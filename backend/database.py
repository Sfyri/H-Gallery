from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_ROOT = PROJECT_ROOT / "data"
DATABASE_PATH = DATA_ROOT / "gallery.db"


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
                name TEXT NOT NULL UNIQUE COLLATE NOCASE
            );

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
