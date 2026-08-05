from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from typing import Any

from backend.database import get_connection
from backend.file_manager import calculate_sha256
from backend.scanner import (
    cleanup_empty_entities,
    get_media_type,
    load_config,
    sync_characters,
)


def _set_ai_state(connection, file_id: int, ai_generated: bool) -> None:
    connection.execute(
        "UPDATE files SET ai_generated = ? WHERE id = ?",
        (int(ai_generated), file_id),
    )

    if ai_generated:
        connection.execute(
            "INSERT INTO tags(name) VALUES ('AI') ON CONFLICT(name) DO NOTHING"
        )
        tag_row = connection.execute(
            "SELECT id FROM tags WHERE name = 'AI' COLLATE NOCASE"
        ).fetchone()
        connection.execute(
            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
            (file_id, int(tag_row["id"])),
        )
        return

    tag_row = connection.execute(
        "SELECT id FROM tags WHERE name = 'AI' COLLATE NOCASE"
    ).fetchone()
    if tag_row is not None:
        connection.execute(
            "DELETE FROM file_tags WHERE file_id = ? AND tag_id = ?",
            (file_id, int(tag_row["id"])),
        )


def _infer_character_link(
    connection,
    file_id: int,
    parts: tuple[str, ...],
    *,
    multiple_folder: str,
    crossovers_folder: str,
) -> bool:
    """Deduce il personaggio solo per i file nella sua cartella diretta.

    Le associazioni già presenti non vengono sostituite. Per !Multiple e
    !Crossovers servono associazioni esplicite tramite la galleria.
    """

    existing_link = connection.execute(
        "SELECT 1 FROM file_characters WHERE file_id = ? LIMIT 1",
        (file_id,),
    ).fetchone()
    if existing_link:
        return True

    if (
        len(parts) < 3
        or parts[0] == crossovers_folder
        or parts[1] == multiple_folder
        or parts[1].startswith("!")
        or parts[1].startswith(".")
    ):
        return False

    character_relative = Path(parts[0], parts[1]).as_posix()
    character_row = connection.execute(
        "SELECT id FROM characters WHERE relative_path = ? AND is_active = 1",
        (character_relative,),
    ).fetchone()
    if character_row is None:
        return False

    connection.execute(
        "INSERT OR IGNORE INTO file_characters(file_id, character_id) VALUES (?, ?)",
        (file_id, int(character_row["id"])),
    )
    return True


def _remove_unused_tags(connection) -> int:
    before = int(connection.execute("SELECT COUNT(*) AS count FROM tags").fetchone()["count"])
    connection.execute(
        """
        DELETE FROM tags
        WHERE NOT EXISTS (
            SELECT 1 FROM file_tags WHERE file_tags.tag_id = tags.id
        )
        """
    )
    after = int(connection.execute("SELECT COUNT(*) AS count FROM tags").fetchone()["count"])
    return before - after


def synchronize_archive() -> dict[str, Any]:
    """Allinea il database al contenuto reale dell'archivio.

    Aggiunge file nuovi, aggiorna i metadati, riconosce spostamenti o rinomine
    tramite SHA-256 e rimuove i record dei file non più presenti. I tag e le
    associazioni vengono mantenuti quando un file viene riconosciuto come
    spostato.
    """

    character_sync = sync_characters()
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    ignored_root_names = {
        config.get("script_folder", ".Script"),
        config.get("todo_folder", ".toDo"),
        config.get("trash_folder", ".trash"),
    }
    ai_folder = config.get("ai_folder", ".AI")
    multiple_folder = config.get("multiple_folder", "!Multiple")
    crossovers_folder = config.get("crossovers_folder", "!Crossovers")

    media_paths = sorted(
        (
            path
            for path in gallery_root.rglob("*")
            if path.is_file()
            and path.relative_to(gallery_root).parts
            and path.relative_to(gallery_root).parts[0] not in ignored_root_names
            and get_media_type(path) is not None
        ),
        key=lambda path: str(path).casefold(),
    )
    current_relative_paths = {
        path.relative_to(gallery_root).as_posix() for path in media_paths
    }

    added = 0
    updated = 0
    unchanged = 0
    moved = 0
    removed = 0
    skipped_character_links = 0
    errors: list[dict[str, str]] = []

    with get_connection() as connection:
        database_rows = connection.execute(
            """
            SELECT id, filename, relative_path, media_type, extension,
                   size, sha256, ai_generated, modified_at
            FROM files
            WHERE is_trashed = 0
            """
        ).fetchall()
        by_path = {str(row["relative_path"]): row for row in database_rows}
        stale_by_hash: dict[str, list[Any]] = defaultdict(list)
        for row in database_rows:
            if str(row["relative_path"]) not in current_relative_paths:
                stale_by_hash[str(row["sha256"])].append(row)

        processed_ids: set[int] = set()
        moved_source_ids: set[int] = set()

        for file_path in media_paths:
            relative_path = file_path.relative_to(gallery_root).as_posix()
            parts = file_path.relative_to(gallery_root).parts
            media_type = get_media_type(file_path)

            try:
                stat = file_path.stat()
                file_size = stat.st_size
                modified_at = stat.st_mtime
            except OSError as error:
                errors.append({"path": relative_path, "error": str(error)})
                continue

            existing = by_path.get(relative_path)
            sha256: str

            if existing is not None:
                file_id = int(existing["id"])
                # Ricalcola l'hash soltanto se dimensione o data sono cambiate,
                # oppure se il vecchio record non aveva ancora modified_at.
                content_changed = (
                    int(existing["size"]) != file_size
                    or float(existing["modified_at"] or 0) != float(modified_at)
                    or not str(existing["sha256"])
                )
                if content_changed:
                    try:
                        sha256 = calculate_sha256(file_path)
                    except OSError as error:
                        errors.append({"path": relative_path, "error": str(error)})
                        continue
                else:
                    sha256 = str(existing["sha256"])

                metadata_changed = content_changed or any(
                    (
                        str(existing["filename"]) != file_path.name,
                        str(existing["media_type"]) != media_type,
                        str(existing["extension"]) != file_path.suffix.lower(),
                    )
                )

                connection.execute(
                    """
                    UPDATE files
                    SET filename = ?, media_type = ?, extension = ?,
                        size = ?, sha256 = ?, modified_at = ?
                    WHERE id = ?
                    """,
                    (
                        file_path.name,
                        media_type,
                        file_path.suffix.lower(),
                        file_size,
                        sha256,
                        modified_at,
                        file_id,
                    ),
                )
                if metadata_changed:
                    updated += 1
                else:
                    unchanged += 1
            else:
                try:
                    sha256 = calculate_sha256(file_path)
                except OSError as error:
                    errors.append({"path": relative_path, "error": str(error)})
                    continue

                move_candidate = None
                for candidate in stale_by_hash.get(sha256, []):
                    candidate_id = int(candidate["id"])
                    if candidate_id not in moved_source_ids:
                        move_candidate = candidate
                        break

                if move_candidate is not None:
                    file_id = int(move_candidate["id"])
                    old_relative_path = str(move_candidate["relative_path"])
                    connection.execute(
                        """
                        UPDATE files
                        SET filename = ?, relative_path = ?, media_type = ?,
                            extension = ?, size = ?, sha256 = ?, modified_at = ?
                        WHERE id = ?
                        """,
                        (
                            file_path.name,
                            relative_path,
                            media_type,
                            file_path.suffix.lower(),
                            file_size,
                            sha256,
                            modified_at,
                            file_id,
                        ),
                    )
                    connection.execute(
                        """
                        INSERT INTO operations(
                            operation_type, source_relative_path,
                            destination_relative_path
                        )
                        VALUES ('external_move_detected', ?, ?)
                        """,
                        (old_relative_path, relative_path),
                    )
                    moved_source_ids.add(file_id)
                    moved += 1
                else:
                    cursor = connection.execute(
                        """
                        INSERT INTO files(
                            filename, relative_path, media_type, extension,
                            size, sha256, ai_generated, modified_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, 0, ?)
                        """,
                        (
                            file_path.name,
                            relative_path,
                            media_type,
                            file_path.suffix.lower(),
                            file_size,
                            sha256,
                            modified_at,
                        ),
                    )
                    file_id = int(cursor.lastrowid)
                    added += 1

            processed_ids.add(file_id)
            _set_ai_state(connection, file_id, ai_folder in parts)
            if not _infer_character_link(
                connection,
                file_id,
                parts,
                multiple_folder=multiple_folder,
                crossovers_folder=crossovers_folder,
            ):
                link_count = connection.execute(
                    "SELECT COUNT(*) AS count FROM file_characters WHERE file_id = ?",
                    (file_id,),
                ).fetchone()
                if int(link_count["count"]) == 0:
                    skipped_character_links += 1

        all_rows_after = connection.execute(
            "SELECT id, relative_path FROM files WHERE is_trashed = 0"
        ).fetchall()
        for row in all_rows_after:
            file_id = int(row["id"])
            if file_id in processed_ids:
                continue

            stored_path = (gallery_root / str(row["relative_path"])).resolve()
            if not stored_path.exists():
                connection.execute("DELETE FROM files WHERE id = ?", (file_id,))
                removed += 1

        removed_tags = _remove_unused_tags(connection)

    cleanup = cleanup_empty_entities()
    return {
        "added": added,
        "updated": updated,
        "unchanged": unchanged,
        "moved": moved,
        "removed": removed,
        "removed_unused_tags": removed_tags,
        "skipped_character_links": skipped_character_links,
        "errors": errors,
        "total_on_disk": len(media_paths),
        "characters": character_sync,
        "cleanup": cleanup,
    }


# Compatibilità con il nome usato dalla versione 0.3.
def index_existing_archive() -> dict[str, Any]:
    return synchronize_archive()
