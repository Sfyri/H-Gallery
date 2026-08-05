from __future__ import annotations

import hashlib
import re
import shutil
import unicodedata
from pathlib import Path
from typing import Any

from backend.database import get_connection
from backend.scanner import get_media_type, load_config


def normalize_filename_component(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    cleaned = re.sub(r"[^A-Za-z0-9]+", "", ascii_value)
    return cleaned or "Unknown"


def calculate_sha256(file_path: Path) -> str:
    digest = hashlib.sha256()
    with file_path.open("rb") as source_file:
        for chunk in iter(lambda: source_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def get_characters_by_ids(character_ids: list[int]) -> list[dict[str, Any]]:
    unique_ids = list(dict.fromkeys(character_ids))
    if not unique_ids:
        raise ValueError("Seleziona almeno un personaggio.")

    placeholders = ",".join("?" for _ in unique_ids)

    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT
                characters.id,
                characters.name,
                characters.relative_path,
                franchises.id AS franchise_id,
                franchises.name AS franchise_name,
                franchises.code AS franchise_code,
                franchises.relative_path AS franchise_relative_path
            FROM characters
            JOIN franchises ON franchises.id = characters.franchise_id
            WHERE characters.id IN ({placeholders})
              AND characters.is_active = 1
              AND franchises.is_active = 1
            """,
            unique_ids,
        ).fetchall()

    found = {int(row["id"]): dict(row) for row in rows}
    missing = [character_id for character_id in unique_ids if character_id not in found]
    if missing:
        raise ValueError(f"Personaggi non validi o non più disponibili: {missing}")

    return [found[character_id] for character_id in unique_ids]


def determine_destination(
    characters: list[dict[str, Any]],
    ai_generated: bool,
) -> tuple[Path, str, str]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    ai_folder = config.get("ai_folder", ".AI")
    multiple_folder = config.get("multiple_folder", "!Multiple")
    crossovers_folder = config.get("crossovers_folder", "!Crossovers")

    franchise_ids = {int(character["franchise_id"]) for character in characters}

    if len(characters) == 1:
        character = characters[0]
        destination = gallery_root / str(character["relative_path"])
        prefix = (
            str(character["franchise_code"])
            + normalize_filename_component(str(character["name"]))
        )
        category = "single"
    elif len(franchise_ids) == 1:
        franchise = characters[0]
        destination = (
            gallery_root
            / str(franchise["franchise_relative_path"])
            / multiple_folder
        )
        prefix = str(franchise["franchise_code"]) + "Multiple"
        category = "multiple"
    else:
        destination = gallery_root / crossovers_folder
        prefix = "Crossover"
        category = "crossover"

    if ai_generated:
        destination = destination / ai_folder

    return destination.resolve(), prefix, category


def find_next_filename(destination: Path, prefix: str, extension: str) -> str:
    logical_root = destination
    if destination.name == load_config().get("ai_folder", ".AI"):
        logical_root = destination.parent

    pattern = re.compile(rf"^{re.escape(prefix)}_(\d{{6}})$", re.IGNORECASE)
    maximum = 0

    if logical_root.exists():
        for file_path in logical_root.rglob("*"):
            if not file_path.is_file():
                continue
            match = pattern.match(file_path.stem)
            if match:
                maximum = max(maximum, int(match.group(1)))

    return f"{prefix}_{maximum + 1:06d}{extension.lower()}"


def preview_organization(
    character_ids: list[int],
    ai_generated: bool,
    extension: str,
) -> dict[str, Any]:
    characters = get_characters_by_ids(character_ids)
    destination, prefix, category = determine_destination(characters, ai_generated)
    filename = find_next_filename(destination, prefix, extension)
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()

    return {
        "category": category,
        "destination_folder": destination.relative_to(gallery_root).as_posix(),
        "filename": filename,
        "destination_relative_path": (
            destination.relative_to(gallery_root) / filename
        ).as_posix(),
    }


def find_duplicate(sha256: str) -> dict[str, Any] | None:
    """Trova un duplicato reale e ripulisce eventuali record rimasti orfani."""

    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()

    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, filename, relative_path, media_type, size, ai_generated
            FROM files
            WHERE sha256 = ? AND is_trashed = 0
            ORDER BY id
            """,
            (sha256,),
        ).fetchall()

        for row in rows:
            stored_file = (gallery_root / str(row["relative_path"])).resolve()
            try:
                stored_file.relative_to(gallery_root)
            except ValueError:
                connection.execute("DELETE FROM files WHERE id = ?", (int(row["id"]),))
                continue

            if stored_file.exists() and stored_file.is_file():
                return dict(row)

            connection.execute("DELETE FROM files WHERE id = ?", (int(row["id"]),))

    return None


def organize_file(
    relative_path: str,
    character_ids: list[int],
    tags: list[str],
    ai_generated: bool,
    allow_duplicate: bool = False,
) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    todo_root = (gallery_root / config.get("todo_folder", ".toDo")).resolve()
    source = (todo_root / relative_path).resolve()

    try:
        source.relative_to(todo_root)
    except ValueError as error:
        raise PermissionError("Il file richiesto non appartiene a New.") from error

    if not source.exists() or not source.is_file():
        raise FileNotFoundError(f"File non trovato in New: {relative_path}")

    media_type = get_media_type(source)
    if media_type is None:
        raise ValueError("Il formato del file non è supportato.")

    characters = get_characters_by_ids(character_ids)
    destination, prefix, category = determine_destination(characters, ai_generated)
    destination.mkdir(parents=True, exist_ok=True)

    sha256 = calculate_sha256(source)
    duplicate = find_duplicate(sha256)
    if duplicate and not allow_duplicate:
        return {
            "status": "duplicate",
            "duplicate": duplicate,
            "sha256": sha256,
        }

    filename = find_next_filename(destination, prefix, source.suffix)
    destination_file = destination / filename

    if destination_file.exists():
        raise FileExistsError(f"Il file di destinazione esiste già: {destination_file}")

    source_relative = source.relative_to(gallery_root).as_posix()
    destination_relative = destination_file.relative_to(gallery_root).as_posix()
    source_stat = source.stat()
    file_size = source_stat.st_size

    shutil.move(str(source), str(destination_file))

    normalized_tags = []
    seen_tags: set[str] = set()
    for tag in tags:
        cleaned = tag.strip()
        if not cleaned:
            continue
        folded = cleaned.casefold()
        if folded not in seen_tags:
            normalized_tags.append(cleaned)
            seen_tags.add(folded)

    if ai_generated and "ai" not in seen_tags:
        normalized_tags.append("AI")

    try:
        with get_connection() as connection:
            # Se il percorso era rimasto nel database dopo una cancellazione manuale,
            # il record orfano viene eliminato prima di registrare il nuovo file.
            stale_destination = connection.execute(
                "SELECT id FROM files WHERE relative_path = ?",
                (destination_relative,),
            ).fetchone()
            if stale_destination is not None:
                connection.execute(
                    "DELETE FROM files WHERE id = ?",
                    (int(stale_destination["id"]),),
                )

            cursor = connection.execute(
                """
                INSERT INTO files(
                    filename, relative_path, media_type, extension,
                    size, sha256, ai_generated, modified_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    filename,
                    destination_relative,
                    media_type,
                    source.suffix.lower(),
                    file_size,
                    sha256,
                    int(ai_generated),
                    destination_file.stat().st_mtime,
                ),
            )
            file_id = int(cursor.lastrowid)

            connection.executemany(
                "INSERT INTO file_characters(file_id, character_id) VALUES (?, ?)",
                [(file_id, int(character["id"])) for character in characters],
            )

            for tag_name in normalized_tags:
                connection.execute(
                    "INSERT INTO tags(name) VALUES (?) ON CONFLICT(name) DO NOTHING",
                    (tag_name,),
                )
                tag_row = connection.execute(
                    "SELECT id FROM tags WHERE name = ? COLLATE NOCASE",
                    (tag_name,),
                ).fetchone()
                connection.execute(
                    "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                    (file_id, int(tag_row["id"])),
                )

            connection.execute(
                """
                INSERT INTO operations(
                    operation_type, source_relative_path, destination_relative_path
                )
                VALUES ('organize', ?, ?)
                """,
                (source_relative, destination_relative),
            )
    except Exception:
        destination_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(destination_file), str(source))
        raise

    return {
        "status": "organized",
        "category": category,
        "filename": filename,
        "relative_path": destination_relative,
        "characters": [
            {
                "id": int(character["id"]),
                "name": str(character["name"]),
                "franchise_name": str(character["franchise_name"]),
            }
            for character in characters
        ],
        "tags": normalized_tags,
        "ai_generated": ai_generated,
        "sha256": sha256,
    }


def update_character_score(character_id: int, delta: int) -> dict[str, Any]:
    if delta not in {-1, 1}:
        raise ValueError("Il valore delta deve essere -1 oppure 1.")

    with get_connection() as connection:
        row = connection.execute(
            "SELECT id, score FROM characters WHERE id = ? AND is_active = 1",
            (character_id,),
        ).fetchone()
        if row is None:
            raise ValueError("Personaggio non trovato.")

        new_score = max(0, int(row["score"]) + delta)
        connection.execute(
            "UPDATE characters SET score = ? WHERE id = ?",
            (new_score, character_id),
        )

        result = connection.execute(
            """
            SELECT
                characters.id,
                characters.name,
                characters.score,
                franchises.name AS franchise_name
            FROM characters
            JOIN franchises ON franchises.id = characters.franchise_id
            WHERE characters.id = ?
            """,
            (character_id,),
        ).fetchone()

    return {
        "id": int(result["id"]),
        "name": str(result["name"]),
        "franchise_name": str(result["franchise_name"]),
        "score": int(result["score"]),
    }


def get_ranking(
    limit: int = 100,
    franchise_id: int | None = None,
) -> list[dict[str, Any]]:
    where = ["characters.is_active = 1", "franchises.is_active = 1"]
    params: list[Any] = []
    if franchise_id is not None:
        where.append("franchises.id = ?")
        params.append(franchise_id)

    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT
                characters.id,
                characters.name,
                characters.score,
                franchises.id AS franchise_id,
                franchises.name AS franchise_name,
                COUNT(DISTINCT CASE WHEN files.is_trashed = 0 THEN file_characters.file_id END) AS file_count
            FROM characters
            JOIN franchises ON franchises.id = characters.franchise_id
            LEFT JOIN file_characters ON file_characters.character_id = characters.id
            LEFT JOIN files ON files.id = file_characters.file_id
            WHERE {' AND '.join(where)}
            GROUP BY characters.id
            ORDER BY characters.score DESC,
                     characters.name COLLATE NOCASE,
                     franchises.name COLLATE NOCASE
            LIMIT ?
            """,
            [*params, limit],
        ).fetchall()

    return [
        {
            "id": int(row["id"]),
            "name": str(row["name"]),
            "franchise_id": int(row["franchise_id"]),
            "franchise_name": str(row["franchise_name"]),
            "score": int(row["score"]),
            "file_count": int(row["file_count"]),
        }
        for row in rows
    ]
