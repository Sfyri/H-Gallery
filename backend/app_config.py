from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

APP_NAME = "H-Gallery"
REGISTRY_VERSION = 1


def _now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def get_user_config_root() -> Path:
    """Restituisce la cartella di configurazione privata dell'applicazione."""

    if os.name == "nt":
        base = os.environ.get("APPDATA")
        if base:
            return Path(base) / APP_NAME
        return Path.home() / "AppData" / "Roaming" / APP_NAME

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME

    base = os.environ.get("XDG_CONFIG_HOME")
    if base:
        return Path(base) / "h-gallery"
    return Path.home() / ".config" / "h-gallery"


def get_user_cache_root() -> Path:
    """Restituisce la cartella della cache ricostruibile dell'applicazione."""

    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA")
        if base:
            return Path(base) / APP_NAME / "cache"
        return Path.home() / "AppData" / "Local" / APP_NAME / "cache"

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Caches" / APP_NAME

    base = os.environ.get("XDG_CACHE_HOME")
    if base:
        return Path(base) / "h-gallery"
    return Path.home() / ".cache" / "h-gallery"


REGISTRY_PATH = get_user_config_root() / "galleries.json"


def _empty_registry() -> dict[str, Any]:
    return {
        "version": REGISTRY_VERSION,
        "active_gallery_id": None,
        "galleries": [],
    }


def _normalize_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    try:
        path = path.resolve(strict=False)
    except OSError:
        path = path.absolute()

    # Se l'utente seleziona per errore la vecchia cartella .Script, usa la
    # cartella padre che contiene realmente l'archivio.
    if path.name.casefold() == ".script":
        path = path.parent
    return path


def _atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def load_registry() -> dict[str, Any]:
    if not REGISTRY_PATH.exists():
        return _empty_registry()

    try:
        data = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(
            f"Configurazione delle gallerie non leggibile: {REGISTRY_PATH}"
        ) from error

    if not isinstance(data, dict):
        raise ValueError("La configurazione delle gallerie non è valida.")

    galleries = data.get("galleries")
    if not isinstance(galleries, list):
        galleries = []

    normalized: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for raw in galleries:
        if not isinstance(raw, dict):
            continue
        gallery_id = str(raw.get("id") or "").strip()
        path_value = str(raw.get("path") or "").strip()
        if not gallery_id or not path_value or gallery_id in seen_ids:
            continue
        path = _normalize_path(path_value)
        path_key = os.path.normcase(str(path))
        if path_key in seen_paths:
            continue
        name = str(raw.get("name") or path.name or "Galleria").strip() or "Galleria"
        normalized.append(
            {
                "id": gallery_id,
                "name": name,
                "path": str(path),
                "added_at": str(raw.get("added_at") or _now_iso()),
            }
        )
        seen_ids.add(gallery_id)
        seen_paths.add(path_key)

    active_id = str(data.get("active_gallery_id") or "").strip() or None
    if active_id not in seen_ids:
        active_id = normalized[0]["id"] if normalized else None

    return {
        "version": REGISTRY_VERSION,
        "active_gallery_id": active_id,
        "galleries": normalized,
    }


def save_registry(registry: dict[str, Any]) -> None:
    _atomic_write_json(REGISTRY_PATH, registry)


def ensure_gallery_layout(gallery_root: str | Path) -> Path:
    root = _normalize_path(gallery_root)
    root.mkdir(parents=True, exist_ok=True)
    if not root.is_dir():
        raise NotADirectoryError(f"Il percorso non è una cartella: {root}")

    for relative in (".user/data", ".user/backups", ".toDo", ".trash"):
        (root / relative).mkdir(parents=True, exist_ok=True)
    return root


def register_gallery(
    gallery_root: str | Path,
    *,
    name: str | None = None,
    make_active: bool = True,
    create_layout: bool = True,
) -> dict[str, Any]:
    root = _normalize_path(gallery_root)
    if create_layout:
        root = ensure_gallery_layout(root)
    elif not root.is_dir():
        raise NotADirectoryError(f"Galleria non trovata: {root}")

    registry = load_registry()
    path_key = os.path.normcase(str(root))
    entry: dict[str, Any] | None = None
    for candidate in registry["galleries"]:
        if os.path.normcase(str(_normalize_path(candidate["path"]))) == path_key:
            entry = candidate
            break

    clean_name = (name or root.name or "Galleria").strip() or "Galleria"
    if entry is None:
        entry = {
            "id": uuid.uuid4().hex,
            "name": clean_name,
            "path": str(root),
            "added_at": _now_iso(),
        }
        registry["galleries"].append(entry)
    else:
        entry["path"] = str(root)
        if name is not None:
            entry["name"] = clean_name

    if make_active:
        registry["active_gallery_id"] = entry["id"]
    save_registry(registry)
    return dict(entry)


def remove_gallery(gallery_id: str) -> dict[str, Any]:
    registry = load_registry()
    galleries = registry["galleries"]
    removed = next((item for item in galleries if item["id"] == gallery_id), None)
    if removed is None:
        raise ValueError("Galleria non trovata nella configurazione.")

    registry["galleries"] = [item for item in galleries if item["id"] != gallery_id]
    if registry.get("active_gallery_id") == gallery_id:
        registry["active_gallery_id"] = (
            registry["galleries"][0]["id"] if registry["galleries"] else None
        )
    save_registry(registry)
    return dict(removed)


def set_active_gallery(gallery_id: str) -> dict[str, Any]:
    registry = load_registry()
    entry = next(
        (item for item in registry["galleries"] if item["id"] == gallery_id),
        None,
    )
    if entry is None:
        raise ValueError("Galleria non trovata nella configurazione.")
    root = _normalize_path(entry["path"])
    if not root.is_dir():
        raise NotADirectoryError(f"La galleria non è accessibile: {root}")
    registry["active_gallery_id"] = gallery_id
    save_registry(registry)
    return dict(entry)


def detect_legacy_gallery(script_root: str | Path) -> Path | None:
    script = Path(script_root).expanduser()
    try:
        script = script.resolve(strict=False)
    except OSError:
        script = script.absolute()
    if script.name.casefold() != ".script":
        return None
    parent = script.parent
    indicators = (
        parent / ".user",
        parent / ".toDo",
        parent / ".trash",
    )
    if parent.is_dir() and any(path.exists() for path in indicators):
        return parent
    return None


def get_active_gallery(
    *,
    script_root: str | Path | None = None,
    allow_legacy_registration: bool = True,
) -> dict[str, Any]:
    registry = load_registry()
    active_id = registry.get("active_gallery_id")
    entry = next(
        (item for item in registry["galleries"] if item["id"] == active_id),
        None,
    )

    if entry is None and allow_legacy_registration and script_root is not None:
        legacy = detect_legacy_gallery(script_root)
        if legacy is not None:
            entry = register_gallery(
                legacy,
                name=legacy.name,
                make_active=True,
                create_layout=True,
            )

    if entry is None:
        raise RuntimeError(
            "Nessuna galleria configurata. Avvia configure.py oppure "
            "Reconfigure.bat e seleziona una cartella."
        )

    root = _normalize_path(entry["path"])
    if not root.is_dir():
        raise NotADirectoryError(
            f"La galleria attiva non è accessibile: {root}. "
            "Avvia Reconfigure.bat per sceglierne un'altra."
        )
    entry = dict(entry)
    entry["path"] = str(root)
    return entry


def list_galleries(*, script_root: str | Path | None = None) -> dict[str, Any]:
    try:
        active = get_active_gallery(script_root=script_root)
        active_id = active["id"]
    except (RuntimeError, NotADirectoryError):
        active_id = None

    registry = load_registry()
    results = []
    for item in registry["galleries"]:
        path = _normalize_path(item["path"])
        results.append(
            {
                **item,
                "path": str(path),
                "active": item["id"] == active_id,
                "available": path.is_dir(),
                "legacy_script_present": (path / ".Script").is_dir(),
            }
        )
    return {
        "active_gallery_id": active_id,
        "registry_path": str(REGISTRY_PATH),
        "results": results,
    }
