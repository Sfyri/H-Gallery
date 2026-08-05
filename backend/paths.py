from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path


SCRIPT_ROOT = Path(__file__).resolve().parent.parent
GALLERY_ROOT = SCRIPT_ROOT.parent
USER_ROOT = GALLERY_ROOT / ".user"
DATA_ROOT = USER_ROOT / "data"
BACKUPS_ROOT = USER_ROOT / "backups"
CACHE_ROOT = SCRIPT_ROOT / "cache"
CONFIG_PATH = SCRIPT_ROOT / "config.json"
EXAMPLE_CONFIG_PATH = SCRIPT_ROOT / "config.example.json"

LEGACY_DATA_ROOT = SCRIPT_ROOT / "data"
LEGACY_BACKUPS_ROOT = SCRIPT_ROOT / "backups"


def ensure_user_layout() -> None:
    """Crea le cartelle persistenti personali nella radice della galleria."""

    USER_ROOT.mkdir(parents=True, exist_ok=True)
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)


def _unique_destination(parent: Path, name: str) -> Path:
    candidate = parent / name
    if not candidate.exists():
        return candidate

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = Path(name).stem
    suffix = Path(name).suffix
    counter = 1
    while True:
        candidate = parent / f"{stem}_migrated_{timestamp}_{counter:02d}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def _move_file_if_needed(source: Path, destination: Path) -> None:
    if not source.is_file():
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    target = destination if not destination.exists() else _unique_destination(
        destination.parent,
        destination.name,
    )
    shutil.move(str(source), str(target))


def _merge_directory(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return

    destination.mkdir(parents=True, exist_ok=True)
    for child in list(source.iterdir()):
        target = destination / child.name
        if child.is_dir():
            if target.exists() and target.is_dir():
                _merge_directory(child, target)
            elif target.exists():
                shutil.move(str(child), str(_unique_destination(destination, child.name)))
            else:
                shutil.move(str(child), str(target))
        else:
            _move_file_if_needed(child, target)

    try:
        source.rmdir()
    except OSError:
        pass


def _migrate_legacy_data() -> None:
    if not LEGACY_DATA_ROOT.is_dir():
        return

    legacy_database = LEGACY_DATA_ROOT / "gallery.db"
    active_database = DATA_ROOT / "gallery.db"

    if legacy_database.exists() and active_database.exists():
        # Se esiste già un database nella nuova posizione, conserva l'intero
        # vecchio gruppo SQLite in una cartella separata senza collegare per
        # errore i vecchi file WAL/SHM al database attivo.
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        preserved = DATA_ROOT / f"legacy_database_{timestamp}"
        counter = 1
        while preserved.exists():
            preserved = DATA_ROOT / f"legacy_database_{timestamp}_{counter:02d}"
            counter += 1
        preserved.mkdir(parents=True)
        for filename in ("gallery.db", "gallery.db-wal", "gallery.db-shm"):
            source = LEGACY_DATA_ROOT / filename
            if source.exists():
                shutil.move(str(source), str(preserved / filename))

    _merge_directory(LEGACY_DATA_ROOT, DATA_ROOT)


def migrate_legacy_user_storage() -> dict[str, bool]:
    """Sposta in `.user` database e backup creati dalle versioni precedenti.

    La cache resta intenzionalmente dentro `.Script`, perché è ricostruibile e
    non fa parte dei dati personali da conservare durante una migrazione.
    """

    ensure_user_layout()
    had_legacy_data = LEGACY_DATA_ROOT.is_dir()
    had_legacy_backups = LEGACY_BACKUPS_ROOT.is_dir()

    if had_legacy_data:
        _migrate_legacy_data()
    if had_legacy_backups:
        _merge_directory(LEGACY_BACKUPS_ROOT, BACKUPS_ROOT)

    return {
        "migrated_data": had_legacy_data,
        "migrated_backups": had_legacy_backups,
    }
