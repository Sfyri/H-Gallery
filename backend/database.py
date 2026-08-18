from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from typing import Iterator

from backend.paths import DATA_ROOT, migrate_legacy_user_storage
from backend.sync_foundation import initialize_sync_schema


migrate_legacy_user_storage()
DATABASE_PATH = DATA_ROOT / "gallery.db"


def normalize_tag_name(value: str) -> str:
    """Normalizza gli spazi senza alterare la grafia scelta dall’utente."""

    return " ".join(str(value).split())


def ensure_tag(
    connection: sqlite3.Connection,
    name: str,
    tag_type: str = "general",
) -> tuple[int, str, str]:
    """Restituisce un tag esistente ignorando maiuscole/minuscole o lo crea.

    I tipi ammessi sono ``general``, ``artist`` e ``system``. Un tag già
    classificato come artista o di sistema non viene retrocesso a generale.
    Se un tag generale viene inserito nel campo Artista, viene promosso ad
    artista mantenendo lo stesso ID e tutte le associazioni esistenti.
    """
    cleaned = normalize_tag_name(name)
    if not cleaned:
        raise ValueError("Il nome del tag non può essere vuoto.")

    normalized_type = str(tag_type or "general").strip().casefold()
    if normalized_type not in {"general", "artist", "system"}:
        raise ValueError("Tipo di tag non valido.")

    if cleaned.casefold() == "ai":
        normalized_type = "system"
    row = connection.execute(
        "SELECT id, name, type FROM tags WHERE name = ? COLLATE NOCASE",
        (cleaned,),
    ).fetchone()

    if row is None:
        cursor = connection.execute(
            "INSERT INTO tags(name, type) VALUES (?, ?)",
            (cleaned, normalized_type),
        )
        return int(cursor.lastrowid), cleaned, normalized_type
    current_type = str(row["type"] or "general")
    final_type = current_type
    if current_type == "general" and normalized_type in {"artist", "system"}:
        final_type = normalized_type
        connection.execute(
            "UPDATE tags SET type = ? WHERE id = ?",
            (final_type, int(row["id"])),
        )

    return int(row["id"]), str(row["name"]), final_type


@contextmanager
def get_connection() -> Iterator[sqlite3.Connection]:
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")

    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def _column_names(connection: sqlite3.Connection, table_name: str) -> set[str]:
    return {
        str(row["name"])
        for row in connection.execute(f"PRAGMA table_info({table_name})").fetchall()
    }


def init_database() -> None:
    """Crea il database e applica le migrazioni non distruttive.

    La funzione è compatibile con i database creati dalle versioni 0.3 e 0.4.
    """
    with get_connection() as connection:
        connection.executescript(
            """
            CREATE TABLE IF NOT EXISTS franchises (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                code TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                is_active INTEGER NOT NULL DEFAULT 1
            );

            CREATE INDEX IF NOT EXISTS idx_franchises_code
            ON franchises(code);
            CREATE TABLE IF NOT EXISTS characters (
                id INTEGER PRIMARY KEY,
                franchise_id INTEGER NOT NULL,
                name TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                score INTEGER NOT NULL DEFAULT 0 CHECK(score >= 0),
                is_active INTEGER NOT NULL DEFAULT 1,
                FOREIGN KEY(franchise_id) REFERENCES franchises(id),
                UNIQUE(franchise_id, name)
            );
            CREATE INDEX IF NOT EXISTS idx_characters_franchise
            ON characters(franchise_id, is_active);
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY,
                filename TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                media_type TEXT NOT NULL,
                extension TEXT NOT NULL,
                size INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                ai_generated INTEGER NOT NULL DEFAULT 0,
                modified_at REAL NOT NULL DEFAULT 0,
                added_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                is_trashed INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_files_sha256
            ON files(sha256);

            CREATE INDEX IF NOT EXISTS idx_files_type_ai
            ON files(media_type, ai_generated);

            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE COLLATE NOCASE,
                type TEXT NOT NULL DEFAULT 'general'
                    CHECK(type IN ('general', 'artist', 'system'))
            );
            CREATE TABLE IF NOT EXISTS character_aliases (
                id INTEGER PRIMARY KEY,
                character_id INTEGER NOT NULL,
                alias TEXT NOT NULL COLLATE NOCASE,
                FOREIGN KEY(character_id) REFERENCES characters(id) ON DELETE CASCADE,
                UNIQUE(character_id, alias)
            );

            CREATE INDEX IF NOT EXISTS idx_character_aliases_alias
            ON character_aliases(alias);
            CREATE TABLE IF NOT EXISTS file_characters (
                file_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                PRIMARY KEY(file_id, character_id),
                FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
                FOREIGN KEY(character_id) REFERENCES characters(id)
            );

            CREATE INDEX IF NOT EXISTS idx_file_characters_character
            ON file_characters(character_id, file_id);
            CREATE TABLE IF NOT EXISTS file_tags (
                file_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY(file_id, tag_id),
                FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE,
                FOREIGN KEY(tag_id) REFERENCES tags(id)
            );

            CREATE INDEX IF NOT EXISTS idx_file_tags_tag
            ON file_tags(tag_id, file_id);
            CREATE TABLE IF NOT EXISTS stories (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                folder_name TEXT NOT NULL,
                relative_path TEXT NOT NULL UNIQUE,
                ai_generated INTEGER NOT NULL DEFAULT 0,
                reading_direction TEXT NOT NULL DEFAULT 'rtl'
                    CHECK(reading_direction IN ('ltr', 'rtl')),
                cover_file_id INTEGER,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                is_active INTEGER NOT NULL DEFAULT 1,
                metadata_mode TEXT NOT NULL DEFAULT 'page_union',
                FOREIGN KEY(cover_file_id) REFERENCES files(id) ON DELETE SET NULL
            );
            CREATE INDEX IF NOT EXISTS idx_stories_active_updated
            ON stories(is_active, updated_at DESC);
            CREATE TABLE IF NOT EXISTS story_pages (
                story_id INTEGER NOT NULL,
                file_id INTEGER NOT NULL UNIQUE,
                page_number INTEGER NOT NULL CHECK(page_number >= 1),
                PRIMARY KEY(story_id, page_number),
                FOREIGN KEY(story_id) REFERENCES stories(id) ON DELETE CASCADE,
                FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_story_pages_file
            ON story_pages(file_id);

            CREATE TABLE IF NOT EXISTS story_characters (
                story_id INTEGER NOT NULL,
                character_id INTEGER NOT NULL,
                PRIMARY KEY(story_id, character_id),
                FOREIGN KEY(story_id) REFERENCES stories(id) ON DELETE CASCADE,
                FOREIGN KEY(character_id) REFERENCES characters(id)
            );
            CREATE INDEX IF NOT EXISTS idx_story_characters_character
            ON story_characters(character_id, story_id);

            CREATE TABLE IF NOT EXISTS story_tags (
                story_id INTEGER NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY(story_id, tag_id),
                FOREIGN KEY(story_id) REFERENCES stories(id) ON DELETE CASCADE,
                FOREIGN KEY(tag_id) REFERENCES tags(id)
            );
            CREATE INDEX IF NOT EXISTS idx_story_tags_tag
            ON story_tags(tag_id, story_id);

            CREATE TABLE IF NOT EXISTS operations (
                id INTEGER PRIMARY KEY,
                operation_type TEXT NOT NULL,
                source_relative_path TEXT NOT NULL,
                destination_relative_path TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS trash_items (
                id INTEGER PRIMARY KEY,
                file_id INTEGER UNIQUE,
                source_kind TEXT NOT NULL CHECK(source_kind IN ('gallery', 'todo')),
                original_relative_path TEXT NOT NULL,
                trash_relative_path TEXT NOT NULL UNIQUE,
                original_filename TEXT NOT NULL,
                media_type TEXT NOT NULL,
                extension TEXT NOT NULL,
                size INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                deleted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_trash_deleted
            ON trash_items(deleted_at DESC);
            """
        )
        # Migrazione dei database creati dalla v0.4, nei quali modified_at
        # non era ancora presente.
        file_columns = _column_names(connection, "files")
        if "modified_at" not in file_columns:
            connection.execute(
                "ALTER TABLE files ADD COLUMN modified_at REAL NOT NULL DEFAULT 0"
            )
        if "is_trashed" not in file_columns:
            connection.execute(
                "ALTER TABLE files ADD COLUMN is_trashed INTEGER NOT NULL DEFAULT 0"
            )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified_at DESC)"
        )

        story_columns = _column_names(connection, "stories")
        if "metadata_mode" not in story_columns:
            connection.execute(
                "ALTER TABLE stories ADD COLUMN metadata_mode TEXT NOT NULL DEFAULT 'legacy'"
            )
        tag_columns = _column_names(connection, "tags")
        if "type" not in tag_columns:
            connection.execute(
                "ALTER TABLE tags ADD COLUMN type TEXT NOT NULL DEFAULT 'general'"
            )

        connection.execute(
            "UPDATE tags SET type = 'system' WHERE name = 'AI' COLLATE NOCASE"
        )
        connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_tags_type ON tags(type, name)"
        )

        # Fondamenta della sincronizzazione multi-device. La migrazione è
        # non distruttiva e non abilita ancora alcun trasferimento di rete.
        initialize_sync_schema(connection)
