from __future__ import annotations

import hashlib
import os
import re
import shutil
import tempfile
import threading
import time
import uuid
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from backend.database import ensure_tag, get_connection
from backend.indexer import synchronize_archive
from backend.paths import DATA_ROOT
from backend.scanner import load_config, sync_characters
from backend.sync_foundation import get_sync_foundation_status

_BLOCKED_ROOTS = {".user", ".todo", ".trash", ".script"}
_SAFE_UUID = re.compile(r"^[0-9a-fA-F-]{16,64}$")


class MobileSyncService:
    """Additive Windows <-> Android gallery merge used by M7.

    M7 never overwrites or deletes a different media file. Equality is based on
    SHA-256. Path collisions are preserved by assigning the incoming file a
    deterministic ``_sync_<id>`` suffix.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()

    def _gallery_root(self) -> Path:
        config = load_config()
        root = Path(config["gallery_root"]).expanduser().resolve()
        if not root.exists() or not root.is_dir():
            raise FileNotFoundError("La cartella della galleria Windows non è disponibile.")
        return root

    @staticmethod
    def _safe_relative_path(value: str) -> str:
        raw = str(value or "").replace("\\", "/").strip().strip("/")
        path = PurePosixPath(raw)
        if not raw or path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
            raise ValueError("Percorso relativo non valido.")
        if path.parts[0].casefold() in _BLOCKED_ROOTS:
            raise ValueError("Questa cartella interna non può essere sincronizzata.")
        return path.as_posix()

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def _metadata_for_file(connection, file_id: int) -> dict[str, Any]:
        characters = [
            {
                "name": str(row["character_name"]),
                "relativePath": str(row["character_relative_path"]),
                "franchiseName": str(row["franchise_name"]),
                "franchiseCode": str(row["franchise_code"]),
                "franchiseRelativePath": str(row["franchise_relative_path"]),
            }
            for row in connection.execute(
                """
                SELECT c.name AS character_name,
                       c.relative_path AS character_relative_path,
                       f.name AS franchise_name,
                       f.code AS franchise_code,
                       f.relative_path AS franchise_relative_path
                FROM file_characters fc
                JOIN characters c ON c.id = fc.character_id
                JOIN franchises f ON f.id = c.franchise_id
                WHERE fc.file_id = ?
                ORDER BY f.name COLLATE NOCASE, c.name COLLATE NOCASE
                """,
                (file_id,),
            ).fetchall()
        ]
        tags: list[str] = []
        artists: list[str] = []
        for row in connection.execute(
            """
            SELECT t.name, t.type
            FROM file_tags ft
            JOIN tags t ON t.id = ft.tag_id
            WHERE ft.file_id = ?
            ORDER BY t.name COLLATE NOCASE
            """,
            (file_id,),
        ).fetchall():
            name = str(row["name"])
            tag_type = str(row["type"] or "general")
            if tag_type == "artist":
                artists.append(name)
            elif tag_type == "general" and name.casefold() != "ai":
                tags.append(name)
        return {
            "characters": characters,
            "tags": tags,
            "artists": artists,
        }

    def manifest(self) -> dict[str, Any]:
        root = self._gallery_root()
        with get_connection() as connection:
            foundation = get_sync_foundation_status(connection)
            rows = connection.execute(
                """
                SELECT id, sync_uuid, relative_path, filename, extension,
                       media_type, size, sha256, ai_generated, modified_at
                FROM files
                WHERE is_trashed = 0
                ORDER BY relative_path COLLATE NOCASE
                """
            ).fetchall()
            files: list[dict[str, Any]] = []
            for row in rows:
                relative_path = str(row["relative_path"])
                try:
                    source = (root / relative_path).resolve()
                    source.relative_to(root)
                except (OSError, ValueError):
                    continue
                if not source.is_file():
                    continue
                metadata = self._metadata_for_file(connection, int(row["id"]))
                files.append(
                    {
                        "syncUuid": str(row["sync_uuid"]),
                        "relativePath": relative_path,
                        "filename": str(row["filename"]),
                        "extension": str(row["extension"]),
                        "mediaType": str(row["media_type"]),
                        "sizeBytes": int(row["size"]),
                        "modifiedEpochMs": int(float(row["modified_at"] or 0) * 1000),
                        "sha256": str(row["sha256"]),
                        "aiGenerated": bool(row["ai_generated"]),
                        **metadata,
                    }
                )
            return {
                "schema": 1,
                "galleryUuid": str(foundation["gallery_uuid"]),
                "files": files,
                "count": len(files),
            }

    def file_path(self, sync_uuid: str) -> Path:
        sync_uuid = str(sync_uuid or "").strip()
        if not sync_uuid:
            raise ValueError("Identità media non valida.")
        root = self._gallery_root()
        with get_connection() as connection:
            row = connection.execute(
                "SELECT relative_path FROM files WHERE sync_uuid = ? AND is_trashed = 0 LIMIT 1",
                (sync_uuid,),
            ).fetchone()
        if row is None:
            raise FileNotFoundError("Media non trovato nella galleria Windows.")
        relative = self._safe_relative_path(str(row["relative_path"]))
        path = (root / relative).resolve()
        try:
            path.relative_to(root)
        except ValueError as error:
            raise ValueError("Percorso media non sicuro.") from error
        if not path.is_file():
            raise FileNotFoundError("Il file non è presente sul disco.")
        return path

    @staticmethod
    def _collision_path(root: Path, relative_path: str, sync_uuid: str, sha256: str) -> tuple[Path, str, bool]:
        target = (root / relative_path).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            return target, relative_path, False
        if target.is_file():
            try:
                if MobileSyncService._sha256(target) == sha256:
                    return target, relative_path, True
            except OSError:
                pass
        suffix = re.sub(r"[^0-9a-fA-F]", "", sync_uuid)[:8] or uuid.uuid4().hex[:8]
        pure = PurePosixPath(relative_path)
        parent = pure.parent
        stem = pure.stem
        extension = pure.suffix
        for index in range(0, 10000):
            extra = f"_sync_{suffix}" if index == 0 else f"_sync_{suffix}_{index}"
            name = f"{stem}{extra}{extension}"
            candidate_rel = (parent / name).as_posix() if str(parent) != "." else name
            candidate = (root / candidate_rel).resolve()
            if not candidate.exists():
                candidate.parent.mkdir(parents=True, exist_ok=True)
                return candidate, candidate_rel, False
        raise FileExistsError("Impossibile trovare un nome libero per il media sincronizzato.")

    def import_uploaded_file(self, temporary_path: Path, media: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            relative_path = self._safe_relative_path(str(media.get("relativePath", "")))
            expected_hash = str(media.get("sha256", "")).strip().lower()
            if len(expected_hash) != 64:
                raise ValueError("Hash SHA-256 non valido.")
            actual_hash = self._sha256(temporary_path)
            if actual_hash != expected_hash:
                raise ValueError("Il file ricevuto non corrisponde all'hash dichiarato.")
            sync_uuid = str(media.get("syncUuid", "")).strip()
            if not _SAFE_UUID.match(sync_uuid):
                sync_uuid = str(uuid.uuid4())
            root = self._gallery_root()
            target, final_relative, duplicate_on_disk = self._collision_path(
                root, relative_path, sync_uuid, expected_hash
            )
            if duplicate_on_disk:
                temporary_path.unlink(missing_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(temporary_path), str(target))
                modified_ms = int(media.get("modifiedEpochMs") or 0)
                if modified_ms > 0:
                    try:
                        os.utime(target, (time.time(), modified_ms / 1000.0))
                    except OSError:
                        pass

            # If a previous interrupted M7 run already registered the hash, keep it.
            with get_connection() as connection:
                existing_hash = connection.execute(
                    "SELECT id, sync_uuid, relative_path FROM files WHERE sha256 = ? AND is_trashed = 0 LIMIT 1",
                    (expected_hash,),
                ).fetchone()
                if existing_hash is not None:
                    return {
                        "status": "duplicate",
                        "syncUuid": str(existing_hash["sync_uuid"]),
                        "relativePath": str(existing_hash["relative_path"]),
                    }
                if duplicate_on_disk:
                    # The file exists physically but the DB is stale. Let the indexer create it.
                    synchronize_archive()
                    row = connection.execute(
                        "SELECT id, sync_uuid, relative_path FROM files WHERE sha256 = ? AND is_trashed = 0 LIMIT 1",
                        (expected_hash,),
                    ).fetchone()
                    if row is not None:
                        return {
                            "status": "duplicate",
                            "syncUuid": str(row["sync_uuid"]),
                            "relativePath": str(row["relative_path"]),
                        }

                final_sync_uuid = sync_uuid
                uuid_collision = connection.execute(
                    "SELECT 1 FROM files WHERE sync_uuid = ? LIMIT 1",
                    (final_sync_uuid,),
                ).fetchone()
                if uuid_collision is not None:
                    final_sync_uuid = str(uuid.uuid4())
                stat = target.stat()
                cursor = connection.execute(
                    """
                    INSERT INTO files(
                        sync_uuid, filename, relative_path, media_type, extension,
                        size, sha256, ai_generated, modified_at, is_trashed
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, 0)
                    """,
                    (
                        final_sync_uuid,
                        target.name,
                        final_relative,
                        str(media.get("mediaType") or "image"),
                        target.suffix.lower(),
                        int(stat.st_size),
                        expected_hash,
                        float(stat.st_mtime),
                    ),
                )
                file_id = int(cursor.lastrowid)
            return {
                "status": "imported",
                "fileId": file_id,
                "syncUuid": final_sync_uuid,
                "relativePath": final_relative,
            }

    @staticmethod
    def _find_character_id(connection, character: dict[str, Any]) -> int | None:
        name = str(character.get("name") or "").strip()
        franchise_name = str(character.get("franchiseName") or "").strip()
        if not name or not franchise_name:
            return None
        row = connection.execute(
            """
            SELECT c.id
            FROM characters c JOIN franchises f ON f.id = c.franchise_id
            WHERE c.name = ? COLLATE NOCASE AND f.name = ? COLLATE NOCASE
              AND c.is_active = 1 AND f.is_active = 1
            LIMIT 1
            """,
            (name, franchise_name),
        ).fetchone()
        return int(row["id"]) if row is not None else None

    def merge_metadata(self, items: Iterable[dict[str, Any]]) -> dict[str, int]:
        merged = 0
        unresolved_characters = 0
        with self._lock:
            # New incoming directories may introduce franchises/characters.
            sync_characters()
            with get_connection() as connection:
                for item in items:
                    sha256 = str(item.get("sha256") or "").strip().lower()
                    if len(sha256) != 64:
                        continue
                    file_row = connection.execute(
                        "SELECT id, ai_generated FROM files WHERE sha256 = ? AND is_trashed = 0 LIMIT 1",
                        (sha256,),
                    ).fetchone()
                    if file_row is None:
                        continue
                    file_id = int(file_row["id"])
                    if bool(item.get("aiGenerated")) and not bool(file_row["ai_generated"]):
                        connection.execute("UPDATE files SET ai_generated = 1 WHERE id = ?", (file_id,))
                        ai_id, _, _ = ensure_tag(connection, "AI", "system")
                        connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, ai_id),
                        )
                    for tag in item.get("tags") or []:
                        name = " ".join(str(tag).split())
                        if not name or name.casefold() == "ai":
                            continue
                        tag_id, _, _ = ensure_tag(connection, name, "general")
                        connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, tag_id),
                        )
                    for artist in item.get("artists") or []:
                        name = " ".join(str(artist).split())
                        if not name or name.casefold() == "ai":
                            continue
                        tag_id, _, _ = ensure_tag(connection, name, "artist")
                        connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, tag_id),
                        )
                    for character in item.get("characters") or []:
                        if not isinstance(character, dict):
                            continue
                        character_id = self._find_character_id(connection, character)
                        if character_id is None:
                            unresolved_characters += 1
                            continue
                        connection.execute(
                            "INSERT OR IGNORE INTO file_characters(file_id, character_id) VALUES (?, ?)",
                            (file_id, character_id),
                        )
                    merged += 1
        return {"merged": merged, "unresolvedCharacters": unresolved_characters}

    def finalize(self, *, device_id: str, android_gallery_uuid: str, android_gallery_name: str) -> dict[str, Any]:
        with self._lock:
            archive = synchronize_archive()
            with get_connection() as connection:
                foundation = get_sync_foundation_status(connection)
                peer_uuid = f"{device_id}:{android_gallery_uuid}"[:240]
                connection.execute(
                    """
                    INSERT INTO sync_peers(
                        peer_uuid, peer_gallery_uuid, display_name, platform,
                        paired_at, last_seen_at, is_active
                    ) VALUES (?, ?, ?, 'android', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                    ON CONFLICT(peer_gallery_uuid) DO UPDATE SET
                        peer_uuid = excluded.peer_uuid,
                        display_name = excluded.display_name,
                        platform = 'android',
                        last_seen_at = CURRENT_TIMESTAMP,
                        is_active = 1
                    """,
                    (
                        peer_uuid,
                        android_gallery_uuid,
                        android_gallery_name or "H-Gallery Android",
                    ),
                )
                final_count = int(
                    connection.execute(
                        "SELECT COUNT(*) AS count FROM files WHERE is_trashed = 0"
                    ).fetchone()["count"]
                )
            return {
                "galleryUuid": str(foundation["gallery_uuid"]),
                "count": final_count,
                "archive": archive,
            }

    @staticmethod
    def new_temporary_upload() -> Path:
        directory = DATA_ROOT / "sync_tmp"
        directory.mkdir(parents=True, exist_ok=True)
        handle, name = tempfile.mkstemp(prefix="m7_", suffix=".part", dir=directory)
        os.close(handle)
        return Path(name)


MOBILE_SYNC_SERVICE = MobileSyncService()
