from __future__ import annotations

import json
import sys
from pathlib import Path

from backend.paths import (
    BACKUPS_ROOT,
    CONFIG_PATH,
    DATA_ROOT,
    EXAMPLE_CONFIG_PATH,
    GALLERY_ROOT,
    migrate_legacy_user_storage,
)


def _read_json(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise FileNotFoundError(f"File di configurazione non trovato: {path}")

    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError(f"{path.name} non contiene un oggetto JSON valido.")
    return data


def configure() -> Path:
    """Crea o aggiorna config.json usando la struttura portabile standard."""

    defaults = _read_json(EXAMPLE_CONFIG_PATH)
    current: dict[str, object] = {}
    if CONFIG_PATH.exists():
        current = _read_json(CONFIG_PATH)

    # Le impostazioni già personalizzate prevalgono sui valori di esempio.
    config = {**defaults, **current}
    config.pop("gallery_root", None)

    migrate_legacy_user_storage()
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    BACKUPS_ROOT.mkdir(parents=True, exist_ok=True)

    todo_folder = str(config.get("todo_folder", ".toDo"))
    trash_folder = str(config.get("trash_folder", ".trash"))
    for folder_name in (todo_folder, trash_folder):
        (GALLERY_ROOT / folder_name).mkdir(parents=True, exist_ok=True)

    temporary_path = CONFIG_PATH.with_suffix(".json.tmp")
    temporary_path.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(CONFIG_PATH)

    print("\nConfigurazione completata.")
    print(f"Galleria rilevata automaticamente: {GALLERY_ROOT}")
    print(f"Dati personali: {DATA_ROOT.parent}")
    print(f"File di configurazione: {CONFIG_PATH}")
    return CONFIG_PATH


def main() -> int:
    try:
        configure()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"\nErrore durante la configurazione: {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
