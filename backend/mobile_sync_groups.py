from __future__ import annotations

import sqlite3
import threading
import uuid
from pathlib import Path
from typing import Any

from backend.app_config import list_galleries
from backend.paths import GALLERY_ID, SCRIPT_ROOT
from backend.sync_foundation import initialize_sync_schema

_SYNC_GROUP_KEY = "sync_group_uuid"


class MobileSyncGroupService:
    """Gestisce l'identità logica delle gallerie sincronizzate.

    Ogni galleria mantiene il proprio ``gallery_uuid`` (identità della singola
    galleria) e, solo quando viene collegata, un ``sync_group_uuid`` dentro la
    tabella ``sync_state``. Gallerie su dispositivi diversi che condividono lo
    stesso ``sync_group_uuid`` rappresentano la stessa galleria logica.

    Il gruppo non dipende dal nome della galleria e sopravvive ai rename.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()

    @staticmethod
    def _database_path(entry: dict[str, Any]) -> Path:
        return Path(str(entry["path"])).expanduser().resolve() / ".user" / "data" / "gallery.db"

    @staticmethod
    def _connect(database_path: Path) -> sqlite3.Connection:
        connection = sqlite3.connect(database_path)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    @staticmethod
    def _table_exists(connection: sqlite3.Connection, table_name: str) -> bool:
        row = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
            (table_name,),
        ).fetchone()
        return row is not None

    @staticmethod
    def _read_group(connection: sqlite3.Connection) -> str:
        if not MobileSyncGroupService._table_exists(connection, "sync_state"):
            return ""
        row = connection.execute(
            "SELECT value FROM sync_state WHERE key = ? LIMIT 1",
            (_SYNC_GROUP_KEY,),
        ).fetchone()
        return str(row["value"]).strip() if row is not None else ""

    @staticmethod
    def _read_gallery_uuid(connection: sqlite3.Connection) -> str:
        if not MobileSyncGroupService._table_exists(connection, "sync_gallery_identity"):
            return ""
        row = connection.execute(
            "SELECT gallery_uuid FROM sync_gallery_identity WHERE singleton_id = 1 LIMIT 1"
        ).fetchone()
        return str(row["gallery_uuid"]).strip() if row is not None else ""

    def _prepare_database(self, entry: dict[str, Any]) -> tuple[sqlite3.Connection, Path]:
        database_path = self._database_path(entry)
        if not database_path.is_file():
            raise FileNotFoundError(
                f"La galleria Windows '{entry.get('name', 'Galleria')}' non è ancora indicizzata. "
                "Aprila almeno una volta in H-Gallery Windows."
            )
        connection = self._connect(database_path)
        try:
            if not self._table_exists(connection, "files"):
                raise ValueError("Il database della galleria Windows non è valido.")
            initialize_sync_schema(connection)
            connection.commit()
            return connection, database_path
        except Exception:
            connection.close()
            raise

    def _entries(self) -> list[dict[str, Any]]:
        data = list_galleries(script_root=SCRIPT_ROOT)
        return [dict(item) for item in data.get("results", [])]

    def _entry_by_registry_id(self, registry_id: str) -> dict[str, Any]:
        requested = str(registry_id or "").strip()
        for entry in self._entries():
            if str(entry.get("id", "")) == requested:
                return entry
        raise ValueError("Galleria Windows non trovata.")

    def _gallery_info(self, entry: dict[str, Any]) -> dict[str, Any]:
        available = bool(entry.get("available")) and Path(str(entry.get("path", ""))).is_dir()
        result: dict[str, Any] = {
            "registryId": str(entry.get("id", "")),
            "name": str(entry.get("name", "Galleria")),
            "available": available,
            # Rappresenta la galleria effettivamente caricata dal processo server,
            # non soltanto il valore corrente del registro su disco.
            "active": str(entry.get("id", "")) == GALLERY_ID,
            "galleryUuid": "",
            "syncGroupUuid": "",
            "mediaCount": 0,
            "syncReady": False,
        }
        if not available:
            return result
        database_path = self._database_path(entry)
        if not database_path.is_file():
            return result
        try:
            connection, _ = self._prepare_database(entry)
        except (OSError, sqlite3.Error, ValueError, FileNotFoundError):
            return result
        try:
            result["galleryUuid"] = self._read_gallery_uuid(connection)
            result["syncGroupUuid"] = self._read_group(connection)
            row = connection.execute(
                "SELECT COUNT(*) AS count FROM files WHERE is_trashed = 0"
            ).fetchone()
            result["mediaCount"] = int(row["count"]) if row is not None else 0
            result["syncReady"] = bool(result["galleryUuid"])
            return result
        finally:
            connection.close()

    def list_windows_galleries(self) -> dict[str, Any]:
        with self._lock:
            galleries = [self._gallery_info(entry) for entry in self._entries()]
            return {
                "schema": 1,
                "runtimeActiveRegistryId": GALLERY_ID,
                "galleries": galleries,
            }

    def link(
        self,
        *,
        windows_registry_id: str,
        android_gallery_uuid: str,
        android_gallery_name: str,
        android_group_uuid: str = "",
    ) -> dict[str, Any]:
        del android_gallery_uuid  # L'identità Android è validata e persistita sul dispositivo Android.
        del android_gallery_name
        with self._lock:
            entry = self._entry_by_registry_id(windows_registry_id)
            if not bool(entry.get("available")):
                raise FileNotFoundError("La galleria Windows selezionata non è disponibile sul PC.")
            connection, _ = self._prepare_database(entry)
            try:
                windows_gallery_uuid = self._read_gallery_uuid(connection)
                windows_group = self._read_group(connection)
                android_group = str(android_group_uuid or "").strip()

                if windows_group and android_group and windows_group != android_group:
                    raise ValueError(
                        "Le due gallerie appartengono già a gruppi di sincronizzazione diversi. "
                        "Scollega prima una delle due gallerie."
                    )

                group_uuid = windows_group or android_group or str(uuid.uuid4())
                connection.execute(
                    """
                    INSERT INTO sync_state(key, value, updated_at)
                    VALUES (?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(key) DO UPDATE SET
                        value = excluded.value,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    (_SYNC_GROUP_KEY, group_uuid),
                )
                connection.commit()
                return {
                    "status": "linked",
                    "syncGroupUuid": group_uuid,
                    "windowsRegistryId": str(entry["id"]),
                    "windowsGalleryUuid": windows_gallery_uuid,
                    "windowsGalleryName": str(entry.get("name", "H-Gallery Windows")),
                    "windowsActive": str(entry["id"]) == GALLERY_ID,
                }
            finally:
                connection.close()

    def require_active_link(
        self,
        *,
        sync_group_uuid: str,
        windows_gallery_uuid: str,
    ) -> dict[str, Any]:
        requested_group = str(sync_group_uuid or "").strip()
        requested_gallery = str(windows_gallery_uuid or "").strip()
        if not requested_group or not requested_gallery:
            raise PermissionError("Collegamento gallerie M7 mancante.")

        with self._lock:
            entries = self._entries()
            active_entry = next(
                (entry for entry in entries if str(entry.get("id", "")) == GALLERY_ID),
                None,
            )
            if active_entry is None:
                raise RuntimeError("La galleria Windows attiva non è disponibile.")
            active_info = self._gallery_info(active_entry)
            if active_info["galleryUuid"] != requested_gallery:
                target = None
                for entry in entries:
                    candidate = self._gallery_info(entry)
                    if candidate["galleryUuid"] == requested_gallery:
                        target = candidate
                        break
                target_name = target["name"] if target else "la galleria Windows collegata"
                raise RuntimeError(
                    f"Apri '{target_name}' come galleria attiva su Windows e riavvia H-Gallery prima di sincronizzare."
                )
            if active_info["syncGroupUuid"] != requested_group:
                raise PermissionError(
                    "La galleria Windows attiva non appartiene al gruppo di sincronizzazione richiesto."
                )
            return active_info


MOBILE_SYNC_GROUPS = MobileSyncGroupService()
