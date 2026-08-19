from __future__ import annotations

import shutil
import uuid
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from backend.database import ensure_tag, get_connection, normalize_tag_name
from backend.file_manager import (
    calculate_sha256,
    determine_destination,
    find_duplicate,
    find_next_filename,
    get_characters_by_ids,
    normalize_filename_component,
)
from backend.paths import CACHE_ROOT
from backend.scanner import (
    cleanup_empty_entities,
    get_media_type,
    image_has_transparency,
    load_config,
    validate_folder_name,
)
from backend.thumbnails import gallery_preview_url, gallery_thumbnail_url


MAX_STORY_PAGES = 500


def _media_url(relative_path: str) -> str:
    return "/media/gallery/" + quote(relative_path, safe="/")


def _normalize_story_tags(
    tags: Iterable[str],
    artists: Iterable[str],
    ai_generated: bool,
) -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    seen: set[str] = set()

    for values, tag_type in ((tags, "general"), (artists, "artist")):
        for value in values:
            cleaned = normalize_tag_name(value)
            folded = cleaned.casefold()
            if not cleaned or folded == "ai" or folded in seen:
                continue
            result.append((cleaned, tag_type))
            seen.add(folded)

    if ai_generated:
        result.append(("AI", "system"))
    return result


def _story_folder_name(title: str) -> str:
    return validate_folder_name(title, kind="storia")


def _unique_story_directory(desired: Path, current: Path | None = None) -> Path:
    desired = desired.resolve()
    if current is not None and desired == current.resolve():
        return desired
    if not desired.exists():
        return desired

    counter = 1
    while True:
        candidate = desired.with_name(f"{desired.name} {counter:02d}")
        if current is not None and candidate.resolve() == current.resolve():
            return candidate.resolve()
        if not candidate.exists():
            return candidate.resolve()
        counter += 1


def determine_story_destination(
    characters: list[dict[str, Any]],
    ai_generated: bool,
    title: str,
    *,
    current_relative_path: str | None = None,
) -> tuple[Path, str, str, str]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    stories_folder = str(config.get("stories_folder", "!Stories"))
    story_title = _story_folder_name(title)
    base_destination, prefix, category = determine_destination(characters, ai_generated)
    desired = (base_destination / stories_folder / story_title).resolve()
    current = (
        (gallery_root / current_relative_path).resolve()
        if current_relative_path
        else None
    )
    destination = _unique_story_directory(desired, current)
    page_prefix = f"{prefix}_{normalize_filename_component(story_title)}"
    return destination, page_prefix, category, destination.name


def preview_story(
    title: str,
    character_ids: list[int],
    ai_generated: bool,
    page_count: int,
) -> dict[str, Any]:
    if page_count < 2:
        raise ValueError("Una storia deve contenere almeno due pagine.")
    characters = get_characters_by_ids(character_ids)
    destination, prefix, category, folder_name = determine_story_destination(
        characters, ai_generated, title
    )
    gallery_root = Path(load_config()["gallery_root"]).resolve()
    return {
        "category": category,
        "folder_name": folder_name,
        "destination_relative_path": destination.relative_to(gallery_root).as_posix(),
        "page_name_example": f"{prefix}_001.png",
        "page_count": page_count,
    }


def _set_file_ai_state(connection, file_id: int, ai_generated: bool) -> None:
    connection.execute(
        "UPDATE files SET ai_generated = ? WHERE id = ?",
        (int(ai_generated), file_id),
    )
    ai_row = connection.execute(
        "SELECT id FROM tags WHERE name = 'AI' COLLATE NOCASE"
    ).fetchone()
    if ai_generated:
        tag_id, _name, _type = ensure_tag(connection, "AI", "system")
        connection.execute(
            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
            (file_id, tag_id),
        )
    elif ai_row is not None:
        connection.execute(
            "DELETE FROM file_tags WHERE file_id = ? AND tag_id = ?",
            (file_id, int(ai_row["id"])),
        )


def _replace_story_metadata(
    connection,
    story_id: int,
    character_ids: list[int],
    tags: list[str],
    artists: list[str],
    ai_generated: bool,
) -> list[dict[str, str]]:
    connection.execute("DELETE FROM story_characters WHERE story_id = ?", (story_id,))
    connection.executemany(
        "INSERT INTO story_characters(story_id, character_id) VALUES (?, ?)",
        [(story_id, character_id) for character_id in dict.fromkeys(character_ids)],
    )

    connection.execute("DELETE FROM story_tags WHERE story_id = ?", (story_id,))
    canonical: list[dict[str, str]] = []
    seen: set[str] = set()
    for name, tag_type in _normalize_story_tags(tags, artists, ai_generated):
        tag_id, canonical_name, canonical_type = ensure_tag(connection, name, tag_type)
        connection.execute(
            "INSERT OR IGNORE INTO story_tags(story_id, tag_id) VALUES (?, ?)",
            (story_id, tag_id),
        )
        folded = canonical_name.casefold()
        if folded not in seen:
            canonical.append({"name": canonical_name, "type": canonical_type})
            seen.add(folded)
    return canonical


def _replace_file_characters(connection, file_id: int, character_ids: list[int]) -> None:
    connection.execute("DELETE FROM file_characters WHERE file_id = ?", (file_id,))
    connection.executemany(
        "INSERT INTO file_characters(file_id, character_id) VALUES (?, ?)",
        [(file_id, character_id) for character_id in dict.fromkeys(character_ids)],
    )


def _replace_file_tags(
    connection,
    file_id: int,
    tags: Iterable[str],
    artists: Iterable[str],
    ai_generated: bool,
) -> None:
    connection.execute("DELETE FROM file_tags WHERE file_id = ?", (file_id,))
    for name, tag_type in _normalize_story_tags(tags, artists, ai_generated):
        tag_id, _canonical_name, _canonical_type = ensure_tag(
            connection, name, tag_type
        )
        connection.execute(
            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
            (file_id, tag_id),
        )


def _file_metadata_by_id(
    connection, file_ids: Iterable[int]
) -> dict[int, dict[str, Any]]:
    unique_ids = list(dict.fromkeys(int(value) for value in file_ids))
    if not unique_ids:
        return {}

    placeholders = ",".join("?" for _ in unique_ids)
    rows = connection.execute(
        f"""
        SELECT id, ai_generated
        FROM files
        WHERE id IN ({placeholders}) AND is_trashed = 0
        """,
        unique_ids,
    ).fetchall()
    result: dict[int, dict[str, Any]] = {
        int(row["id"]): {
            "ai_generated": bool(row["ai_generated"]),
            "character_ids": [],
            "tag_ids": [],
        }
        for row in rows
    }

    character_rows = connection.execute(
        f"""
        SELECT file_id, character_id
        FROM file_characters
        WHERE file_id IN ({placeholders})
        ORDER BY file_id, character_id
        """,
        unique_ids,
    ).fetchall()
    for row in character_rows:
        file_id = int(row["file_id"])
        if file_id in result:
            result[file_id]["character_ids"].append(int(row["character_id"]))

    tag_rows = connection.execute(
        f"""
        SELECT file_id, tag_id
        FROM file_tags
        WHERE file_id IN ({placeholders})
        ORDER BY file_id, tag_id
        """,
        unique_ids,
    ).fetchall()
    for row in tag_rows:
        file_id = int(row["file_id"])
        if file_id in result:
            result[file_id]["tag_ids"].append(int(row["tag_id"]))

    return result


def _aggregate_file_metadata(
    connection,
    file_ids: Iterable[int],
    *,
    require_characters: bool = True,
) -> dict[str, Any]:
    unique_ids = list(dict.fromkeys(int(value) for value in file_ids))
    if not unique_ids:
        raise ValueError("La storia non contiene pagine.")

    metadata = _file_metadata_by_id(connection, unique_ids)
    missing = [file_id for file_id in unique_ids if file_id not in metadata]
    if missing:
        raise ValueError("Una o più immagini non sono disponibili.")

    if require_characters:
        without_characters = [
            file_id
            for file_id in unique_ids
            if not metadata[file_id]["character_ids"]
        ]
        if without_characters:
            raise ValueError(
                "Ogni pagina deve avere almeno un personaggio prima di essere inserita nella storia."
            )

    character_ids = sorted(
        {
            character_id
            for file_id in unique_ids
            for character_id in metadata[file_id]["character_ids"]
        }
    )
    tag_ids = sorted(
        {
            tag_id
            for file_id in unique_ids
            for tag_id in metadata[file_id]["tag_ids"]
        }
    )
    all_ai = all(metadata[file_id]["ai_generated"] for file_id in unique_ids)
    return {
        "file_metadata": metadata,
        "character_ids": character_ids,
        "tag_ids": tag_ids,
        "ai_generated": all_ai,
    }


def _sync_story_metadata(
    connection, story_id: int, file_ids: Iterable[int] | None = None
) -> dict[str, Any]:
    if file_ids is None:
        rows = connection.execute(
            "SELECT file_id FROM story_pages WHERE story_id = ? ORDER BY page_number",
            (story_id,),
        ).fetchall()
        file_ids = [int(row["file_id"]) for row in rows]

    aggregate = _aggregate_file_metadata(connection, file_ids)
    connection.execute("DELETE FROM story_characters WHERE story_id = ?", (story_id,))
    connection.executemany(
        "INSERT INTO story_characters(story_id, character_id) VALUES (?, ?)",
        [(story_id, character_id) for character_id in aggregate["character_ids"]],
    )
    connection.execute("DELETE FROM story_tags WHERE story_id = ?", (story_id,))
    connection.executemany(
        "INSERT INTO story_tags(story_id, tag_id) VALUES (?, ?)",
        [(story_id, tag_id) for tag_id in aggregate["tag_ids"]],
    )
    connection.execute(
        "UPDATE stories SET ai_generated = ? WHERE id = ?",
        (int(aggregate["ai_generated"]), story_id),
    )
    return aggregate


def refresh_story_metadata() -> int:
    """Migra le vecchie storie e riallinea i metadati aggregati alle pagine.

    Le storie create prima della 1.7 conservavano personaggi e tag soltanto
    sul contenitore. Alla prima apertura tali associazioni vengono copiate
    sulle singole pagine, poi la storia passa al modello ``page_union``.
    Una storia malformata viene ignorata senza impedire l'avvio della
    galleria; potrà essere corretta dall'editor.
    """

    refreshed = 0
    with get_connection() as connection:
        story_rows = connection.execute(
            """
            SELECT id, ai_generated, metadata_mode
            FROM stories
            WHERE is_active = 1
            ORDER BY id
            """
        ).fetchall()
        for row in story_rows:
            story_id = int(row["id"])
            page_rows = connection.execute(
                "SELECT file_id FROM story_pages WHERE story_id = ? ORDER BY page_number",
                (story_id,),
            ).fetchall()
            file_ids = [int(page["file_id"]) for page in page_rows]
            if not file_ids:
                continue

            try:
                if str(row["metadata_mode"] or "legacy") == "legacy":
                    character_rows = connection.execute(
                        "SELECT character_id FROM story_characters WHERE story_id = ?",
                        (story_id,),
                    ).fetchall()
                    tag_rows = connection.execute(
                        "SELECT tag_id FROM story_tags WHERE story_id = ?",
                        (story_id,),
                    ).fetchall()
                    character_ids = [int(item["character_id"]) for item in character_rows]
                    tag_ids = [int(item["tag_id"]) for item in tag_rows]

                    for file_id in file_ids:
                        connection.executemany(
                            """
                            INSERT OR IGNORE INTO file_characters(file_id, character_id)
                            VALUES (?, ?)
                            """,
                            [(file_id, character_id) for character_id in character_ids],
                        )
                        connection.executemany(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            [(file_id, tag_id) for tag_id in tag_ids],
                        )
                        if bool(row["ai_generated"]):
                            _set_file_ai_state(connection, file_id, True)

                _sync_story_metadata(connection, story_id, file_ids)
                connection.execute(
                    "UPDATE stories SET metadata_mode = 'page_union' WHERE id = ?",
                    (story_id,),
                )

                cover_row = connection.execute(
                    """
                    SELECT 1 FROM story_pages
                    WHERE story_id = ?
                      AND file_id = (SELECT cover_file_id FROM stories WHERE id = ?)
                    """,
                    (story_id, story_id),
                ).fetchone()
                if cover_row is None:
                    connection.execute(
                        "UPDATE stories SET cover_file_id = ? WHERE id = ?",
                        (file_ids[0], story_id),
                    )
                refreshed += 1
            except (ValueError, FileNotFoundError):
                # Non bloccare l'avvio per una vecchia storia incompleta.
                continue
    return refreshed


def _remove_empty_story_records(connection) -> int:
    rows = connection.execute(
        """
        SELECT s.id
        FROM stories s
        WHERE NOT EXISTS (
            SELECT 1 FROM story_pages sp WHERE sp.story_id = s.id
        )
        """
    ).fetchall()
    for row in rows:
        connection.execute("DELETE FROM stories WHERE id = ?", (int(row["id"]),))
    return len(rows)


def cleanup_empty_stories() -> int:
    with get_connection() as connection:
        return _remove_empty_story_records(connection)


def _validate_new_sources(relative_paths: list[str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    todo_root = (gallery_root / config.get("todo_folder", ".toDo")).resolve()
    unique_paths = list(dict.fromkeys(path.strip() for path in relative_paths if path.strip()))
    if len(unique_paths) < 2:
        raise ValueError("Seleziona almeno due immagini per creare una storia.")
    if len(unique_paths) > MAX_STORY_PAGES:
        raise ValueError(f"Una storia può contenere al massimo {MAX_STORY_PAGES} pagine.")

    sources: list[dict[str, Any]] = []
    duplicates: list[dict[str, Any]] = []
    selected_hashes: dict[str, str] = {}
    for relative_path in unique_paths:
        source = (todo_root / relative_path).resolve()
        try:
            source.relative_to(todo_root)
        except ValueError as error:
            raise PermissionError("Un file selezionato non appartiene a New.") from error
        if not source.exists() or not source.is_file():
            raise FileNotFoundError(f"File non trovato in New: {relative_path}")
        if get_media_type(source) != "image":
            raise ValueError("Le storie possono contenere soltanto immagini.")
        stat = source.stat()
        sha256 = calculate_sha256(source)
        duplicate = find_duplicate(sha256)
        if duplicate is not None:
            duplicates.append(
                {
                    "relative_path": relative_path,
                    "duplicate": duplicate,
                    "sha256": sha256,
                }
            )
        previous = selected_hashes.get(sha256)
        if previous is not None:
            duplicates.append(
                {
                    "relative_path": relative_path,
                    "duplicate": {"relative_path": f"New/{previous}"},
                    "sha256": sha256,
                }
            )
        else:
            selected_hashes[sha256] = relative_path
        sources.append(
            {
                "source": source,
                "source_relative": source.relative_to(gallery_root).as_posix(),
                "todo_relative": relative_path,
                "extension": source.suffix.lower(),
                "size": stat.st_size,
                "modified_at": stat.st_mtime,
                "sha256": sha256,
            }
        )
    return sources, duplicates


def create_story_from_new(
    *,
    relative_paths: list[str],
    title: str,
    character_ids: list[int],
    tags: list[str],
    artists: list[str],
    ai_generated: bool,
    cover_index: int = 0,
    allow_duplicates: bool = False,
) -> dict[str, Any]:
    sources, duplicates = _validate_new_sources(relative_paths)
    if duplicates and not allow_duplicates:
        return {"status": "duplicate", "duplicates": duplicates}

    characters = get_characters_by_ids(character_ids)
    destination, prefix, category, folder_name = determine_story_destination(
        characters, ai_generated, title
    )
    destination.mkdir(parents=True, exist_ok=False)
    gallery_root = Path(load_config()["gallery_root"]).resolve()
    moved: list[tuple[Path, Path]] = []

    try:
        for page_number, source_info in enumerate(sources, start=1):
            filename = f"{prefix}_{page_number:03d}{source_info['extension']}"
            final_path = destination / filename
            shutil.move(str(source_info["source"]), str(final_path))
            source_info["final_path"] = final_path
            source_info["filename"] = filename
            source_info["destination_relative"] = final_path.relative_to(gallery_root).as_posix()
            moved.append((final_path, source_info["source"]))

        with get_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO stories(
                    title, folder_name, relative_path, ai_generated,
                    created_at, updated_at, is_active, metadata_mode
                )
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, 'page_union')
                """,
                (
                    _story_folder_name(title),
                    folder_name,
                    destination.relative_to(gallery_root).as_posix(),
                    int(ai_generated),
                ),
            )
            story_id = int(cursor.lastrowid)

            file_ids: list[int] = []
            for page_number, source_info in enumerate(sources, start=1):
                cursor = connection.execute(
                    """
                    INSERT INTO files(
                        filename, relative_path, media_type, extension,
                        size, sha256, ai_generated, modified_at
                    ) VALUES (?, ?, 'image', ?, ?, ?, ?, ?)
                    """,
                    (
                        source_info["filename"],
                        source_info["destination_relative"],
                        source_info["extension"],
                        source_info["size"],
                        source_info["sha256"],
                        int(ai_generated),
                        source_info["modified_at"],
                    ),
                )
                file_id = int(cursor.lastrowid)
                file_ids.append(file_id)
                _replace_file_characters(connection, file_id, character_ids)
                _replace_file_tags(connection, file_id, tags, artists, ai_generated)
                connection.execute(
                    "INSERT INTO story_pages(story_id, file_id, page_number) VALUES (?, ?, ?)",
                    (story_id, file_id, page_number),
                )
                connection.execute(
                    """
                    INSERT INTO operations(
                        operation_type, source_relative_path, destination_relative_path
                    ) VALUES ('story_page_organize', ?, ?)
                    """,
                    (source_info["source_relative"], source_info["destination_relative"]),
                )

            cover_position = min(max(int(cover_index), 0), len(file_ids) - 1)
            connection.execute(
                "UPDATE stories SET cover_file_id = ? WHERE id = ?",
                (file_ids[cover_position], story_id),
            )
            _sync_story_metadata(connection, story_id, file_ids)
    except Exception:
        for final_path, original_path in reversed(moved):
            if final_path.exists():
                original_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(final_path), str(original_path))
        shutil.rmtree(destination, ignore_errors=True)
        raise

    cleanup_empty_entities()
    return get_story(story_id) | {"status": "created", "category": category}


def _load_gallery_sources(file_ids: list[int]) -> list[dict[str, Any]]:
    unique_ids = list(dict.fromkeys(int(value) for value in file_ids))
    if len(unique_ids) < 2:
        raise ValueError("Seleziona almeno due immagini per creare una storia.")
    if len(unique_ids) > MAX_STORY_PAGES:
        raise ValueError(f"Una storia può contenere al massimo {MAX_STORY_PAGES} pagine.")
    placeholders = ",".join("?" for _ in unique_ids)
    gallery_root = Path(load_config()["gallery_root"]).resolve()
    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT f.id, f.filename, f.relative_path, f.extension, f.size,
                   f.sha256, f.modified_at, f.media_type, f.ai_generated
            FROM files f
            WHERE f.id IN ({placeholders}) AND f.is_trashed = 0
            """,
            unique_ids,
        ).fetchall()
        story_rows = connection.execute(
            f"SELECT file_id FROM story_pages WHERE file_id IN ({placeholders})",
            unique_ids,
        ).fetchall()
    if len(rows) != len(unique_ids):
        raise ValueError("Uno o più file non sono disponibili.")
    if story_rows:
        raise ValueError("Una o più immagini appartengono già a una storia.")
    by_id = {int(row["id"]): row for row in rows}
    sources: list[dict[str, Any]] = []
    for file_id in unique_ids:
        row = by_id[file_id]
        if str(row["media_type"]) != "image":
            raise ValueError("Le storie possono contenere soltanto immagini.")
        source = (gallery_root / str(row["relative_path"])).resolve()
        try:
            source.relative_to(gallery_root)
        except ValueError as error:
            raise PermissionError("Percorso di un file non consentito.") from error
        if not source.exists() or not source.is_file():
            raise FileNotFoundError(f"File non trovato: {row['relative_path']}")
        sources.append(
            {
                "id": file_id,
                "source": source,
                "original_relative": str(row["relative_path"]),
                "extension": str(row["extension"]),
                "size": int(row["size"]),
                "sha256": str(row["sha256"]),
                "modified_at": float(row["modified_at"] or source.stat().st_mtime),
                "ai_generated": bool(row["ai_generated"]),
            }
        )
    return sources


def create_story_from_gallery(
    *,
    file_ids: list[int],
    title: str,
    cover_index: int = 0,
) -> dict[str, Any]:
    sources = _load_gallery_sources(file_ids)
    source_ids = [int(source["id"]) for source in sources]
    with get_connection() as connection:
        aggregate = _aggregate_file_metadata(connection, source_ids)
    characters = get_characters_by_ids(aggregate["character_ids"])
    destination, prefix, category, folder_name = determine_story_destination(
        characters, bool(aggregate["ai_generated"]), title
    )
    destination.mkdir(parents=True, exist_ok=False)
    gallery_root = Path(load_config()["gallery_root"]).resolve()
    moved: list[tuple[Path, Path]] = []

    try:
        for page_number, source_info in enumerate(sources, start=1):
            filename = f"{prefix}_{page_number:03d}{source_info['extension']}"
            final_path = destination / filename
            shutil.move(str(source_info["source"]), str(final_path))
            source_info["final_path"] = final_path
            source_info["filename"] = filename
            source_info["destination_relative"] = final_path.relative_to(gallery_root).as_posix()
            moved.append((final_path, source_info["source"]))

        with get_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO stories(
                    title, folder_name, relative_path, ai_generated,
                    created_at, updated_at, is_active, metadata_mode
                ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, 'page_union')
                """,
                (
                    _story_folder_name(title),
                    folder_name,
                    destination.relative_to(gallery_root).as_posix(),
                    int(aggregate["ai_generated"]),
                ),
            )
            story_id = int(cursor.lastrowid)
            for page_number, source_info in enumerate(sources, start=1):
                file_id = int(source_info["id"])
                connection.execute(
                    """
                    UPDATE files
                    SET filename = ?, relative_path = ?, modified_at = ?
                    WHERE id = ?
                    """,
                    (
                        source_info["filename"],
                        source_info["destination_relative"],
                        source_info["final_path"].stat().st_mtime,
                        file_id,
                    ),
                )
                connection.execute(
                    "INSERT INTO story_pages(story_id, file_id, page_number) VALUES (?, ?, ?)",
                    (story_id, file_id, page_number),
                )
                connection.execute(
                    """
                    INSERT INTO operations(
                        operation_type, source_relative_path, destination_relative_path
                    ) VALUES ('story_page_move', ?, ?)
                    """,
                    (source_info["original_relative"], source_info["destination_relative"]),
                )
            cover_position = min(max(int(cover_index), 0), len(sources) - 1)
            connection.execute(
                "UPDATE stories SET cover_file_id = ? WHERE id = ?",
                (int(sources[cover_position]["id"]), story_id),
            )
            _sync_story_metadata(connection, story_id, source_ids)
    except Exception:
        for final_path, original_path in reversed(moved):
            if final_path.exists():
                original_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(final_path), str(original_path))
        shutil.rmtree(destination, ignore_errors=True)
        raise

    cleanup_empty_entities()
    return get_story(story_id) | {"status": "created", "category": category}


def _story_character_rows(connection, story_ids: list[int]) -> dict[int, list[dict[str, Any]]]:
    result = {story_id: [] for story_id in story_ids}
    if not story_ids:
        return result
    placeholders = ",".join("?" for _ in story_ids)
    rows = connection.execute(
        f"""
        SELECT sc.story_id, c.id, c.name, c.score,
               fr.id AS franchise_id, fr.name AS franchise_name, fr.code AS franchise_code
        FROM story_characters sc
        JOIN characters c ON c.id = sc.character_id
        JOIN franchises fr ON fr.id = c.franchise_id
        WHERE sc.story_id IN ({placeholders})
        ORDER BY fr.name COLLATE NOCASE, c.name COLLATE NOCASE
        """,
        story_ids,
    ).fetchall()
    for row in rows:
        result[int(row["story_id"])].append(
            {
                "id": int(row["id"]),
                "name": str(row["name"]),
                "score": int(row["score"]),
                "franchise_id": int(row["franchise_id"]),
                "franchise_name": str(row["franchise_name"]),
                "franchise_code": str(row["franchise_code"]),
                "label": f"{row['franchise_name']} / {row['name']}",
            }
        )
    return result


def _story_tag_rows(connection, story_ids: list[int]) -> dict[int, list[dict[str, Any]]]:
    result = {story_id: [] for story_id in story_ids}
    if not story_ids:
        return result
    placeholders = ",".join("?" for _ in story_ids)
    rows = connection.execute(
        f"""
        SELECT st.story_id, t.id, t.name, t.type
        FROM story_tags st
        JOIN tags t ON t.id = st.tag_id
        WHERE st.story_id IN ({placeholders})
        ORDER BY CASE t.type WHEN 'system' THEN 0 WHEN 'artist' THEN 1 ELSE 2 END,
                 t.name COLLATE NOCASE
        """,
        story_ids,
    ).fetchall()
    for row in rows:
        result[int(row["story_id"])].append(
            {"id": int(row["id"]), "name": str(row["name"]), "type": str(row["type"])}
        )
    return result


def _hydrate_story_rows(connection, rows) -> list[dict[str, Any]]:
    story_ids = [int(row["id"]) for row in rows]
    characters = _story_character_rows(connection, story_ids)
    tags = _story_tag_rows(connection, story_ids)
    result: list[dict[str, Any]] = []
    for row in rows:
        story_id = int(row["id"])
        cover_url = None
        if row["cover_file_id"] is not None and row["cover_size"] is not None:
            cover_url = gallery_thumbnail_url(
                int(row["cover_file_id"]),
                int(row["cover_size"]),
                float(row["cover_modified_at"] or 0),
            )
        result.append(
            {
                "id": story_id,
                "title": str(row["title"]),
                "folder_name": str(row["folder_name"]),
                "relative_path": str(row["relative_path"]),
                "ai_generated": bool(row["ai_generated"]),
                "cover_file_id": int(row["cover_file_id"]) if row["cover_file_id"] is not None else None,
                "cover_url": cover_url,
                "page_count": int(row["page_count"] or 0),
                "created_at": str(row["created_at"]),
                "updated_at": str(row["updated_at"]),
                "characters": characters[story_id],
                "tags": tags[story_id],
                "artists": [tag["name"] for tag in tags[story_id] if tag["type"] == "artist"],
            }
        )
    return result


def list_stories(
    *,
    character_id: int | None = None,
    franchise_id: int | None = None,
    collection: str | None = None,
    ai_generated: bool | None = None,
    tags: list[str] | None = None,
    query: str | None = None,
    limit: int = 200,
) -> dict[str, Any]:
    if collection not in {None, "multiple", "crossovers"}:
        raise ValueError("Raccolta non valida.")
    conditions = ["s.is_active = 1"]
    params: list[Any] = []
    config = load_config()

    if character_id is not None:
        conditions.append(
            "EXISTS (SELECT 1 FROM story_characters sc WHERE sc.story_id = s.id AND sc.character_id = ?)"
        )
        params.append(character_id)
    if franchise_id is not None:
        conditions.append(
            """
            EXISTS (
                SELECT 1 FROM story_characters sc
                JOIN characters c ON c.id = sc.character_id
                WHERE sc.story_id = s.id AND c.franchise_id = ?
            )
            """
        )
        params.append(franchise_id)
    if collection == "crossovers":
        prefix = str(config.get("crossovers_folder", "!Crossovers"))
        conditions.append("(s.relative_path = ? OR s.relative_path LIKE ?)")
        params.extend([prefix, f"{prefix}/%"])
    elif collection == "multiple":
        if franchise_id is None:
            raise ValueError("La raccolta !Multiple richiede una serie.")
        with get_connection() as connection:
            row = connection.execute(
                "SELECT relative_path FROM franchises WHERE id = ?", (franchise_id,)
            ).fetchone()
        if row is None:
            raise ValueError("Serie non trovata.")
        prefix = (Path(str(row["relative_path"])) / config.get("multiple_folder", "!Multiple")).as_posix()
        conditions.append("(s.relative_path = ? OR s.relative_path LIKE ?)")
        params.extend([prefix, f"{prefix}/%"])
    if ai_generated is not None:
        conditions.append("s.ai_generated = ?")
        params.append(int(ai_generated))
    for tag in tags or []:
        cleaned = normalize_tag_name(tag)
        if not cleaned:
            continue
        conditions.append(
            """
            EXISTS (
                SELECT 1 FROM story_tags st
                JOIN tags t ON t.id = st.tag_id
                WHERE st.story_id = s.id AND t.name = ? COLLATE NOCASE
            )
            """
        )
        params.append(cleaned)
    if query and query.strip():
        pattern = f"%{query.strip()}%"
        conditions.append(
            """
            (
                s.title LIKE ? COLLATE NOCASE
                OR EXISTS (
                    SELECT 1 FROM story_tags st JOIN tags t ON t.id = st.tag_id
                    WHERE st.story_id = s.id AND t.name LIKE ? COLLATE NOCASE
                )
                OR EXISTS (
                    SELECT 1 FROM story_characters sc
                    JOIN characters c ON c.id = sc.character_id
                    JOIN franchises fr ON fr.id = c.franchise_id
                    WHERE sc.story_id = s.id
                      AND (c.name LIKE ? COLLATE NOCASE OR fr.name LIKE ? COLLATE NOCASE)
                )
            )
            """
        )
        params.extend([pattern, pattern, pattern, pattern])

    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT s.id, s.title, s.folder_name, s.relative_path,
                   s.ai_generated, s.cover_file_id,
                   s.created_at, s.updated_at,
                   COUNT(sp.file_id) AS page_count,
                   cf.size AS cover_size, cf.modified_at AS cover_modified_at
            FROM stories s
            JOIN story_pages sp ON sp.story_id = s.id
            LEFT JOIN files cf ON cf.id = s.cover_file_id AND cf.is_trashed = 0
            WHERE {' AND '.join(conditions)}
            GROUP BY s.id
            ORDER BY s.updated_at DESC, s.title COLLATE NOCASE
            LIMIT ?
            """,
            [*params, min(max(int(limit), 1), 500)],
        ).fetchall()
        stories = _hydrate_story_rows(connection, rows)
    return {"stories": stories, "total": len(stories)}


def _hydrate_story_pages(connection, story_id: int) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        SELECT sp.page_number, f.id, f.filename, f.relative_path, f.media_type,
               f.extension, f.size, f.modified_at, f.ai_generated
        FROM story_pages sp
        JOIN files f ON f.id = sp.file_id
        WHERE sp.story_id = ? AND f.is_trashed = 0
        ORDER BY sp.page_number
        """,
        (story_id,),
    ).fetchall()
    gallery_root = Path(load_config()["gallery_root"]).resolve()
    pages: list[dict[str, Any]] = []
    for row in rows:
        absolute_path = gallery_root / str(row["relative_path"])
        available = absolute_path.exists() and absolute_path.is_file()
        pages.append(
            {
                "page_number": int(row["page_number"]),
                "id": int(row["id"]),
                "filename": str(row["filename"]),
                "relative_path": str(row["relative_path"]),
                "media_type": str(row["media_type"]),
                "extension": str(row["extension"]),
                "size": int(row["size"]),
                "modified_at": float(row["modified_at"] or 0),
                "ai_generated": bool(row["ai_generated"]),
                "available": available,
                "media_url": _media_url(str(row["relative_path"])),
                "thumbnail_url": gallery_thumbnail_url(
                    int(row["id"]), int(row["size"]), float(row["modified_at"] or 0)
                ),
                "animated_preview_url": gallery_preview_url(
                    int(row["id"]), int(row["size"]), float(row["modified_at"] or 0),
                    str(row["media_type"]), str(row["extension"]),
                ),
                "has_transparency": image_has_transparency(absolute_path) if available else False,
            }
        )
    return pages


def get_story(story_id: int) -> dict[str, Any]:
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT s.id, s.title, s.folder_name, s.relative_path,
                   s.ai_generated, s.cover_file_id,
                   s.created_at, s.updated_at,
                   COUNT(sp.file_id) AS page_count,
                   cf.size AS cover_size, cf.modified_at AS cover_modified_at
            FROM stories s
            LEFT JOIN story_pages sp ON sp.story_id = s.id
            LEFT JOIN files cf ON cf.id = s.cover_file_id
            WHERE s.id = ? AND s.is_active = 1
            GROUP BY s.id
            """,
            (story_id,),
        ).fetchall()
        if not rows:
            raise ValueError("Storia non trovata.")
        story = _hydrate_story_rows(connection, rows)[0]
        story["pages"] = _hydrate_story_pages(connection, story_id)
    return story


def search_stories(query: str, limit: int = 12) -> list[dict[str, Any]]:
    return list_stories(query=query, limit=limit)["stories"]


def _fallback_cover_file_id(
    current: dict[str, Any], ordered_ids: list[int], requested_cover: int | None
) -> int:
    ordered_set = set(ordered_ids)
    if requested_cover is not None and int(requested_cover) in ordered_set:
        return int(requested_cover)

    current_ids = [int(page["id"]) for page in current.get("pages", [])]
    old_cover = current.get("cover_file_id")
    if old_cover is not None and int(old_cover) in current_ids:
        cover_index = current_ids.index(int(old_cover))
        for candidate in current_ids[cover_index + 1 :]:
            if candidate in ordered_set:
                return candidate
        for candidate in reversed(current_ids[:cover_index]):
            if candidate in ordered_set:
                return candidate
    return ordered_ids[0]


def update_story(
    story_id: int,
    *,
    title: str,
    ordered_file_ids: list[int],
    cover_file_id: int | None,
) -> dict[str, Any]:
    current = get_story(story_id)
    ordered_ids = [int(value) for value in ordered_file_ids]
    if len(ordered_ids) < 2:
        raise ValueError(
            "Una storia deve contenere almeno due pagine. Usa Sciogli storia per recuperarle tutte."
        )
    if len(ordered_ids) > MAX_STORY_PAGES:
        raise ValueError(f"Una storia può contenere al massimo {MAX_STORY_PAGES} pagine.")
    if len(set(ordered_ids)) != len(ordered_ids):
        raise ValueError("La stessa immagine non può essere inserita due volte nella storia.")

    current_ids = [int(page["id"]) for page in current["pages"]]
    all_ids = list(dict.fromkeys([*current_ids, *ordered_ids]))
    placeholders = ",".join("?" for _ in all_ids)
    gallery_root = Path(load_config()["gallery_root"]).resolve()

    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT id, filename, relative_path, media_type, extension, size,
                   sha256, ai_generated, modified_at
            FROM files
            WHERE id IN ({placeholders}) AND is_trashed = 0
            """,
            all_ids,
        ).fetchall()
        records = {int(row["id"]): row for row in rows}
        missing_requested = [file_id for file_id in ordered_ids if file_id not in records]
        if missing_requested:
            raise ValueError("Una o più immagini da salvare non sono disponibili.")
        for file_id in ordered_ids:
            if str(records[file_id]["media_type"]) != "image":
                raise ValueError("Le storie possono contenere soltanto immagini.")

        membership_rows = connection.execute(
            f"SELECT file_id, story_id FROM story_pages WHERE file_id IN ({placeholders})",
            all_ids,
        ).fetchall()
        memberships = {int(row["file_id"]): int(row["story_id"]) for row in membership_rows}
        for file_id in ordered_ids:
            member_story_id = memberships.get(file_id)
            if member_story_id is not None and member_story_id != story_id:
                raise ValueError("Una delle immagini appartiene già a un’altra storia.")

        aggregate = _aggregate_file_metadata(connection, ordered_ids)
        metadata = _file_metadata_by_id(connection, all_ids)

    characters = get_characters_by_ids(aggregate["character_ids"])
    old_story_path = (gallery_root / current["relative_path"]).resolve()
    destination, prefix, _category, folder_name = determine_story_destination(
        characters,
        bool(aggregate["ai_generated"]),
        title,
        current_relative_path=current["relative_path"],
    )
    selected_cover_id = _fallback_cover_file_id(current, ordered_ids, cover_file_id)
    removed_ids = [file_id for file_id in current_ids if file_id not in set(ordered_ids)]

    operation_root = CACHE_ROOT / "story_operations" / uuid.uuid4().hex
    operation_root.mkdir(parents=True, exist_ok=False)
    plans: dict[int, dict[str, Any]] = {}

    try:
        for file_id in all_ids:
            row = records.get(file_id)
            if row is None:
                continue
            source = (gallery_root / str(row["relative_path"])).resolve()
            try:
                source.relative_to(gallery_root)
            except ValueError as error:
                raise PermissionError("Percorso di una pagina non consentito.") from error
            exists = source.exists() and source.is_file()
            if file_id in ordered_ids and not exists:
                raise FileNotFoundError(
                    f"Pagina non trovata: {row['relative_path']}. Rimuovila dalla storia oppure ripristina il file."
                )
            plan = {
                "id": file_id,
                "source": source,
                "extension": str(row["extension"]),
                "exists": exists,
                "removed": file_id in removed_ids,
            }
            plans[file_id] = plan
            if exists:
                staging = operation_root / f"{file_id}{source.suffix.lower()}"
                shutil.move(str(source), str(staging))
                plan["staging"] = staging

        destination.mkdir(parents=True, exist_ok=True)
        for page_number, file_id in enumerate(ordered_ids, start=1):
            plan = plans[file_id]
            final = destination / f"{prefix}_{page_number:03d}{plan['extension']}"
            if final.exists():
                raise FileExistsError(f"Esiste già una pagina con questo nome: {final.name}")
            shutil.move(str(plan["staging"]), str(final))
            plan["final"] = final
            plan["page_number"] = page_number

        destination_cache: dict[tuple[tuple[int, ...], bool], tuple[Path, str]] = {}
        for file_id in removed_ids:
            plan = plans.get(file_id)
            if plan is None or not plan["exists"]:
                continue
            item_metadata = metadata.get(file_id)
            if not item_metadata or not item_metadata["character_ids"]:
                raise ValueError(
                    "Una pagina rimossa non ha personaggi associati e non può essere ricollocata."
                )
            cache_key = (
                tuple(item_metadata["character_ids"]),
                bool(item_metadata["ai_generated"]),
            )
            destination_info = destination_cache.get(cache_key)
            if destination_info is None:
                page_characters = get_characters_by_ids(list(cache_key[0]))
                page_destination, page_prefix, _page_category = determine_destination(
                    page_characters, cache_key[1]
                )
                page_destination.mkdir(parents=True, exist_ok=True)
                destination_info = (page_destination, page_prefix)
                destination_cache[cache_key] = destination_info
            page_destination, page_prefix = destination_info
            filename = find_next_filename(
                page_destination, page_prefix, plan["extension"]
            )
            final = page_destination / filename
            shutil.move(str(plan["staging"]), str(final))
            plan["final"] = final

        with get_connection() as connection:
            connection.execute(
                """
                UPDATE stories
                SET title = ?, folder_name = ?, relative_path = ?, ai_generated = ?,
                    cover_file_id = ?, metadata_mode = 'page_union',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
                """,
                (
                    _story_folder_name(title),
                    folder_name,
                    destination.relative_to(gallery_root).as_posix(),
                    int(aggregate["ai_generated"]),
                    selected_cover_id,
                    story_id,
                ),
            )
            connection.execute("DELETE FROM story_pages WHERE story_id = ?", (story_id,))

            for file_id in ordered_ids:
                plan = plans[file_id]
                final: Path = plan["final"]
                relative = final.relative_to(gallery_root).as_posix()
                connection.execute(
                    """
                    UPDATE files
                    SET filename = ?, relative_path = ?, modified_at = ?
                    WHERE id = ?
                    """,
                    (final.name, relative, final.stat().st_mtime, file_id),
                )
                connection.execute(
                    "INSERT INTO story_pages(story_id, file_id, page_number) VALUES (?, ?, ?)",
                    (story_id, file_id, int(plan["page_number"])),
                )
                connection.execute(
                    """
                    INSERT INTO operations(operation_type, source_relative_path, destination_relative_path)
                    VALUES ('story_page_update', ?, ?)
                    """,
                    (plan["source"].relative_to(gallery_root).as_posix(), relative),
                )

            for file_id in removed_ids:
                plan = plans.get(file_id)
                if plan is None or not plan["exists"]:
                    connection.execute("DELETE FROM files WHERE id = ?", (file_id,))
                    continue
                final = Path(plan["final"])
                relative = final.relative_to(gallery_root).as_posix()
                connection.execute(
                    "UPDATE files SET filename = ?, relative_path = ?, modified_at = ? WHERE id = ?",
                    (final.name, relative, final.stat().st_mtime, file_id),
                )
                connection.execute(
                    """
                    INSERT INTO operations(operation_type, source_relative_path, destination_relative_path)
                    VALUES ('story_page_remove', ?, ?)
                    """,
                    (plan["source"].relative_to(gallery_root).as_posix(), relative),
                )

            _sync_story_metadata(connection, story_id, ordered_ids)
    except Exception:
        for plan in plans.values():
            final = plan.get("final")
            staging = plan.get("staging")
            if final is not None and Path(final).exists():
                if staging is None:
                    staging = operation_root / f"rollback_{plan['id']}{Path(final).suffix.lower()}"
                    plan["staging"] = staging
                shutil.move(str(final), str(staging))
        for plan in plans.values():
            staging = plan.get("staging")
            source: Path = plan["source"]
            if staging is not None and Path(staging).exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(staging), str(source))
        if destination != old_story_path and destination.exists():
            shutil.rmtree(destination, ignore_errors=True)
        raise
    finally:
        shutil.rmtree(operation_root, ignore_errors=True)

    cleanup_empty_entities()
    return get_story(story_id) | {
        "status": "updated",
        "added_pages": len([file_id for file_id in ordered_ids if file_id not in set(current_ids)]),
        "removed_pages": len(removed_ids),
    }


def dissolve_story(story_id: int) -> dict[str, Any]:
    story = get_story(story_id)
    if not story["pages"]:
        raise ValueError("La storia non contiene pagine.")

    page_ids = [int(page["id"]) for page in story["pages"]]
    with get_connection() as connection:
        metadata = _file_metadata_by_id(connection, page_ids)

    gallery_root = Path(load_config()["gallery_root"]).resolve()
    moved: list[dict[str, Any]] = []
    destination_cache: dict[tuple[tuple[int, ...], bool], tuple[Path, str]] = {}

    try:
        for page in story["pages"]:
            file_id = int(page["id"])
            source = (gallery_root / page["relative_path"]).resolve()
            if not source.exists() or not source.is_file():
                raise FileNotFoundError(
                    f"Pagina non trovata: {page['relative_path']}. Rimuovila dalla storia prima di scioglierla."
                )
            item_metadata = metadata.get(file_id)
            if not item_metadata or not item_metadata["character_ids"]:
                raise ValueError(
                    "Una pagina non ha personaggi associati e non può essere ricollocata."
                )
            cache_key = (
                tuple(item_metadata["character_ids"]),
                bool(item_metadata["ai_generated"]),
            )
            destination_info = destination_cache.get(cache_key)
            if destination_info is None:
                characters = get_characters_by_ids(list(cache_key[0]))
                destination, prefix, _category = determine_destination(
                    characters, cache_key[1]
                )
                destination.mkdir(parents=True, exist_ok=True)
                destination_info = (destination, prefix)
                destination_cache[cache_key] = destination_info
            destination, prefix = destination_info
            filename = find_next_filename(destination, prefix, source.suffix)
            final = destination / filename
            shutil.move(str(source), str(final))
            moved.append({"id": file_id, "source": source, "final": final})

        with get_connection() as connection:
            for item in moved:
                file_id = int(item["id"])
                final: Path = item["final"]
                relative = final.relative_to(gallery_root).as_posix()
                connection.execute(
                    "UPDATE files SET filename = ?, relative_path = ?, modified_at = ? WHERE id = ?",
                    (final.name, relative, final.stat().st_mtime, file_id),
                )
                connection.execute(
                    """
                    INSERT INTO operations(operation_type, source_relative_path, destination_relative_path)
                    VALUES ('story_dissolve', ?, ?)
                    """,
                    (item["source"].relative_to(gallery_root).as_posix(), relative),
                )
            connection.execute("DELETE FROM stories WHERE id = ?", (story_id,))
    except Exception:
        for item in reversed(moved):
            final: Path = item["final"]
            source: Path = item["source"]
            if final.exists():
                source.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(final), str(source))
        raise

    cleanup_empty_entities()
    return {
        "status": "dissolved",
        "story_id": story_id,
        "moved_files": [item["final"].relative_to(gallery_root).as_posix() for item in moved],
    }

