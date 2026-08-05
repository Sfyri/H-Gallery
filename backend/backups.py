from __future__ import annotations

import json
import os
import shutil
import sqlite3
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from backend.database import DATABASE_PATH, get_connection, init_database
from backend.paths import (
    BACKUPS_ROOT,
    CONFIG_PATH,
    DATA_ROOT,
    SCRIPT_ROOT,
    migrate_legacy_user_storage,
)


migrate_legacy_user_storage()
EXPORTS_ROOT = BACKUPS_ROOT / "exports"
MAX_AUTOMATIC_BACKUPS = 10

TABLES_TO_EXPORT = (
    "franchises",
    "characters",
    "files",
    "tags",
    "file_characters",
    "file_tags",
    "operations",
    "trash_items",
)


def _now() -> datetime:
    return datetime.now(timezone.utc).astimezone()


def _timestamp(value: datetime | None = None) -> str:
    return (value or _now()).strftime("%Y%m%d_%H%M%S_%f")


def _iso(value: datetime | None = None) -> str:
    return (value or _now()).isoformat(timespec="seconds")


def _safe_backup_id(backup_id: str) -> str:
    candidate = backup_id.strip()
    if not candidate or candidate in {".", ".."}:
        raise ValueError("Identificatore del backup non valido.")
    if Path(candidate).name != candidate or any(char in candidate for char in ("/", "\\")):
        raise ValueError("Identificatore del backup non valido.")
    return candidate


def _backup_directory(backup_id: str) -> Path:
    safe_id = _safe_backup_id(backup_id)
    path = (BACKUPS_ROOT / safe_id).resolve()
    try:
        path.relative_to(BACKUPS_ROOT.resolve())
    except ValueError as error:
        raise ValueError("Percorso del backup non consentito.") from error
    return path


def _database_backup(destination: Path) -> None:
    init_database()
    destination.parent.mkdir(parents=True, exist_ok=True)

    source_connection = sqlite3.connect(DATABASE_PATH)
    destination_connection = sqlite3.connect(destination)
    try:
        source_connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
        source_connection.backup(destination_connection)
        destination_connection.commit()
    finally:
        destination_connection.close()
        source_connection.close()


def _read_version() -> str:
    version_path = SCRIPT_ROOT / "VERSION.txt"
    try:
        return version_path.read_text(encoding="utf-8").strip() or "sconosciuta"
    except OSError:
        return "sconosciuta"


def _write_manifest(
    directory: Path,
    *,
    backup_id: str,
    backup_type: str,
    reason: str,
    created_at: datetime,
) -> dict[str, Any]:
    database_path = directory / "gallery.db"
    config_path = directory / "config.json"
    manifest = {
        "id": backup_id,
        "type": backup_type,
        "reason": reason,
        "created_at": _iso(created_at),
        "app_version": _read_version(),
        "database_size": database_path.stat().st_size if database_path.exists() else 0,
        "config_included": config_path.exists(),
    }
    (directory / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return manifest


def _load_manifest(directory: Path) -> dict[str, Any] | None:
    manifest_path = directory / "manifest.json"
    database_path = directory / "gallery.db"
    if not directory.is_dir() or not database_path.is_file():
        return None

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        manifest = {
            "id": directory.name,
            "type": "manual" if directory.name.startswith("manual_") else "automatic",
            "reason": "backup_importato",
            "created_at": datetime.fromtimestamp(
                directory.stat().st_mtime,
                tz=timezone.utc,
            ).astimezone().isoformat(timespec="seconds"),
            "app_version": "sconosciuta",
            "database_size": database_path.stat().st_size,
            "config_included": (directory / "config.json").exists(),
        }

    manifest["id"] = directory.name
    manifest["database_size"] = database_path.stat().st_size
    manifest["config_included"] = (directory / "config.json").exists()
    return manifest


def _prune_automatic_backups() -> list[str]:
    automatic: list[tuple[float, Path]] = []
    if not BACKUPS_ROOT.exists():
        return []

    for directory in BACKUPS_ROOT.iterdir():
        if not directory.is_dir() or not directory.name.startswith("auto_"):
            continue
        manifest = _load_manifest(directory)
        if manifest is None:
            continue
        automatic.append((directory.stat().st_mtime, directory))

    automatic.sort(key=lambda item: item[0], reverse=True)
    removed: list[str] = []
    for _, directory in automatic[MAX_AUTOMATIC_BACKUPS:]:
        shutil.rmtree(directory, ignore_errors=False)
        removed.append(directory.name)
    return removed


def create_backup(*, backup_type: str, reason: str) -> dict[str, Any]:
    if backup_type not in {"manual", "automatic"}:
        raise ValueError("Tipo di backup non valido.")

    created_at = _now()
    prefix = "manual" if backup_type == "manual" else "auto"
    backup_id = f"{prefix}_{_timestamp(created_at)}"
    target = BACKUPS_ROOT / backup_id
    target.mkdir(parents=True, exist_ok=False)

    try:
        _database_backup(target / "gallery.db")
        if CONFIG_PATH.exists():
            shutil.copy2(CONFIG_PATH, target / "config.json")
        manifest = _write_manifest(
            target,
            backup_id=backup_id,
            backup_type=backup_type,
            reason=reason,
            created_at=created_at,
        )
    except Exception:
        shutil.rmtree(target, ignore_errors=True)
        raise

    removed = _prune_automatic_backups() if backup_type == "automatic" else []
    return {
        **manifest,
        "path": str(target),
        "pruned_automatic_backups": removed,
    }


def create_manual_backup() -> dict[str, Any]:
    return create_backup(backup_type="manual", reason="manuale")


def create_automatic_backup(reason: str) -> dict[str, Any]:
    return create_backup(backup_type="automatic", reason=reason)


def list_backups() -> dict[str, Any]:
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []

    for directory in BACKUPS_ROOT.iterdir():
        if directory == EXPORTS_ROOT:
            continue
        manifest = _load_manifest(directory)
        if manifest is None:
            continue
        manifest["path"] = str(directory)
        results.append(manifest)

    results.sort(key=lambda item: str(item.get("created_at", "")), reverse=True)
    return {
        "results": results,
        "manual_count": sum(item.get("type") == "manual" for item in results),
        "automatic_count": sum(item.get("type") == "automatic" for item in results),
        "automatic_limit": MAX_AUTOMATIC_BACKUPS,
        "backup_root": str(BACKUPS_ROOT),
    }


def delete_backup(backup_id: str) -> dict[str, Any]:
    directory = _backup_directory(backup_id)
    if not directory.exists():
        raise FileNotFoundError("Backup non trovato.")
    if not (directory / "gallery.db").is_file():
        raise ValueError("La cartella selezionata non contiene un backup valido.")

    shutil.rmtree(directory)
    return {"deleted": backup_id}


def _validate_database(path: Path) -> None:
    if not path.is_file():
        raise FileNotFoundError("Il database del backup non è presente.")
    connection = sqlite3.connect(path)
    try:
        result = connection.execute("PRAGMA integrity_check").fetchone()
    finally:
        connection.close()
    if result is None or str(result[0]).lower() != "ok":
        raise ValueError("Il database del backup non ha superato il controllo di integrità.")


def _validate_config(path: Path) -> None:
    if not path.exists():
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("Il config.json del backup non è valido.") from error
    if not isinstance(data, dict):
        raise ValueError("Il config.json del backup non contiene un oggetto JSON valido.")


def restore_backup(backup_id: str, confirmation: str) -> dict[str, Any]:
    if confirmation.strip().upper() != "RIPRISTINA":
        raise ValueError("Conferma non valida. Scrivi RIPRISTINA.")

    source_directory = _backup_directory(backup_id)
    if not source_directory.exists():
        raise FileNotFoundError("Backup non trovato.")

    source_database = source_directory / "gallery.db"
    source_config = source_directory / "config.json"
    _validate_database(source_database)
    _validate_config(source_config)

    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    restore_database = DATA_ROOT / f".restore_{_timestamp()}.db"
    restore_config = SCRIPT_ROOT / f".restore_{_timestamp()}.json"
    shutil.copy2(source_database, restore_database)
    if source_config.exists():
        shutil.copy2(source_config, restore_config)

    safety_backup: dict[str, Any] | None = None
    try:
        safety_backup = create_automatic_backup("prima_del_ripristino")

        for suffix in ("-wal", "-shm"):
            sidecar = Path(str(DATABASE_PATH) + suffix)
            if sidecar.exists():
                sidecar.unlink()

        os.replace(restore_database, DATABASE_PATH)
        if source_config.exists():
            os.replace(restore_config, CONFIG_PATH)

        init_database()
        _validate_database(DATABASE_PATH)
    finally:
        if restore_database.exists():
            restore_database.unlink(missing_ok=True)
        if restore_config.exists():
            restore_config.unlink(missing_ok=True)

    return {
        "restored": backup_id,
        "safety_backup": safety_backup["id"] if safety_backup else None,
        "message": "Backup ripristinato. Ricarica la pagina per usare i dati ripristinati.",
    }


def _rows_as_dicts(connection: sqlite3.Connection, table_name: str) -> list[dict[str, Any]]:
    rows = connection.execute(f'SELECT * FROM "{table_name}"').fetchall()
    return [dict(row) for row in rows]


def create_metadata_export() -> dict[str, Any]:
    EXPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    filename = f"metadata_{_timestamp()}.json"
    output_path = EXPORTS_ROOT / filename

    config: dict[str, Any] | None = None
    if CONFIG_PATH.exists():
        try:
            config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            config = None

    with get_connection() as connection:
        payload = {
            "exported_at": _iso(),
            "app_version": _read_version(),
            "config": config,
            "tables": {
                table: _rows_as_dicts(connection, table)
                for table in TABLES_TO_EXPORT
            },
        }

    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return {
        "filename": filename,
        "path": str(output_path),
        "size": output_path.stat().st_size,
        "download_url": f"/api/settings/backups/exports/{filename}",
    }


def get_export_path(filename: str) -> Path:
    safe_name = Path(filename).name
    if safe_name != filename or not safe_name.endswith(".json"):
        raise ValueError("Nome del file di esportazione non valido.")
    path = (EXPORTS_ROOT / safe_name).resolve()
    try:
        path.relative_to(EXPORTS_ROOT.resolve())
    except ValueError as error:
        raise ValueError("Percorso dell'esportazione non consentito.") from error
    if not path.is_file():
        raise FileNotFoundError("Esportazione non trovata.")
    return path


def open_backups_folder() -> dict[str, Any]:
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)
    try:
        if os.name == "nt":
            os.startfile(BACKUPS_ROOT)  # type: ignore[attr-defined]
        elif sys_platform() == "darwin":
            subprocess.Popen(["open", str(BACKUPS_ROOT)])
        else:
            subprocess.Popen(["xdg-open", str(BACKUPS_ROOT)])
    except OSError as error:
        raise RuntimeError("Non è stato possibile aprire la cartella dei backup.") from error
    return {"opened": str(BACKUPS_ROOT)}


def sys_platform() -> str:
    import sys

    return sys.platform
