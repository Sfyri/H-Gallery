from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

from backend.database import get_connection
from backend.file_manager import (
    determine_destination,
    find_next_filename,
    get_characters_by_ids,
)
from backend.scanner import (
    cleanup_empty_entities,
    list_todo_files,
    load_config,
    normalize_search_text,
)
from backend.thumbnails import gallery_preview_url, gallery_thumbnail_url


def _media_url(relative_path: str) -> str:
    return "/media/gallery/" + quote(relative_path, safe="/")


def _normalize_tags(tags: list[str], ai_generated: bool) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()

    for tag in tags:
        cleaned = tag.strip()
        if not cleaned:
            continue
        folded = cleaned.casefold()
        # Il tag AI è controllato esclusivamente dalla relativa casella.
        if folded == "ai":
            continue
        if folded not in seen:
            normalized.append(cleaned)
            seen.add(folded)

    if ai_generated:
        normalized.append("AI")

    return normalized


def _path_condition(prefix: str) -> tuple[str, list[Any]]:
    return (
        "(f.relative_path = ? OR substr(f.relative_path, 1, length(?) + 1) = ? || '/')",
        [prefix, prefix, prefix],
    )


def _collection_prefix(
    *,
    franchise_id: int | None,
    collection: str | None,
) -> str | None:
    config = load_config()

    if collection == "crossovers":
        return str(config.get("crossovers_folder", "!Crossovers"))

    if collection == "multiple":
        if franchise_id is None:
            raise ValueError("La raccolta !Multiple richiede una serie.")
        with get_connection() as connection:
            row = connection.execute(
                "SELECT relative_path FROM franchises WHERE id = ? AND is_active = 1",
                (franchise_id,),
            ).fetchone()
        if row is None:
            raise ValueError("Serie non trovata.")
        return (Path(str(row["relative_path"])) / config.get("multiple_folder", "!Multiple")).as_posix()

    if franchise_id is not None:
        with get_connection() as connection:
            row = connection.execute(
                "SELECT relative_path FROM franchises WHERE id = ? AND is_active = 1",
                (franchise_id,),
            ).fetchone()
        if row is None:
            raise ValueError("Serie non trovata.")
        return str(row["relative_path"])

    return None


def _get_cover_for_prefix(connection, prefix: str) -> str | None:
    condition, params = _path_condition(prefix)
    row = connection.execute(
        f"""
        SELECT f.id, f.relative_path, f.size, f.modified_at, f.media_type, f.extension
        FROM files f
        WHERE {condition} AND f.is_trashed = 0 AND f.media_type = 'image'
        ORDER BY f.modified_at DESC, f.id DESC
        LIMIT 1
        """,
        params,
    ).fetchone()
    return (
        gallery_thumbnail_url(int(row["id"]), int(row["size"]), float(row["modified_at"] or 0))
        if row
        else None
    )


def _get_cover_for_franchise(
    connection,
    franchise_id: int,
    prefix: str,
) -> str | None:
    condition, params = _path_condition(prefix)
    row = connection.execute(
        f"""
        SELECT f.id, f.size, f.modified_at
        FROM files f
        WHERE f.is_trashed = 0
          AND f.media_type = 'image'
          AND (
              {condition}
              OR EXISTS (
                  SELECT 1
                  FROM file_characters fc
                  JOIN characters c ON c.id = fc.character_id
                  WHERE fc.file_id = f.id AND c.franchise_id = ?
              )
          )
        ORDER BY f.modified_at DESC, f.id DESC
        LIMIT 1
        """,
        [*params, franchise_id],
    ).fetchone()
    return (
        gallery_thumbnail_url(
            int(row["id"]),
            int(row["size"]),
            float(row["modified_at"] or 0),
        )
        if row
        else None
    )


def get_gallery_overview() -> dict[str, Any]:
    config = load_config()
    crossovers_folder = str(config.get("crossovers_folder", "!Crossovers"))

    franchises: list[dict[str, Any]] = []
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, name, code, relative_path
            FROM franchises
            WHERE is_active = 1
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()

        for row in rows:
            prefix = str(row["relative_path"])
            condition, params = _path_condition(prefix)
            franchise_id = int(row["id"])
            stats = connection.execute(
                f"""
                SELECT
                    COUNT(DISTINCT f.id) AS total_files,
                    COUNT(DISTINCT CASE WHEN f.media_type = 'image' THEN f.id END) AS images,
                    COUNT(DISTINCT CASE WHEN f.media_type = 'video' THEN f.id END) AS videos,
                    COUNT(DISTINCT CASE WHEN f.ai_generated = 1 THEN f.id END) AS ai_files
                FROM files f
                WHERE f.is_trashed = 0
                  AND (
                      {condition}
                      OR EXISTS (
                          SELECT 1
                          FROM file_characters fc
                          JOIN characters c ON c.id = fc.character_id
                          WHERE fc.file_id = f.id AND c.franchise_id = ?
                      )
                  )
                """,
                [*params, franchise_id],
            ).fetchone()
            total_files = int(stats["total_files"] or 0)
            if total_files == 0:
                continue

            character_count = connection.execute(
                """
                SELECT COUNT(*) AS count
                FROM characters c
                WHERE c.franchise_id = ?
                  AND c.is_active = 1
                  AND EXISTS (
                      SELECT 1
                      FROM file_characters fc
                      JOIN files f ON f.id = fc.file_id
                      WHERE fc.character_id = c.id AND f.is_trashed = 0
                  )
                """,
                (franchise_id,),
            ).fetchone()

            franchises.append(
                {
                    "id": franchise_id,
                    "name": str(row["name"]),
                    "code": str(row["code"]),
                    "relative_path": prefix,
                    "character_count": int(character_count["count"]),
                    "total_files": total_files,
                    "images": int(stats["images"] or 0),
                    "videos": int(stats["videos"] or 0),
                    "ai_files": int(stats["ai_files"] or 0),
                    "cover_url": _get_cover_for_franchise(
                        connection, franchise_id, prefix
                    ),
                }
            )

        cross_condition, cross_params = _path_condition(crossovers_folder)
        cross_stats = connection.execute(
            f"""
            SELECT
                COUNT(*) AS total_files,
                SUM(CASE WHEN f.media_type = 'image' THEN 1 ELSE 0 END) AS images,
                SUM(CASE WHEN f.media_type = 'video' THEN 1 ELSE 0 END) AS videos,
                SUM(CASE WHEN f.ai_generated = 1 THEN 1 ELSE 0 END) AS ai_files
            FROM files f
            WHERE {cross_condition} AND f.is_trashed = 0
            """,
            cross_params,
        ).fetchone()

        total_stats = connection.execute(
            """
            SELECT
                COUNT(*) AS total_files,
                SUM(CASE WHEN media_type = 'image' THEN 1 ELSE 0 END) AS images,
                SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END) AS videos,
                SUM(CASE WHEN ai_generated = 1 THEN 1 ELSE 0 END) AS ai_files
            FROM files
            WHERE is_trashed = 0
            """
        ).fetchone()
        trash_count = int(
            connection.execute(
                "SELECT COUNT(*) AS count FROM trash_items"
            ).fetchone()["count"]
        )

    todo = list_todo_files()
    return {
        "franchises": franchises,
        "crossovers": {
            "name": crossovers_folder,
            "total_files": int(cross_stats["total_files"] or 0),
            "images": int(cross_stats["images"] or 0),
            "videos": int(cross_stats["videos"] or 0),
            "ai_files": int(cross_stats["ai_files"] or 0),
            "cover_url": _get_cover_for_prefix_from_new_connection(crossovers_folder),
        },
        "todo_count": int(todo["total_files"]),
        "trash_count": trash_count,
        "summary": {
            "franchises": len(franchises),
            "total_files": int(total_stats["total_files"] or 0),
            "images": int(total_stats["images"] or 0),
            "videos": int(total_stats["videos"] or 0),
            "ai_files": int(total_stats["ai_files"] or 0),
        },
    }


def _get_cover_for_prefix_from_new_connection(prefix: str) -> str | None:
    with get_connection() as connection:
        return _get_cover_for_prefix(connection, prefix)


def get_franchise_characters(franchise_id: int) -> dict[str, Any]:
    config = load_config()
    multiple_folder = str(config.get("multiple_folder", "!Multiple"))

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

        rows = connection.execute(
            """
            SELECT
                c.id,
                c.name,
                c.relative_path,
                c.score,
                COUNT(DISTINCT f.id) AS total_files,
                COUNT(DISTINCT CASE WHEN f.media_type = 'image' THEN f.id END) AS images,
                COUNT(DISTINCT CASE WHEN f.media_type = 'video' THEN f.id END) AS videos,
                COUNT(DISTINCT CASE WHEN f.ai_generated = 1 THEN f.id END) AS ai_files
            FROM characters c
            LEFT JOIN file_characters fc ON fc.character_id = c.id
            LEFT JOIN files f ON f.id = fc.file_id AND f.is_trashed = 0
            WHERE c.franchise_id = ? AND c.is_active = 1
            GROUP BY c.id
            ORDER BY c.name COLLATE NOCASE
            """,
            (franchise_id,),
        ).fetchall()

        characters: list[dict[str, Any]] = []
        for row in rows:
            if int(row["total_files"] or 0) == 0:
                continue
            cover = connection.execute(
                """
                SELECT f.id, f.relative_path, f.size, f.modified_at, f.media_type, f.extension
                FROM files f
                JOIN file_characters fc ON fc.file_id = f.id
                WHERE fc.character_id = ? AND f.is_trashed = 0 AND f.media_type = 'image'
                ORDER BY f.modified_at DESC, f.id DESC
                LIMIT 1
                """,
                (int(row["id"]),),
            ).fetchone()
            characters.append(
                {
                    "id": int(row["id"]),
                    "name": str(row["name"]),
                    "relative_path": str(row["relative_path"]),
                    "score": int(row["score"]),
                    "total_files": int(row["total_files"] or 0),
                    "images": int(row["images"] or 0),
                    "videos": int(row["videos"] or 0),
                    "ai_files": int(row["ai_files"] or 0),
                    "cover_url": (
                        gallery_thumbnail_url(
                            int(cover["id"]),
                            int(cover["size"]),
                            float(cover["modified_at"] or 0),
                        )
                        if cover
                        else None
                    ),
                }
            )

        multiple_prefix = (
            Path(str(franchise["relative_path"])) / multiple_folder
        ).as_posix()
        multiple_condition, multiple_params = _path_condition(multiple_prefix)
        multiple_stats = connection.execute(
            f"""
            SELECT
                COUNT(*) AS total_files,
                SUM(CASE WHEN f.media_type = 'image' THEN 1 ELSE 0 END) AS images,
                SUM(CASE WHEN f.media_type = 'video' THEN 1 ELSE 0 END) AS videos,
                SUM(CASE WHEN f.ai_generated = 1 THEN 1 ELSE 0 END) AS ai_files
            FROM files f
            WHERE {multiple_condition} AND f.is_trashed = 0
            """,
            multiple_params,
        ).fetchone()
        multiple_cover = _get_cover_for_prefix(connection, multiple_prefix)

    return {
        "franchise": {
            "id": int(franchise["id"]),
            "name": str(franchise["name"]),
            "code": str(franchise["code"]),
            "relative_path": str(franchise["relative_path"]),
        },
        "characters": characters,
        "multiple": {
            "name": multiple_folder,
            "total_files": int(multiple_stats["total_files"] or 0),
            "images": int(multiple_stats["images"] or 0),
            "videos": int(multiple_stats["videos"] or 0),
            "ai_files": int(multiple_stats["ai_files"] or 0),
            "cover_url": multiple_cover,
        },
    }


def _build_file_conditions(
    *,
    character_id: int | None,
    franchise_id: int | None,
    collection: str | None,
    media_type: str | None,
    ai_generated: bool | None,
    tags: list[str],
    query: str | None,
) -> tuple[list[str], list[Any]]:
    conditions: list[str] = ["f.is_trashed = 0"]
    params: list[Any] = []

    if character_id is not None:
        conditions.append(
            "EXISTS (SELECT 1 FROM file_characters fc WHERE fc.file_id = f.id AND fc.character_id = ?)"
        )
        params.append(character_id)

    if collection == "unassigned":
        conditions.append("NOT EXISTS (SELECT 1 FROM file_characters fc WHERE fc.file_id = f.id)")
    else:
        prefix = _collection_prefix(franchise_id=franchise_id, collection=collection)
        if prefix is not None:
            condition, prefix_params = _path_condition(prefix)
            conditions.append(condition)
            params.extend(prefix_params)

    if media_type in {"image", "video"}:
        conditions.append("f.media_type = ?")
        params.append(media_type)

    if ai_generated is not None:
        conditions.append("f.ai_generated = ?")
        params.append(int(ai_generated))

    for tag in tags:
        cleaned = tag.strip()
        if not cleaned:
            continue
        conditions.append(
            """
            EXISTS (
                SELECT 1
                FROM file_tags ft
                JOIN tags t ON t.id = ft.tag_id
                WHERE ft.file_id = f.id AND t.name = ? COLLATE NOCASE
            )
            """
        )
        params.append(cleaned)

    if query and query.strip():
        pattern = f"%{query.strip()}%"
        conditions.append(
            """
            (
                f.filename LIKE ? COLLATE NOCASE
                OR f.relative_path LIKE ? COLLATE NOCASE
                OR EXISTS (
                    SELECT 1
                    FROM file_tags ft
                    JOIN tags t ON t.id = ft.tag_id
                    WHERE ft.file_id = f.id AND t.name LIKE ? COLLATE NOCASE
                )
                OR EXISTS (
                    SELECT 1
                    FROM file_characters fc
                    JOIN characters c ON c.id = fc.character_id
                    JOIN franchises fr ON fr.id = c.franchise_id
                    WHERE fc.file_id = f.id
                      AND (c.name LIKE ? COLLATE NOCASE OR fr.name LIKE ? COLLATE NOCASE)
                )
            )
            """
        )
        params.extend([pattern, pattern, pattern, pattern, pattern])

    return conditions, params


def _hydrate_files(connection, rows) -> list[dict[str, Any]]:
    file_ids = [int(row["id"]) for row in rows]
    if not file_ids:
        return []

    placeholders = ",".join("?" for _ in file_ids)
    character_rows = connection.execute(
        f"""
        SELECT
            fc.file_id,
            c.id,
            c.name,
            c.score,
            fr.id AS franchise_id,
            fr.name AS franchise_name,
            fr.code AS franchise_code
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
        SELECT ft.file_id, t.id, t.name
        FROM file_tags ft
        JOIN tags t ON t.id = ft.tag_id
        WHERE ft.file_id IN ({placeholders})
        ORDER BY t.name COLLATE NOCASE
        """,
        file_ids,
    ).fetchall()

    characters: dict[int, list[dict[str, Any]]] = {file_id: [] for file_id in file_ids}
    tags: dict[int, list[dict[str, Any]]] = {file_id: [] for file_id in file_ids}

    for row in character_rows:
        characters[int(row["file_id"])].append(
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

    for row in tag_rows:
        tags[int(row["file_id"])].append(
            {"id": int(row["id"]), "name": str(row["name"])}
        )

    return [
        {
            "id": int(row["id"]),
            "filename": str(row["filename"]),
            "relative_path": str(row["relative_path"]),
            "media_type": str(row["media_type"]),
            "extension": str(row["extension"]),
            "size": int(row["size"]),
            "sha256": str(row["sha256"]),
            "ai_generated": bool(row["ai_generated"]),
            "modified_at": float(row["modified_at"] or 0),
            "added_at": str(row["added_at"]),
            "media_url": _media_url(str(row["relative_path"])),
            "thumbnail_url": gallery_thumbnail_url(
                int(row["id"]), int(row["size"]), float(row["modified_at"] or 0)
            ),
            "animated_preview_url": gallery_preview_url(
                int(row["id"]),
                int(row["size"]),
                float(row["modified_at"] or 0),
                str(row["media_type"]),
                str(row["extension"]),
            ),
            "characters": characters[int(row["id"])],
            "tags": tags[int(row["id"])],
        }
        for row in rows
    ]


def list_gallery_files(
    *,
    character_id: int | None = None,
    franchise_id: int | None = None,
    collection: str | None = None,
    media_type: str | None = None,
    ai_generated: bool | None = None,
    tags: list[str] | None = None,
    query: str | None = None,
    sort: str = "newest",
    page: int = 1,
    limit: int = 60,
) -> dict[str, Any]:
    if collection not in {None, "multiple", "crossovers", "unassigned"}:
        raise ValueError("Raccolta non valida.")

    conditions, params = _build_file_conditions(
        character_id=character_id,
        franchise_id=franchise_id,
        collection=collection,
        media_type=media_type,
        ai_generated=ai_generated,
        tags=tags or [],
        query=query,
    )
    where_clause = "WHERE " + " AND ".join(conditions) if conditions else ""

    order_map = {
        "newest": "f.modified_at DESC, f.id DESC",
        "oldest": "f.modified_at ASC, f.id ASC",
        "name_asc": "f.filename COLLATE NOCASE ASC, f.id ASC",
        "name_desc": "f.filename COLLATE NOCASE DESC, f.id DESC",
        "size_desc": "f.size DESC, f.id DESC",
        "size_asc": "f.size ASC, f.id ASC",
        "added_desc": "f.added_at DESC, f.id DESC",
    }
    order_clause = order_map.get(sort)
    if order_clause is None:
        raise ValueError("Ordinamento non valido.")

    page = max(1, page)
    limit = min(max(1, limit), 200)
    offset = (page - 1) * limit

    with get_connection() as connection:
        total = int(
            connection.execute(
                f"SELECT COUNT(*) AS count FROM files f {where_clause}",
                params,
            ).fetchone()["count"]
        )
        rows = connection.execute(
            f"""
            SELECT f.id, f.filename, f.relative_path, f.media_type,
                   f.extension, f.size, f.sha256, f.ai_generated,
                   f.modified_at, f.added_at
            FROM files f
            {where_clause}
            ORDER BY {order_clause}
            LIMIT ? OFFSET ?
            """,
            [*params, limit, offset],
        ).fetchall()
        files = _hydrate_files(connection, rows)

    return {
        "files": files,
        "page": page,
        "limit": limit,
        "total": total,
        "pages": max(1, (total + limit - 1) // limit),
    }


def get_gallery_file(file_id: int) -> dict[str, Any]:
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, filename, relative_path, media_type, extension,
                   size, sha256, ai_generated, modified_at, added_at
            FROM files
            WHERE id = ? AND is_trashed = 0
            """,
            (file_id,),
        ).fetchall()
        if not rows:
            raise ValueError("File non trovato nel database.")
        return _hydrate_files(connection, rows)[0]


def list_tags(query: str | None = None, limit: int = 100) -> list[dict[str, Any]]:
    params: list[Any] = []
    where = ""
    if query and query.strip():
        where = "WHERE t.name LIKE ? COLLATE NOCASE"
        params.append(f"%{query.strip()}%")

    with get_connection() as connection:
        rows = connection.execute(
            f"""
            SELECT t.id, t.name,
                   COUNT(DISTINCT CASE WHEN f.is_trashed = 0 THEN ft.file_id END) AS file_count
            FROM tags t
            LEFT JOIN file_tags ft ON ft.tag_id = t.id
            LEFT JOIN files f ON f.id = ft.file_id
            {where}
            GROUP BY t.id
            HAVING file_count > 0
            ORDER BY file_count DESC, t.name COLLATE NOCASE
            LIMIT ?
            """,
            [*params, min(max(limit, 1), 500)],
        ).fetchall()

    return [
        {
            "id": int(row["id"]),
            "name": str(row["name"]),
            "file_count": int(row["file_count"]),
        }
        for row in rows
    ]


def search_gallery(query: str, limit: int = 12) -> dict[str, Any]:
    normalized = normalize_search_text(query)
    if not normalized:
        return {"characters": [], "tags": []}

    with get_connection() as connection:
        character_rows = connection.execute(
            """
            SELECT c.id, c.name, c.score, fr.id AS franchise_id,
                   fr.name AS franchise_name, fr.code AS franchise_code
            FROM characters c
            JOIN franchises fr ON fr.id = c.franchise_id
            WHERE c.is_active = 1 AND fr.is_active = 1
            """
        ).fetchall()

    ranked: list[tuple[int, str, dict[str, Any]]] = []
    for row in character_rows:
        name = str(row["name"])
        franchise = str(row["franchise_name"])
        normalized_name = normalize_search_text(name)
        normalized_label = normalize_search_text(f"{franchise} {name}")
        if normalized == normalized_name:
            rank = 0
        elif normalized_name.startswith(normalized):
            rank = 1
        elif normalized in normalized_name:
            rank = 2
        elif all(part in normalized_label for part in normalized.split()):
            rank = 3
        else:
            continue
        ranked.append(
            (
                rank,
                normalized_name,
                {
                    "id": int(row["id"]),
                    "name": name,
                    "score": int(row["score"]),
                    "franchise_id": int(row["franchise_id"]),
                    "franchise_name": franchise,
                    "franchise_code": str(row["franchise_code"]),
                    "label": f"{franchise} / {name}",
                },
            )
        )

    ranked.sort(key=lambda item: (item[0], item[1], item[2]["franchise_name"].casefold()))
    return {
        "characters": [item[2] for item in ranked[:limit]],
        "tags": list_tags(query, limit),
    }


def update_file_metadata(
    file_id: int,
    *,
    character_ids: list[int],
    tags: list[str],
    ai_generated: bool,
) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()

    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, filename, relative_path, extension, ai_generated
            FROM files
            WHERE id = ? AND is_trashed = 0
            """,
            (file_id,),
        ).fetchone()
    if row is None:
        raise ValueError("File non trovato nel database.")

    current_file = (gallery_root / str(row["relative_path"])).resolve()
    try:
        current_file.relative_to(gallery_root)
    except ValueError as error:
        raise PermissionError("Il percorso registrato non appartiene alla galleria.") from error
    if not current_file.exists() or not current_file.is_file():
        raise FileNotFoundError(
            "Il file non esiste più sul disco. Esegui Sincronizza archivio."
        )

    characters = get_characters_by_ids(character_ids)
    destination, prefix, _category = determine_destination(characters, ai_generated)
    destination.mkdir(parents=True, exist_ok=True)

    moved = current_file.parent.resolve() != destination.resolve()
    destination_file = current_file
    if moved:
        new_filename = find_next_filename(destination, prefix, current_file.suffix)
        destination_file = destination / new_filename
        if destination_file.exists():
            raise FileExistsError(f"Il file di destinazione esiste già: {destination_file}")
        shutil.move(str(current_file), str(destination_file))

    normalized_tags = _normalize_tags(tags, ai_generated)
    old_relative = str(row["relative_path"])
    new_relative = destination_file.relative_to(gallery_root).as_posix()

    try:
        stat = destination_file.stat()
        with get_connection() as connection:
            # find_next_filename controlla il disco. Se lo stesso percorso è
            # ancora occupato soltanto da un vecchio record del database, quel
            # record è necessariamente orfano e può essere rimosso.
            connection.execute(
                "DELETE FROM files WHERE relative_path = ? AND id <> ?",
                (new_relative, file_id),
            )
            connection.execute(
                """
                UPDATE files
                SET filename = ?, relative_path = ?, ai_generated = ?,
                    size = ?, modified_at = ?
                WHERE id = ?
                """,
                (
                    destination_file.name,
                    new_relative,
                    int(ai_generated),
                    stat.st_size,
                    stat.st_mtime,
                    file_id,
                ),
            )

            connection.execute(
                "DELETE FROM file_characters WHERE file_id = ?",
                (file_id,),
            )
            connection.executemany(
                "INSERT INTO file_characters(file_id, character_id) VALUES (?, ?)",
                [(file_id, int(character["id"])) for character in characters],
            )

            connection.execute("DELETE FROM file_tags WHERE file_id = ?", (file_id,))
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
                    "INSERT INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                    (file_id, int(tag_row["id"])),
                )

            connection.execute(
                """
                DELETE FROM tags
                WHERE NOT EXISTS (
                    SELECT 1 FROM file_tags WHERE file_tags.tag_id = tags.id
                )
                """
            )

            if moved:
                connection.execute(
                    """
                    INSERT INTO operations(
                        operation_type, source_relative_path, destination_relative_path
                    )
                    VALUES ('metadata_reorganize', ?, ?)
                    """,
                    (old_relative, new_relative),
                )
    except Exception:
        if moved and destination_file.exists():
            current_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(destination_file), str(current_file))
        raise

    cleanup_empty_entities()
    result = get_gallery_file(file_id)
    result["moved"] = moved
    result["old_relative_path"] = old_relative
    return result


def reveal_file(file_id: int) -> dict[str, Any]:
    file_data = get_gallery_file(file_id)
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    file_path = (gallery_root / file_data["relative_path"]).resolve()

    if not file_path.exists():
        raise FileNotFoundError(
            "Il file non esiste più sul disco. Esegui Sincronizza archivio."
        )

    if sys.platform != "win32":
        raise RuntimeError("L'apertura in Esplora file è disponibile solo su Windows.")

    subprocess.Popen(["explorer", "/select,", os.fspath(file_path)])
    return {"status": "opened", "relative_path": file_data["relative_path"]}
