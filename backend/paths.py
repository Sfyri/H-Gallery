from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path

from backend.app_config import get_active_gallery, get_user_cache_root
from backend.resources import CONFIG_EXAMPLE_PATH


SCRIPT_ROOT = Path(__file__).resolve().parent.parent
_ACTIVE_GALLERY = get_active_gallery(script_root=SCRIPT_ROOT)
GALLERY_ID = str(_ACTIVE_GALLERY["id"])
GALLERY_NAME = str(_ACTIVE_GALLERY["name"])
GALLERY_ROOT = Path(str(_ACTIVE_GALLERY["path"])).resolve()

USER_ROOT = GALLERY_ROOT / ".user"
DATA_ROOT = USER_ROOT / "data"
BACKUPS_ROOT = USER_ROOT / "backups"
CACHE_ROOT = get_user_cache_root() / GALLERY_ID
CONFIG_PATH = USER_ROOT / "config.json"
EXAMPLE_CONFIG_PATH = CONFIG_EXAMPLE_PATH

LEGACY_CONFIG_PATH = SCRIPT_ROOT / "config.json"
LEGACY_DATA_ROOT = SCRIPT_ROOT / "data"
LEGACY_BACKUPS_ROOT = SCRIPT_ROOT / "backups"
LEGACY_CACHE_ROOT = SCRIPT_ROOT / "cache"
IS_LEGACY_PORTABLE = SCRIPT_ROOT.parent.resolve() == GALLERY_ROOT.resolve()


def ensure_user_layout() -> None:
    """Crea le cartelle persistenti personali nella radice della galleria."""

    USER_ROOT.mkdir(parents=True, exist_ok=True)
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)


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


def _copy_legacy_config_if_needed() -> bool:
    """Copia la vecchia configurazione nella galleria senza cancellarla."""

    if (
        not IS_LEGACY_PORTABLE
        or CONFIG_PATH.exists()
        or not LEGACY_CONFIG_PATH.is_file()
    ):
        return False
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(LEGACY_CONFIG_PATH, CONFIG_PATH)
    return True


def migrate_legacy_user_storage() -> dict[str, bool]:
    """Porta i dati persistenti fuori dalla cartella del programma.

    Il vecchio ``config.json`` viene copiato in ``.user/config.json`` e viene
    lasciato al suo posto per permettere un ritorno alla versione precedente.
    La vecchia cache non viene spostata perché è ricostruibile.
    """

    ensure_user_layout()
    copied_config = _copy_legacy_config_if_needed()
    had_legacy_data = IS_LEGACY_PORTABLE and LEGACY_DATA_ROOT.is_dir()
    had_legacy_backups = IS_LEGACY_PORTABLE and LEGACY_BACKUPS_ROOT.is_dir()

    if had_legacy_data:
        _migrate_legacy_data()
    if had_legacy_backups:
        _merge_directory(LEGACY_BACKUPS_ROOT, BACKUPS_ROOT)

    return {
        "copied_config": copied_config,
        "migrated_data": had_legacy_data,
        "migrated_backups": had_legacy_backups,
    }
