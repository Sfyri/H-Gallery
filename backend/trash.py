from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote

from backend.database import get_connection
from backend.file_manager import calculate_sha256
from backend.scanner import cleanup_empty_entities, get_media_type, load_config
from backend.thumbnails import trash_preview_url, trash_thumbnail_url


def _trash_root() -> tuple[Path, Path, str]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    trash_name = str(config.get("trash_folder", ".trash"))
    trash_root = (gallery_root / trash_name).resolve()
    trash_root.mkdir(parents=True, exist_ok=True)
    return gallery_root, trash_root, trash_name


def _ensure_inside(path: Path, root: Path, message: str) -> None:
    try:
        path.relative_to(root)
    except ValueError as error:
        raise PermissionError(message) from error


def _unique_target(target: Path, marker: str) -> Path:
    if not target.exists():
        return target

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    candidate = target.with_name(f"{target.stem}_{marker}_{timestamp}{target.suffix}")
    counter = 2
    while candidate.exists():
        candidate = target.with_name(
            f"{target.stem}_{marker}_{timestamp}_{counter}{target.suffix}"
        )
        counter += 1
    return candidate


def _media_url(trash_relative_path: str) -> str:
    return "/media/trash/" + quote(trash_relative_path, safe="/")


def _remove_unused_tags(connection) -> None:
    connection.execute(
        """
        DELETE FROM tags
        WHERE NOT EXISTS (
            SELECT 1 FROM file_tags WHERE file_tags.tag_id = tags.id
        )
        """
    )


def trash_gallery_file(file_id: int) -> dict[str, Any]:
    gallery_root, trash_root, trash_name = _trash_root()

    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, filename, relative_path, media_type, extension,
                   size, sha256, ai_generated, modified_at, is_trashed
            FROM files
            WHERE id = ?
            """,
            (file_id,),
        ).fetchone()

    if row is None:
        raise ValueError("File non trovato nel database.")
    if bool(row["is_trashed"]):
        raise ValueError("Il file si trova già nel cestino.")

    original_relative = str(row["relative_path"])
    source = (gallery_root / original_relative).resolve()
    _ensure_inside(source, gallery_root, "Il file non appartiene alla galleria.")
    if not source.exists() or not source.is_file():
        raise FileNotFoundError(
            "Il file non esiste più sul disco. Esegui Sincronizza archivio."
        )

    target = _unique_target(trash_root / original_relative, "deleted")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(target))

    trash_relative = target.relative_to(gallery_root).as_posix()
    try:
        stat = target.stat()
        with get_connection() as connection:
            connection.execute(
                """
                UPDATE files
                SET filename = ?, relative_path = ?, size = ?, modified_at = ?,
                    is_trashed = 1
                WHERE id = ?
                """,
                (target.name, trash_relative, stat.st_size, stat.st_mtime, file_id),
            )
            cursor = connection.execute(
                """
                INSERT INTO trash_items(
                    file_id, source_kind, original_relative_path,
                    trash_relative_path, original_filename, media_type,
                    extension, size, sha256
                )
                VALUES (?, 'gallery', ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    file_id,
                    original_relative,
                    trash_relative,
                    str(row["filename"]),
                    str(row["media_type"]),
                    str(row["extension"]),
                    int(row["size"]),
                    str(row["sha256"]),
                ),
            )
            trash_id = int(cursor.lastrowid)
            connection.execute(
                """
                INSERT INTO operations(
                    operation_type, source_relative_path, destination_relative_path
                ) VALUES ('trash', ?, ?)
                """,
                (original_relative, trash_relative),
            )
    except Exception:
        source.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            shutil.move(str(target), str(source))
        raise

    cleanup_empty_entities()
    return {
        "status": "trashed",
        "trash_id": trash_id,
        "file_id": file_id,
        "original_relative_path": original_relative,
        "trash_relative_path": trash_relative,
        "trash_folder": trash_name,
    }


def trash_todo_file(relative_path: str) -> dict[str, Any]:
    config = load_config()
    gallery_root, trash_root, trash_name = _trash_root()
    todo_name = str(config.get("todo_folder", ".toDo"))
    todo_root = (gallery_root / todo_name).resolve()
    source = (todo_root / relative_path).resolve()
    _ensure_inside(source, todo_root, "Il file richiesto non appartiene a New.")

    if not source.exists() or not source.is_file():
        raise FileNotFoundError(f"File non trovato in New: {relative_path}")

    media_type = get_media_type(source)
    if media_type is None:
        raise ValueError("Il formato del file non è supportato.")

    stat = source.stat()
    sha256 = calculate_sha256(source)
    # Mantiene la struttura della cartella reale, anche se nell'interfaccia è New.
    target = _unique_target(trash_root / todo_name / relative_path, "deleted")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(target))
    trash_relative = target.relative_to(gallery_root).as_posix()

    try:
        with get_connection() as connection:
            cursor = connection.execute(
                """
                INSERT INTO trash_items(
                    file_id, source_kind, original_relative_path,
                    trash_relative_path, original_filename, media_type,
                    extension, size, sha256
                )
                VALUES (NULL, 'todo', ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    Path(relative_path).as_posix(),
                    trash_relative,
                    source.name,
                    media_type,
                    source.suffix.lower(),
                    stat.st_size,
                    sha256,
                ),
            )
            trash_id = int(cursor.lastrowid)
            connection.execute(
                """
                INSERT INTO operations(
                    operation_type, source_relative_path, destination_relative_path
                ) VALUES ('trash_new', ?, ?)
                """,
                ((Path(todo_name) / relative_path).as_posix(), trash_relative),
            )
    except Exception:
        source.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            shutil.move(str(target), str(source))
        raise

    return {
        "status": "trashed",
        "trash_id": trash_id,
        "source_kind": "todo",
        "original_relative_path": Path(relative_path).as_posix(),
        "trash_relative_path": trash_relative,
        "trash_folder": trash_name,
    }


def _hydrate_trash_items(connection, rows) -> list[dict[str, Any]]:
    file_ids = [int(row["file_id"]) for row in rows if row["file_id"] is not None]
    characters: dict[int, list[dict[str, Any]]] = {file_id: [] for file_id in file_ids}
    tags: dict[int, list[dict[str, Any]]] = {file_id: [] for file_id in file_ids}

    if file_ids:
        placeholders = ",".join("?" for _ in file_ids)
        character_rows = connection.execute(
            f"""
            SELECT fc.file_id, c.id, c.name, fr.id AS franchise_id,
                   fr.name AS franchise_name
            FROM file_characters fc
            JOIN characters c ON c.id = fc.character_id
            JOIN franchises fr ON fr.id = c.franchise_id
            WHERE fc.file_id IN ({placeholders})
            ORDER BY fr.name COLLATE NOCASE, c.name COLLATE NOCASE
            """,
            file_ids,
        ).fetchall()
        tag_rows = connection.execute(
            f"""
            SELECT ft.file_id, t.id, t.name, t.type
            FROM file_tags ft
            JOIN tags t ON t.id = ft.tag_id
            WHERE ft.file_id IN ({placeholders})
            ORDER BY CASE t.type
                WHEN 'system' THEN 0
                WHEN 'artist' THEN 1
                ELSE 2
            END, t.name COLLATE NOCASE
            """,
            file_ids,
        ).fetchall()
        for row in character_rows:
            characters[int(row["file_id"])].append(
                {
                    "id": int(row["id"]),
                    "name": str(row["name"]),
                    "franchise_id": int(row["franchise_id"]),
                    "franchise_name": str(row["franchise_name"]),
                    "label": f"{row['franchise_name']} / {row['name']}",
                }
            )
        for row in tag_rows:
            tags[int(row["file_id"])].append(
                {"id": int(row["id"]), "name": str(row["name"]), "type": str(row["type"] or "general")}
            )

    result: list[dict[str, Any]] = []
    for row in rows:
        file_id = int(row["file_id"]) if row["file_id"] is not None else None
        result.append(
            {
                "id": int(row["id"]),
                "file_id": file_id,
                "source_kind": str(row["source_kind"]),
                "filename": str(row["original_filename"]),
                "original_relative_path": str(row["original_relative_path"]),
                "trash_relative_path": str(row["trash_relative_path"]),
                "media_type": str(row["media_type"]),
                "extension": str(row["extension"]),
                "size": int(row["size"]),
                "sha256": str(row["sha256"]),
                "deleted_at": str(row["deleted_at"]),
                "media_url": _media_url(str(row["trash_relative_path"])),
                "thumbnail_url": trash_thumbnail_url(int(row["id"]), int(row["size"])),
                "animated_preview_url": trash_preview_url(
                    int(row["id"]),
                    int(row["size"]),
                    str(row["media_type"]),
                    str(row["extension"]),
                ),
                "characters": characters.get(file_id, []) if file_id is not None else [],
                "tags": tags.get(file_id, []) if file_id is not None else [],
                "ai_generated": bool(row["ai_generated"] or 0),
            }
        )
    return result


def list_trash_items(page: int = 1, limit: int = 100) -> dict[str, Any]:
    page = max(1, page)
    limit = min(max(1, limit), 200)
    offset = (page - 1) * limit

    with get_connection() as connection:
        total_row = connection.execute(
            "SELECT COUNT(*) AS count, COALESCE(SUM(size), 0) AS total_size FROM trash_items"
        ).fetchone()
        rows = connection.execute(
            """
            SELECT ti.id, ti.file_id, ti.source_kind, ti.original_relative_path,
                   ti.trash_relative_path, ti.original_filename, ti.media_type,
                   ti.extension, ti.size, ti.sha256, ti.deleted_at,
                   f.ai_generated
            FROM trash_items ti
            LEFT JOIN files f ON f.id = ti.file_id
            ORDER BY ti.deleted_at DESC, ti.id DESC
            LIMIT ? OFFSET ?
            """,
            (limit, offset),
        ).fetchall()
        items = _hydrate_trash_items(connection, rows)

    total = int(total_row["count"])
    return {
        "items": items,
        "page": page,
        "limit": limit,
        "total": total,
        "pages": max(1, (total + limit - 1) // limit),
        "total_size": int(total_row["total_size"] or 0),
    }


def restore_trash_item(trash_id: int, auto_rename: bool = False) -> dict[str, Any]:
    config = load_config()
    gallery_root, trash_root, _trash_name = _trash_root()
    todo_name = str(config.get("todo_folder", ".toDo"))

    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, file_id, source_kind, original_relative_path,
                   trash_relative_path, original_filename
            FROM trash_items
            WHERE id = ?
            """,
            (trash_id,),
        ).fetchone()
    if row is None:
        raise ValueError("Elemento del cestino non trovato.")

    source = (gallery_root / str(row["trash_relative_path"])).resolve()
    _ensure_inside(source, trash_root, "Il file non appartiene al cestino.")
    if not source.exists() or not source.is_file():
        raise FileNotFoundError(
            "Il file non è più presente nel cestino. Puoi eliminarne il record definitivamente."
        )

    if str(row["source_kind"]) == "todo":
        destination = (gallery_root / todo_name / str(row["original_relative_path"])).resolve()
        destination_root = (gallery_root / todo_name).resolve()
    else:
        destination = (gallery_root / str(row["original_relative_path"])).resolve()
        destination_root = gallery_root
    _ensure_inside(destination, destination_root, "Percorso di ripristino non consentito.")

    renamed = False
    if destination.exists():
        if not auto_rename:
            return {
                "status": "conflict",
                "message": "Esiste già un file nella destinazione originale.",
                "destination_relative_path": destination.relative_to(gallery_root).as_posix(),
            }
        destination = _unique_target(destination, "restored")
        renamed = True

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))

    restored_relative = destination.relative_to(gallery_root).as_posix()
    try:
        with get_connection() as connection:
            if row["file_id"] is not None:
                file_id = int(row["file_id"])
                stat = destination.stat()
                connection.execute(
                    """
                    UPDATE files
                    SET filename = ?, relative_path = ?, size = ?, modified_at = ?,
                        is_trashed = 0
                    WHERE id = ?
                    """,
                    (destination.name, restored_relative, stat.st_size, stat.st_mtime, file_id),
                )
            connection.execute("DELETE FROM trash_items WHERE id = ?", (trash_id,))
            connection.execute(
                """
                INSERT INTO operations(
                    operation_type, source_relative_path, destination_relative_path
                ) VALUES ('restore', ?, ?)
                """,
                (str(row["trash_relative_path"]), restored_relative),
            )
    except Exception:
        source.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            shutil.move(str(destination), str(source))
        raise

    _remove_empty_parents(source.parent, trash_root)
    cleanup_empty_entities()
    return {
        "status": "restored",
        "trash_id": trash_id,
        "relative_path": restored_relative,
        "renamed": renamed,
        "source_kind": str(row["source_kind"]),
    }


def permanently_delete_trash_item(
    trash_id: int,
    *,
    run_cleanup: bool = True,
) -> dict[str, Any]:
    gallery_root, trash_root, _trash_name = _trash_root()

    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, file_id, trash_relative_path
            FROM trash_items
            WHERE id = ?
            """,
            (trash_id,),
        ).fetchone()
    if row is None:
        raise ValueError("Elemento del cestino non trovato.")

    file_path = (gallery_root / str(row["trash_relative_path"])).resolve()
    _ensure_inside(file_path, trash_root, "Il file non appartiene al cestino.")
    if file_path.exists():
        if not file_path.is_file():
            raise ValueError("Il percorso nel cestino non è un file.")
        file_path.unlink()

    with get_connection() as connection:
        if row["file_id"] is not None:
            connection.execute("DELETE FROM files WHERE id = ?", (int(row["file_id"]),))
        else:
            connection.execute("DELETE FROM trash_items WHERE id = ?", (trash_id,))
        _remove_unused_tags(connection)
        connection.execute(
            """
            INSERT INTO operations(
                operation_type, source_relative_path, destination_relative_path
            ) VALUES ('permanent_delete', ?, '')
            """,
            (str(row["trash_relative_path"]),),
        )

    _remove_empty_parents(file_path.parent, trash_root)
    if run_cleanup:
        cleanup_empty_entities()
    return {"status": "deleted", "trash_id": trash_id}


def empty_trash(confirmation: str) -> dict[str, Any]:
    if confirmation != "ELIMINA":
        raise ValueError("Conferma non valida. Scrivi ELIMINA.")

    with get_connection() as connection:
        rows = connection.execute(
            "SELECT id FROM trash_items ORDER BY id"
        ).fetchall()

    deleted = 0
    errors: list[dict[str, Any]] = []
    for row in rows:
        trash_id = int(row["id"])
        try:
            permanently_delete_trash_item(trash_id, run_cleanup=False)
            deleted += 1
        except Exception as error:  # continua con gli altri elementi
            errors.append({"id": trash_id, "error": str(error)})

    cleanup_empty_entities()
    return {"status": "emptied", "deleted": deleted, "errors": errors}


def _remove_empty_parents(start: Path, stop: Path) -> None:
    current = start
    while current != stop:
        try:
            current.rmdir()
        except OSError:
            break
        current = current.parent
