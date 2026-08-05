from __future__ import annotations

import json
import shutil
import re
import unicodedata
from pathlib import Path
from typing import Any
from urllib.parse import quote

from backend.database import get_connection

IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff",
}
VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".webm", ".avi", ".mov", ".m4v",
}

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = PROJECT_ROOT / "config.json"
WINDOWS_RESERVED_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{number}" for number in range(1, 10)),
    *(f"LPT{number}" for number in range(1, 10)),
}
INVALID_WINDOWS_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1F]')


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            "File config.json non trovato. Avvia Install.bat oppure configure.py "
            f"per configurare la galleria: {CONFIG_PATH}"
        )

    with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    gallery_root = config.get("gallery_root")
    if not gallery_root:
        raise ValueError("La voce 'gallery_root' manca in config.json.")

    root_path = Path(gallery_root)
    if not root_path.exists():
        raise FileNotFoundError(f"La cartella della galleria non esiste: {root_path}")
    if not root_path.is_dir():
        raise NotADirectoryError(f"Il percorso non è una cartella: {root_path}")

    return config


def get_media_type(file_path: Path) -> str | None:
    extension = file_path.suffix.lower()
    if extension in IMAGE_EXTENSIONS:
        return "image"
    if extension in VIDEO_EXTENSIONS:
        return "video"
    return None


def normalize_search_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    without_accents = "".join(
        character for character in normalized
        if not unicodedata.combining(character)
    )
    return without_accents.casefold().strip()


def derive_franchise_code(name: str) -> str:
    """Genera un codice leggibile per una nuova serie.

    - Più parole: iniziale di ogni parola ("The Legend of Zelda" -> "TLOZ").
    - Una parola: prime quattro consonanti ("Konosuba" -> "KNSB").

    I codici già salvati nel database non vengono modificati.
    """

    normalized = unicodedata.normalize("NFKD", name)
    ascii_name = normalized.encode("ascii", "ignore").decode("ascii")
    words = [
        "".join(character for character in word if character.isalnum())
        for word in re.split(r"[\s\-_]+", ascii_name.strip())
    ]
    words = [word for word in words if word]

    if not words:
        return "FR"

    if len(words) > 1:
        code = "".join(word[0] for word in words)
        return (code[:10] or "FR").upper()

    word = words[0]
    consonants = "".join(
        character
        for character in word
        if character.isalpha() and character.casefold() not in "aeiou"
    )

    # Nomi composti solo da vocali o numeri devono comunque produrre un codice.
    code = consonants[:4] or word[:4]
    return (code or "FR").upper()


def make_unique_franchise_code(
    connection: Any,
    requested_code: str,
    *,
    exclude_franchise_id: int | None = None,
) -> str:
    """Restituisce un codice univoco aggiungendo 01, 02, 03... se necessario."""

    base_code = validate_franchise_code(requested_code)
    parameters: list[Any] = [base_code]
    exclusion = ""
    if exclude_franchise_id is not None:
        exclusion = " AND id <> ?"
        parameters.append(exclude_franchise_id)

    duplicate = connection.execute(
        f"SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE{exclusion} LIMIT 1",
        parameters,
    ).fetchone()
    if duplicate is None:
        return base_code

    number = 1
    while True:
        suffix = f"{number:02d}"
        available_base_length = max(1, 10 - len(suffix))
        candidate = f"{base_code[:available_base_length]}{suffix}"
        parameters = [candidate]
        if exclude_franchise_id is not None:
            parameters.append(exclude_franchise_id)
        duplicate = connection.execute(
            f"SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE{exclusion} LIMIT 1",
            parameters,
        ).fetchone()
        if duplicate is None:
            return candidate
        number += 1


def validate_folder_name(name: str, *, kind: str) -> str:
    cleaned = name.strip()
    if not cleaned:
        raise ValueError(f"Il nome della {kind} non può essere vuoto.")
    if cleaned in {".", ".."}:
        raise ValueError(f"Nome della {kind} non valido.")
    if cleaned.startswith(".") or cleaned.startswith("!"):
        raise ValueError(f"Il nome della {kind} non può iniziare con '.' oppure '!'.")
    if INVALID_WINDOWS_CHARS.search(cleaned):
        raise ValueError(f"Il nome della {kind} contiene caratteri non validi per Windows.")
    if cleaned.endswith(" ") or cleaned.endswith("."):
        raise ValueError(f"Il nome della {kind} non può terminare con uno spazio o un punto.")
    if cleaned.upper() in WINDOWS_RESERVED_NAMES:
        raise ValueError(f"Il nome '{cleaned}' è riservato da Windows.")
    return cleaned


def validate_franchise_code(code: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]", "", code).upper()
    if not 1 <= len(cleaned) <= 10:
        raise ValueError("Il codice della serie deve contenere da 1 a 10 lettere o numeri.")
    return cleaned


def get_franchise_folders(config: dict[str, Any]) -> list[Path]:
    gallery_root = Path(config["gallery_root"]).resolve()
    ignored = {
        config.get("script_folder", ".Script"),
        config.get("todo_folder", ".toDo"),
        config.get("trash_folder", ".trash"),
        config.get("crossovers_folder", "!Crossovers"),
    }

    return sorted(
        (
            path for path in gallery_root.iterdir()
            if path.is_dir()
            and path.name not in ignored
            and not path.name.startswith(".")
            and not path.name.startswith("!")
        ),
        key=lambda path: path.name.casefold(),
    )


def get_character_folders(franchise_path: Path, config: dict[str, Any]) -> list[Path]:
    special_names = {
        config.get("multiple_folder", "!Multiple"),
        config.get("ai_folder", ".AI"),
    }

    return sorted(
        (
            path for path in franchise_path.iterdir()
            if path.is_dir()
            and path.name not in special_names
            and not path.name.startswith(".")
            and not path.name.startswith("!")
        ),
        key=lambda path: path.name.casefold(),
    )


def sync_characters() -> dict[str, int]:
    """Sincronizza serie e personaggi presenti sul disco senza sovrascrivere i codici salvati."""

    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    configured_codes = config.get("franchise_codes", {})

    franchise_count = 0
    character_count = 0
    created_franchises = 0
    created_characters = 0

    with get_connection() as connection:
        connection.execute("UPDATE franchises SET is_active = 0")
        connection.execute("UPDATE characters SET is_active = 0")

        for franchise_path in get_franchise_folders(config):
            franchise_name = franchise_path.name
            franchise_relative = franchise_path.relative_to(gallery_root).as_posix()

            existing_franchise = connection.execute(
                """
                SELECT id, code
                FROM franchises
                WHERE name = ? OR relative_path = ?
                ORDER BY CASE WHEN relative_path = ? THEN 0 ELSE 1 END
                LIMIT 1
                """,
                (franchise_name, franchise_relative, franchise_relative),
            ).fetchone()

            if existing_franchise:
                franchise_id = int(existing_franchise["id"])
                franchise_code = str(existing_franchise["code"])
                connection.execute(
                    """
                    UPDATE franchises
                    SET name = ?, relative_path = ?, is_active = 1
                    WHERE id = ?
                    """,
                    (franchise_name, franchise_relative, franchise_id),
                )
            else:
                franchise_code = make_unique_franchise_code(
                    connection,
                    str(
                        configured_codes.get(franchise_name)
                        or derive_franchise_code(franchise_name)
                    ),
                )
                cursor = connection.execute(
                    """
                    INSERT INTO franchises(name, code, relative_path, is_active)
                    VALUES (?, ?, ?, 1)
                    """,
                    (franchise_name, franchise_code, franchise_relative),
                )
                franchise_id = int(cursor.lastrowid)
                created_franchises += 1

            franchise_count += 1

            for character_path in get_character_folders(franchise_path, config):
                character_relative = character_path.relative_to(gallery_root).as_posix()
                existing_character = connection.execute(
                    """
                    SELECT id
                    FROM characters
                    WHERE (franchise_id = ? AND name = ?) OR relative_path = ?
                    LIMIT 1
                    """,
                    (franchise_id, character_path.name, character_relative),
                ).fetchone()

                if existing_character:
                    connection.execute(
                        """
                        UPDATE characters
                        SET franchise_id = ?, name = ?, relative_path = ?, is_active = 1
                        WHERE id = ?
                        """,
                        (
                            franchise_id,
                            character_path.name,
                            character_relative,
                            int(existing_character["id"]),
                        ),
                    )
                else:
                    connection.execute(
                        """
                        INSERT INTO characters(franchise_id, name, relative_path, is_active)
                        VALUES (?, ?, ?, 1)
                        """,
                        (franchise_id, character_path.name, character_relative),
                    )
                    created_characters += 1

                character_count += 1

    return {
        "franchises": franchise_count,
        "characters": character_count,
        "created_franchises": created_franchises,
        "created_characters": created_characters,
    }


def list_franchises() -> list[dict[str, Any]]:
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, name, code, relative_path
            FROM franchises
            WHERE is_active = 1
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()

    return [
        {
            "id": int(row["id"]),
            "name": str(row["name"]),
            "code": str(row["code"]),
            "relative_path": str(row["relative_path"]),
        }
        for row in rows
    ]


def create_franchise(name: str, code: str | None = None) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    franchise_name = validate_folder_name(name, kind="serie")
    requested_code = code or derive_franchise_code(franchise_name)

    reserved = {
        config.get("script_folder", ".Script").casefold(),
        config.get("todo_folder", ".toDo").casefold(),
        config.get("crossovers_folder", "!Crossovers").casefold(),
    }
    if franchise_name.casefold() in reserved:
        raise ValueError("Questo nome è riservato dal programma.")

    destination = (gallery_root / franchise_name).resolve()
    try:
        destination.relative_to(gallery_root)
    except ValueError as error:
        raise ValueError("Percorso della serie non valido.") from error

    with get_connection() as connection:
        duplicate = connection.execute(
            "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE",
            (franchise_name,),
        ).fetchone()
        if duplicate:
            raise ValueError("Esiste già una serie con questo nome.")

        franchise_code = make_unique_franchise_code(connection, requested_code)

        if destination.exists() and not destination.is_dir():
            raise ValueError("Esiste già un file con il nome scelto per la serie.")
        destination.mkdir(parents=False, exist_ok=True)

        cursor = connection.execute(
            """
            INSERT INTO franchises(name, code, relative_path, is_active)
            VALUES (?, ?, ?, 1)
            """,
            (franchise_name, franchise_code, destination.relative_to(gallery_root).as_posix()),
        )
        franchise_id = int(cursor.lastrowid)

    return {
        "id": franchise_id,
        "name": franchise_name,
        "code": franchise_code,
        "relative_path": destination.relative_to(gallery_root).as_posix(),
    }


def create_character(franchise_id: int, name: str) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    character_name = validate_folder_name(name, kind="personaggio")

    special_names = {
        config.get("multiple_folder", "!Multiple").casefold(),
        config.get("ai_folder", ".AI").casefold(),
    }
    if character_name.casefold() in special_names:
        raise ValueError("Questo nome è riservato dal programma.")

    with get_connection() as connection:
        franchise = connection.execute(
            """
            SELECT id, name, code, relative_path
            FROM franchises
            WHERE id = ? AND is_active = 1
            """,
            (franchise_id,),
        ).fetchone()
        if franchise is None:
            raise ValueError("Serie non trovata.")

        duplicate = connection.execute(
            """
            SELECT id
            FROM characters
            WHERE franchise_id = ? AND name = ? COLLATE NOCASE
            """,
            (franchise_id, character_name),
        ).fetchone()
        if duplicate:
            raise ValueError("Questo personaggio esiste già nella serie selezionata.")

        franchise_path = (gallery_root / str(franchise["relative_path"])).resolve()
        destination = (franchise_path / character_name).resolve()
        try:
            destination.relative_to(franchise_path)
        except ValueError as error:
            raise ValueError("Percorso del personaggio non valido.") from error

        if destination.exists() and not destination.is_dir():
            raise ValueError("Esiste già un file con il nome scelto per il personaggio.")
        destination.mkdir(parents=True, exist_ok=True)

        relative_path = destination.relative_to(gallery_root).as_posix()
        cursor = connection.execute(
            """
            INSERT INTO characters(franchise_id, name, relative_path, is_active)
            VALUES (?, ?, ?, 1)
            """,
            (franchise_id, character_name, relative_path),
        )
        character_id = int(cursor.lastrowid)

    return {
        "id": character_id,
        "name": character_name,
        "franchise_name": str(franchise["name"]),
        "franchise_code": str(franchise["code"]),
        "relative_path": relative_path,
        "score": 0,
        "label": f"{franchise['name']} / {character_name}",
    }


def search_characters(query: str, limit: int = 20) -> list[dict[str, Any]]:
    normalized_query = normalize_search_text(query)
    if not normalized_query:
        return []

    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT
                characters.id,
                characters.name,
                characters.relative_path,
                characters.score,
                franchises.name AS franchise_name,
                franchises.code AS franchise_code
            FROM characters
            JOIN franchises ON franchises.id = characters.franchise_id
            WHERE characters.is_active = 1
              AND franchises.is_active = 1
            """
        ).fetchall()

    ranked_results: list[tuple[int, str, dict[str, Any]]] = []

    for row in rows:
        character_name = str(row["name"])
        franchise_name = str(row["franchise_name"])
        normalized_name = normalize_search_text(character_name)
        normalized_label = normalize_search_text(f"{franchise_name} {character_name}")

        if normalized_query == normalized_name:
            rank = 0
        elif normalized_name.startswith(normalized_query):
            rank = 1
        elif normalized_query in normalized_name:
            rank = 2
        elif all(part in normalized_label for part in normalized_query.split()):
            rank = 3
        else:
            continue

        result = {
            "id": int(row["id"]),
            "name": character_name,
            "franchise_name": franchise_name,
            "franchise_code": str(row["franchise_code"]),
            "relative_path": str(row["relative_path"]),
            "score": int(row["score"]),
            "label": f"{franchise_name} / {character_name}",
        }
        ranked_results.append((rank, normalized_name, result))

    ranked_results.sort(key=lambda item: (item[0], item[1], item[2]["franchise_name"].casefold()))
    return [item[2] for item in ranked_results[:limit]]


def list_todo_files() -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    todo_folder_name = config.get("todo_folder", ".toDo")
    todo_root = (gallery_root / todo_folder_name).resolve()

    if not todo_root.exists():
        return {
            "folder": todo_folder_name,
            "display_name": "New",
            "path": str(todo_root),
            "exists": False,
            "files": [],
            "total_files": 0,
        }

    files: list[dict[str, Any]] = []

    for file_path in sorted(todo_root.rglob("*"), key=lambda path: str(path).casefold()):
        if not file_path.is_file():
            continue

        media_type = get_media_type(file_path)
        if media_type is None:
            continue

        try:
            file_info = file_path.stat()
        except OSError:
            continue

        relative_path = file_path.relative_to(todo_root).as_posix()
        files.append(
            {
                "name": file_path.name,
                "relative_path": relative_path,
                "extension": file_path.suffix.lower(),
                "media_type": media_type,
                "size": file_info.st_size,
                "modified_at": file_info.st_mtime,
                "media_url": "/media/todo/" + quote(relative_path, safe="/"),
                "thumbnail_url": (
                    "/api/thumbnails/new?relative_path="
                    + quote(relative_path, safe="")
                    + f"&v={file_info.st_size}-{int(file_info.st_mtime * 1000)}-1"
                ),
                "animated_preview_url": (
                    "/api/thumbnails/new/preview?relative_path="
                    + quote(relative_path, safe="")
                    + f"&v={file_info.st_size}-{int(file_info.st_mtime * 1000)}-1"
                    if (media_type == "video" and shutil.which("ffmpeg"))
                    or file_path.suffix.lower() == ".gif"
                    else None
                ),
            }
        )

    return {
        "folder": todo_folder_name,
        "display_name": "New",
        "path": str(todo_root),
        "exists": True,
        "files": files,
        "total_files": len(files),
    }


def scan_gallery() -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    franchises: list[dict[str, Any]] = []
    total_images = 0
    total_videos = 0

    for franchise_path in get_franchise_folders(config):
        images = 0
        videos = 0

        for file_path in franchise_path.rglob("*"):
            if not file_path.is_file():
                continue
            media_type = get_media_type(file_path)
            if media_type == "image":
                images += 1
            elif media_type == "video":
                videos += 1

        characters = get_character_folders(franchise_path, config)
        franchises.append(
            {
                "name": franchise_path.name,
                "path": str(franchise_path),
                "character_folders": len(characters),
                "images": images,
                "videos": videos,
                "total_files": images + videos,
            }
        )
        total_images += images
        total_videos += videos

    todo = list_todo_files()

    return {
        "gallery_root": str(gallery_root),
        "franchises": franchises,
        "todo": {
            "name": todo["folder"],
            "path": todo["path"],
            "total_files": todo["total_files"],
            "exists": todo["exists"],
        },
        "summary": {
            "franchises": len(franchises),
            "images": total_images,
            "videos": total_videos,
            "total_files": total_images + total_videos,
        },
    }
