from __future__ import annotations

import json
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent
CONFIG_PATH = PROJECT_ROOT / "config.json"
EXAMPLE_PATH = PROJECT_ROOT / "config.example.json"


def _answer_is_yes(value: str, *, default: bool = True) -> bool:
    normalized = value.strip().casefold()
    if not normalized:
        return default
    return normalized in {"s", "si", "sì", "y", "yes"}


def _read_example() -> dict[str, object]:
    if not EXAMPLE_PATH.is_file():
        raise FileNotFoundError(
            f"File di configurazione di esempio non trovato: {EXAMPLE_PATH}"
        )

    with EXAMPLE_PATH.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, dict):
        raise ValueError("config.example.json non contiene un oggetto JSON valido.")
    return data


def _request_gallery_root() -> Path:
    while True:
        print("\nInserisci il percorso completo della cartella che conterrà la galleria.")
        print(r"Esempio: E:\ArchivioPersonaggi")
        raw_value = input("> ").strip().strip('"')

        if not raw_value:
            print("Il percorso non può essere vuoto.")
            continue

        gallery_root = Path(raw_value).expanduser()
        try:
            gallery_root = gallery_root.resolve()
        except OSError as error:
            print(f"Percorso non valido: {error}")
            continue

        if gallery_root.exists():
            if not gallery_root.is_dir():
                print("Il percorso esiste ma non è una cartella.")
                continue
            return gallery_root

        create = input("La cartella non esiste. Vuoi crearla? [S/n]: ")
        if not _answer_is_yes(create, default=True):
            continue

        try:
            gallery_root.mkdir(parents=True, exist_ok=True)
        except OSError as error:
            print(f"Impossibile creare la cartella: {error}")
            continue
        return gallery_root


def configure() -> Path:
    if CONFIG_PATH.exists():
        overwrite = input(
            "Esiste già config.json. Vuoi riconfigurare il percorso della galleria? [s/N]: "
        )
        if not _answer_is_yes(overwrite, default=False):
            print("Configurazione lasciata invariata.")
            return CONFIG_PATH

    config = _read_example()
    gallery_root = _request_gallery_root()
    config["gallery_root"] = str(gallery_root)
    config["franchise_codes"] = {}

    todo_folder = str(config.get("todo_folder", ".toDo"))
    trash_folder = str(config.get("trash_folder", ".trash"))

    for folder_name in (todo_folder, trash_folder):
        (gallery_root / folder_name).mkdir(parents=True, exist_ok=True)

    temporary_path = CONFIG_PATH.with_suffix(".json.tmp")
    temporary_path.write_text(
        json.dumps(config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary_path.replace(CONFIG_PATH)

    print("\nConfigurazione completata.")
    print(f"Galleria: {gallery_root}")
    print(f"File: {CONFIG_PATH}")
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
