from __future__ import annotations

import sqlite3
import uuid
from typing import Any


SYNC_SCHEMA_VERSION = 1


def _column_names(connection: sqlite3.Connection, table_name: str) -> set[str]:
    return {
        str(row["name"])
        for row in connection.execute(f"PRAGMA table_info({table_name})").fetchall()
    }


def _new_uuid() -> str:
    return str(uuid.uuid4())


def _ensure_file_sync_ids(connection: sqlite3.Connection) -> None:
    """Aggiunge un'identità persistente a ogni media già indicizzato.

    ``files.id`` resta l'ID locale SQLite e continua a essere usato dal codice
    esistente. ``sync_uuid`` è invece l'identità portabile che in futuro verrà
    usata per riconoscere lo stesso media tra Windows e Android.
    """

    columns = _column_names(connection, "files")
    if "sync_uuid" not in columns:
        connection.execute("ALTER TABLE files ADD COLUMN sync_uuid TEXT")

    missing_rows = connection.execute(
        """
        SELECT id
        FROM files
        WHERE sync_uuid IS NULL OR TRIM(sync_uuid) = ''
        ORDER BY id
        """
    ).fetchall()
    for row in missing_rows:
        connection.execute(
            "UPDATE files SET sync_uuid = ? WHERE id = ?",
            (_new_uuid(), int(row["id"])),
        )

    duplicate_rows = connection.execute(
        """
        SELECT sync_uuid
        FROM files
        WHERE sync_uuid IS NOT NULL AND TRIM(sync_uuid) <> ''
        GROUP BY sync_uuid
        HAVING COUNT(*) > 1
        """
    ).fetchall()
    for duplicate in duplicate_rows:
        duplicate_uuid = str(duplicate["sync_uuid"])
        rows = connection.execute(
            "SELECT id FROM files WHERE sync_uuid = ? ORDER BY id",
            (duplicate_uuid,),
        ).fetchall()
        # Conserva l'identità del record più vecchio e rigenera solo i duplicati.
        for row in rows[1:]:
            connection.execute(
                "UPDATE files SET sync_uuid = ? WHERE id = ?",
                (_new_uuid(), int(row["id"])),
            )

    connection.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_files_sync_uuid ON files(sync_uuid)"
    )

    # Il codice desktop esistente non conosce ancora sync_uuid. Questo trigger
    # garantisce che ogni futuro INSERT riceva comunque un'identità persistente
    # senza dover modificare tutti i punti che creano record media.
    connection.executescript(
        """
        CREATE TRIGGER IF NOT EXISTS trg_files_assign_sync_uuid
        AFTER INSERT ON files
        FOR EACH ROW
        WHEN NEW.sync_uuid IS NULL OR TRIM(NEW.sync_uuid) = ''
        BEGIN
            UPDATE files
            SET sync_uuid = (
                lower(hex(randomblob(4))) || '-' ||
                lower(hex(randomblob(2))) || '-' ||
                lower(hex(randomblob(2))) || '-' ||
                lower(hex(randomblob(2))) || '-' ||
                lower(hex(randomblob(6)))
            )
            WHERE id = NEW.id;
        END;
        """
    )


def _ensure_gallery_identity(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS sync_gallery_identity (
            singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
            gallery_uuid TEXT NOT NULL UNIQUE,
            schema_version INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    row = connection.execute(
        "SELECT gallery_uuid FROM sync_gallery_identity WHERE singleton_id = 1"
    ).fetchone()
    if row is None:
        connection.execute(
            """
            INSERT INTO sync_gallery_identity(singleton_id, gallery_uuid, schema_version)
            VALUES (1, ?, ?)
            """,
            (_new_uuid(), SYNC_SCHEMA_VERSION),
        )
    else:
        connection.execute(
            "UPDATE sync_gallery_identity SET schema_version = ? WHERE singleton_id = 1",
            (SYNC_SCHEMA_VERSION,),
        )


def _ensure_sync_tables(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS sync_peers (
            peer_uuid TEXT PRIMARY KEY,
            peer_gallery_uuid TEXT NOT NULL,
            display_name TEXT NOT NULL,
            platform TEXT NOT NULL CHECK(platform IN ('windows', 'android', 'unknown')),
            paired_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            last_seen_at TEXT,
            is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
            UNIQUE(peer_gallery_uuid)
        );

        CREATE INDEX IF NOT EXISTS idx_sync_peers_active
        ON sync_peers(is_active, display_name);

        CREATE TABLE IF NOT EXISTS sync_tombstones (
            file_uuid TEXT PRIMARY KEY,
            sha256 TEXT NOT NULL,
            media_type TEXT NOT NULL,
            last_relative_path TEXT NOT NULL,
            deleted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            origin_peer_uuid TEXT,
            created_locally INTEGER NOT NULL DEFAULT 1 CHECK(created_locally IN (0, 1))
        );

        CREATE INDEX IF NOT EXISTS idx_sync_tombstones_deleted
        ON sync_tombstones(deleted_at);

        CREATE TABLE IF NOT EXISTS sync_tombstone_acks (
            file_uuid TEXT NOT NULL,
            peer_uuid TEXT NOT NULL,
            acknowledged_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(file_uuid, peer_uuid),
            FOREIGN KEY(file_uuid) REFERENCES sync_tombstones(file_uuid) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS sync_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """
    )


def initialize_sync_schema(connection: sqlite3.Connection) -> None:
    """Installa le fondamenta DB del sync in modo non distruttivo e idempotente.

    Questa funzione NON abilita alcun trasferimento di rete. Prepara solamente
    identità e tabelle che verranno usate dalle future versioni Windows/Android.
    """

    _ensure_file_sync_ids(connection)
    _ensure_gallery_identity(connection)
    _ensure_sync_tables(connection)


def get_sync_foundation_status(connection: sqlite3.Connection) -> dict[str, Any]:
    """Restituisce un riepilogo diagnostico, utile durante i test su PC."""

    gallery = connection.execute(
        """
        SELECT gallery_uuid, schema_version, created_at
        FROM sync_gallery_identity
        WHERE singleton_id = 1
        """
    ).fetchone()
    media_count = int(
        connection.execute("SELECT COUNT(*) AS count FROM files").fetchone()["count"]
    )
    missing_ids = int(
        connection.execute(
            """
            SELECT COUNT(*) AS count
            FROM files
            WHERE sync_uuid IS NULL OR TRIM(sync_uuid) = ''
            """
        ).fetchone()["count"]
    )
    duplicate_ids = int(
        connection.execute(
            """
            SELECT COUNT(*) AS count
            FROM (
                SELECT sync_uuid
                FROM files
                WHERE sync_uuid IS NOT NULL AND TRIM(sync_uuid) <> ''
                GROUP BY sync_uuid
                HAVING COUNT(*) > 1
            )
            """
        ).fetchone()["count"]
    )
    peers = int(
        connection.execute(
            "SELECT COUNT(*) AS count FROM sync_peers WHERE is_active = 1"
        ).fetchone()["count"]
    )
    tombstones = int(
        connection.execute("SELECT COUNT(*) AS count FROM sync_tombstones").fetchone()[
            "count"
        ]
    )
    return {
        "schema_version": int(gallery["schema_version"]) if gallery else 0,
        "gallery_uuid": str(gallery["gallery_uuid"]) if gallery else "",
        "media_count": media_count,
        "missing_file_sync_ids": missing_ids,
        "duplicate_file_sync_ids": duplicate_ids,
        "active_peers": peers,
        "pending_tombstones": tombstones,
        "ready": bool(gallery) and missing_ids == 0 and duplicate_ids == 0,
    }
