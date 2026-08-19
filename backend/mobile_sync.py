from __future__ import annotations

import hashlib
import json
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
from backend.scanner import create_character, create_franchise, load_config, sync_characters
from backend.sync_foundation import get_sync_foundation_status
from backend.trash import trash_gallery_file

_BLOCKED_ROOTS = {".user", ".todo", ".trash", ".script"}
_SAFE_UUID = re.compile(r"^[0-9a-fA-F-]{16,64}$")


class MobileSyncService:
    """Windows <-> Android gallery merge used by M7.

    File transfers remain conservative and collision-safe. M7.5 handles only
    explicit, tombstone-backed media removals. M7.6 adds verified three-way
    metadata baselines: removals are propagated only when both peers prove the
    same previous state; otherwise metadata merging falls back to additive mode.
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
    def _current_sync_group_uuid(connection) -> str:
        row = connection.execute(
            "SELECT value FROM sync_state WHERE key = 'sync_group_uuid' LIMIT 1"
        ).fetchone()
        return str(row["value"] if row is not None else "").strip()

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
            sync_group_uuid = self._current_sync_group_uuid(connection)
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
            tombstones = [
                {
                    "fileUuid": str(row["file_uuid"]),
                    "sha256": str(row["sha256"]).lower(),
                    "mediaType": str(row["media_type"]),
                    "lastRelativePath": str(row["last_relative_path"]),
                    "deletedAt": str(row["deleted_at"]),
                    "originPeerUuid": str(row["origin_peer_uuid"] or ""),
                    "createdLocally": bool(row["created_locally"]),
                }
                for row in connection.execute(
                    """
                    SELECT file_uuid, sha256, media_type, last_relative_path,
                           deleted_at, origin_peer_uuid, created_locally, sync_group_uuid
                    FROM sync_tombstones
                    WHERE sync_group_uuid = ? AND sync_group_uuid <> ''
                    ORDER BY deleted_at, file_uuid
                    """,
                    (sync_group_uuid,),
                ).fetchall()
            ]
            for item in tombstones:
                item["syncGroupUuid"] = sync_group_uuid

            metadata_baselines: list[dict[str, Any]] = []
            if sync_group_uuid:
                for row in connection.execute(
                    """
                    SELECT peer_gallery_uuid, media_sha256, snapshot_json
                    FROM sync_metadata_baselines
                    WHERE sync_group_uuid = ?
                    ORDER BY peer_gallery_uuid, media_sha256
                    """,
                    (sync_group_uuid,),
                ).fetchall():
                    try:
                        snapshot = json.loads(str(row["snapshot_json"]))
                    except (TypeError, ValueError, json.JSONDecodeError):
                        continue
                    if not isinstance(snapshot, dict):
                        continue
                    metadata_baselines.append(
                        {
                            "peerGalleryUuid": str(row["peer_gallery_uuid"]),
                            "sha256": str(row["media_sha256"]).lower(),
                            "snapshot": snapshot,
                        }
                    )
            return {
                "schema": 4,
                "galleryUuid": str(foundation["gallery_uuid"]),
                "files": files,
                "tombstones": tombstones,
                "metadataBaselines": metadata_baselines,
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

    def _live_hash_row(self, root: Path, sha256: str):
        with get_connection() as connection:
            row = connection.execute(
                "SELECT id, sync_uuid, relative_path FROM files WHERE sha256 = ? AND is_trashed = 0 LIMIT 1",
                (sha256,),
            ).fetchone()
        if row is None:
            return None
        try:
            relative = self._safe_relative_path(str(row["relative_path"]))
            path = (root / relative).resolve()
            path.relative_to(root)
            if path.is_file() and self._sha256(path) == sha256:
                return row
        except (OSError, ValueError):
            pass
        return None

    def import_uploaded_file(self, temporary_path: Path, media: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            relative_path = self._safe_relative_path(str(media.get("relativePath", "")))
            expected_hash = str(media.get("sha256", "")).strip().lower()
            if len(expected_hash) != 64:
                raise ValueError("Hash SHA-256 non valido.")
            actual_hash = self._sha256(temporary_path)
            if actual_hash != expected_hash:
                raise ValueError("Il file ricevuto non corrisponde all'hash dichiarato.")

            root = self._gallery_root()
            incoming_uuid = str(media.get("syncUuid", "")).strip()
            with get_connection() as connection:
                sync_group_uuid = self._current_sync_group_uuid(connection)
                tombstone = connection.execute(
                    """
                    SELECT file_uuid FROM sync_tombstones
                    WHERE sync_group_uuid = ?
                      AND (file_uuid = ? OR sha256 = ?)
                    LIMIT 1
                    """,
                    (sync_group_uuid, incoming_uuid, expected_hash),
                ).fetchone() if sync_group_uuid else None
            if tombstone is not None:
                temporary_path.unlink(missing_ok=True)
                return {
                    "status": "tombstoned",
                    "syncUuid": str(tombstone["file_uuid"]),
                    "message": "Il media è stato eliminato nel gruppo di sincronizzazione.",
                }
            # Prima di toccare il filesystem controlla un duplicato realmente
            # presente su disco. Una riga DB stale non deve far perdere il file
            # che Android sta tentando di ripristinare.
            existing_hash = self._live_hash_row(root, expected_hash)
            if existing_hash is not None:
                temporary_path.unlink(missing_ok=True)
                return {
                    "status": "duplicate",
                    "syncUuid": str(existing_hash["sync_uuid"]),
                    "relativePath": str(existing_hash["relative_path"]),
                }

            sync_uuid = str(media.get("syncUuid", "")).strip()
            if not _SAFE_UUID.match(sync_uuid):
                sync_uuid = str(uuid.uuid4())
            target, final_relative, duplicate_on_disk = self._collision_path(
                root, relative_path, sync_uuid, expected_hash
            )

            if duplicate_on_disk:
                temporary_path.unlink(missing_ok=True)
                # Il file fisico esiste già ma il DB può essere rimasto indietro
                # dopo un arresto improvviso. Ricostruisci l'indice prima di creare
                # manualmente una nuova riga.
                synchronize_archive()
                with get_connection() as connection:
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
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(temporary_path), str(target))
                modified_ms = int(media.get("modifiedEpochMs") or 0)
                if modified_ms > 0:
                    try:
                        os.utime(target, (time.time(), modified_ms / 1000.0))
                    except OSError:
                        pass

            # Un secondo controllo chiude la finestra tra il primo lookup e
            # l'import fisico (utile se in futuro più peer sincronizzano insieme).
            existing_hash = self._live_hash_row(root, expected_hash)
            if existing_hash is not None:
                if not duplicate_on_disk:
                    try:
                        if target.is_file() and self._sha256(target) == expected_hash:
                            target.unlink(missing_ok=True)
                    except OSError:
                        pass
                return {
                    "status": "duplicate",
                    "syncUuid": str(existing_hash["sync_uuid"]),
                    "relativePath": str(existing_hash["relative_path"]),
                }

            with get_connection() as connection:
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

    def _ensure_character_catalog(self, items: Iterable[dict[str, Any]]) -> dict[str, int]:
        """Crea su Windows serie/personaggi metadata che esistono solo su Android.

        Le entità vengono create tramite le API del normale scanner H-Gallery, così
        database e struttura di cartelle restano coerenti. Il merge dei file resta
        comunque additivo: nessuna entità esistente viene rinominata o rimossa.
        """
        unique: dict[tuple[str, str], dict[str, Any]] = {}
        for item in items:
            for raw in item.get("characters") or []:
                if not isinstance(raw, dict):
                    continue
                name = " ".join(str(raw.get("name") or "").split())
                franchise = " ".join(str(raw.get("franchiseName") or "").split())
                if not name or not franchise:
                    continue
                unique[(franchise.casefold(), name.casefold())] = dict(raw)

        created_franchises = 0
        created_characters = 0
        unresolved = 0
        if not unique:
            return {
                "createdFranchises": 0,
                "createdCharacters": 0,
                "unresolvedCatalogCharacters": 0,
            }

        sync_characters()
        for character in unique.values():
            name = " ".join(str(character.get("name") or "").split())
            franchise_name = " ".join(str(character.get("franchiseName") or "").split())
            with get_connection() as connection:
                if self._find_character_id(connection, character) is not None:
                    continue
                franchise_row = connection.execute(
                    "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE AND is_active = 1 LIMIT 1",
                    (franchise_name,),
                ).fetchone()
                franchise_id = int(franchise_row["id"]) if franchise_row is not None else None

            if franchise_id is None:
                requested_code = "".join(str(character.get("franchiseCode") or "").split()) or None
                try:
                    created = create_franchise(franchise_name, requested_code)
                    franchise_id = int(created["id"])
                    created_franchises += 1
                except Exception:
                    # Può esistere già per una differenza di maiuscole oppure per
                    # una creazione concorrente: rileggi prima di dichiarare errore.
                    with get_connection() as connection:
                        row = connection.execute(
                            "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE AND is_active = 1 LIMIT 1",
                            (franchise_name,),
                        ).fetchone()
                    franchise_id = int(row["id"]) if row is not None else None

            if franchise_id is None:
                unresolved += 1
                continue

            try:
                create_character(franchise_id, name)
                created_characters += 1
            except Exception:
                with get_connection() as connection:
                    if self._find_character_id(connection, character) is None:
                        unresolved += 1

        return {
            "createdFranchises": created_franchises,
            "createdCharacters": created_characters,
            "unresolvedCatalogCharacters": unresolved,
        }

    @staticmethod
    def _clean_tombstone(item: dict[str, Any]) -> dict[str, Any] | None:
        file_uuid = str(item.get("fileUuid") or item.get("syncUuid") or "").strip()
        sha256 = str(item.get("sha256") or "").strip().lower()
        media_type = str(item.get("mediaType") or "image").strip().lower()
        relative_path = str(item.get("lastRelativePath") or item.get("relativePath") or "").strip()
        if not _SAFE_UUID.match(file_uuid) or len(sha256) != 64:
            return None
        if media_type not in {"image", "video"}:
            media_type = "image"
        try:
            relative_path = MobileSyncService._safe_relative_path(relative_path)
        except ValueError:
            return None
        return {
            "fileUuid": file_uuid,
            "sha256": sha256,
            "mediaType": media_type,
            "lastRelativePath": relative_path,
            "deletedAt": str(item.get("deletedAt") or "").strip(),
            "originPeerUuid": str(item.get("originPeerUuid") or "").strip()[:240],
        }

    @staticmethod
    def _store_remote_tombstone(tombstone: dict[str, Any], sync_group_uuid: str) -> None:
        if not sync_group_uuid:
            raise ValueError("La galleria Windows non appartiene a un gruppo di sincronizzazione.")
        with get_connection() as connection:
            if tombstone["deletedAt"]:
                connection.execute(
                    """
                    INSERT INTO sync_tombstones(
                        file_uuid, sha256, media_type, last_relative_path,
                        deleted_at, origin_peer_uuid, created_locally, sync_group_uuid
                    ) VALUES (?, ?, ?, ?, ?, ?, 0, ?)
                    ON CONFLICT(file_uuid) DO UPDATE SET
                        sha256 = excluded.sha256,
                        media_type = excluded.media_type,
                        last_relative_path = excluded.last_relative_path,
                        deleted_at = excluded.deleted_at,
                        origin_peer_uuid = excluded.origin_peer_uuid,
                        created_locally = 0,
                        sync_group_uuid = excluded.sync_group_uuid
                    WHERE sync_tombstones.sync_group_uuid = excluded.sync_group_uuid
                       OR sync_tombstones.sync_group_uuid = ''
                    """,
                    (
                        tombstone["fileUuid"], tombstone["sha256"], tombstone["mediaType"],
                        tombstone["lastRelativePath"], tombstone["deletedAt"],
                        tombstone["originPeerUuid"] or None, sync_group_uuid,
                    ),
                )
            else:
                connection.execute(
                    """
                    INSERT INTO sync_tombstones(
                        file_uuid, sha256, media_type, last_relative_path,
                        origin_peer_uuid, created_locally, sync_group_uuid
                    ) VALUES (?, ?, ?, ?, ?, 0, ?)
                    ON CONFLICT(file_uuid) DO UPDATE SET
                        sha256 = excluded.sha256,
                        media_type = excluded.media_type,
                        last_relative_path = excluded.last_relative_path,
                        origin_peer_uuid = excluded.origin_peer_uuid,
                        created_locally = 0,
                        sync_group_uuid = excluded.sync_group_uuid
                    WHERE sync_tombstones.sync_group_uuid = excluded.sync_group_uuid
                       OR sync_tombstones.sync_group_uuid = ''
                    """,
                    (
                        tombstone["fileUuid"], tombstone["sha256"], tombstone["mediaType"],
                        tombstone["lastRelativePath"], tombstone["originPeerUuid"] or None,
                        sync_group_uuid,
                    ),
                )

    @staticmethod
    def _resolve_tombstone_target(tombstone: dict[str, Any]) -> tuple[int | None, str | None]:
        """Trova un solo media attivo senza mai indovinare una cancellazione.

        Priorità: UUID+SHA. Per gallerie collegate prima di M7.5, dove lo stesso
        contenuto può avere UUID diversi, accetta SHA solo se individua un unico
        media; se ci sono duplicati identici usa il percorso solo quando è unico.
        """
        with get_connection() as connection:
            exact = connection.execute(
                "SELECT id, sha256 FROM files WHERE sync_uuid = ? AND is_trashed = 0 LIMIT 1",
                (tombstone["fileUuid"],),
            ).fetchone()
            if exact is not None:
                if str(exact["sha256"]).lower() != tombstone["sha256"]:
                    return None, "UUID uguale ma SHA-256 differente: cancellazione bloccata."
                target_id = int(exact["id"])
                story = connection.execute(
                    "SELECT story_id FROM story_pages WHERE file_id = ? LIMIT 1",
                    (target_id,),
                ).fetchone()
                if story is not None:
                    return None, (
                        "Il media appartiene a una storia Windows. Sciogli prima la storia: "
                        "la cancellazione sincronizzata è stata bloccata."
                    )
                return target_id, None

            candidates = connection.execute(
                """
                SELECT id, relative_path
                FROM files
                WHERE sha256 = ? AND is_trashed = 0
                ORDER BY id
                """,
                (tombstone["sha256"],),
            ).fetchall()
            if not candidates:
                return None, None
            if len(candidates) == 1:
                target_id = int(candidates[0]["id"])
                story = connection.execute(
                    "SELECT story_id FROM story_pages WHERE file_id = ? LIMIT 1",
                    (target_id,),
                ).fetchone()
                if story is not None:
                    return None, (
                        "Il media appartiene a una storia Windows. Sciogli prima la storia: "
                        "la cancellazione sincronizzata è stata bloccata."
                    )
                return target_id, None

            path_matches = [
                row for row in candidates
                if str(row["relative_path"]).casefold() == tombstone["lastRelativePath"].casefold()
            ]
            if len(path_matches) == 1:
                target_id = int(path_matches[0]["id"])
                story = connection.execute(
                    "SELECT story_id FROM story_pages WHERE file_id = ? LIMIT 1",
                    (target_id,),
                ).fetchone()
                if story is not None:
                    return None, (
                        "Il media appartiene a una storia Windows. Sciogli prima la storia: "
                        "la cancellazione sincronizzata è stata bloccata."
                    )
                return target_id, None
            return None, "Più media identici corrispondono alla tombstone: cancellazione ambigua bloccata."

    def _apply_tombstones(self, items: Iterable[dict[str, Any]]) -> dict[str, Any]:
        item_list = list(items)
        moved_to_trash = 0
        already_absent = 0
        conflicts: list[dict[str, str]] = []
        applied = 0
        with get_connection() as connection:
            sync_group_uuid = self._current_sync_group_uuid(connection)
        if item_list and not sync_group_uuid:
            return {
                "deletionsApplied": 0,
                "deletedMovedToTrash": 0,
                "deletionAlreadyAbsent": 0,
                "deletionConflicts": len(item_list),
                "deletionConflictDetails": [{
                    "fileUuid": str(item.get("fileUuid") or ""),
                    "relativePath": str(item.get("lastRelativePath") or ""),
                    "message": "Gruppo di sincronizzazione Windows assente: cancellazione bloccata.",
                } for item in item_list],
            }

        # Preflight completo del batch: nessuna cancellazione del batch viene
        # applicata se anche una sola tombstone è ambigua o appartiene a un
        # gruppo differente. Questo evita merge distruttivi parziali.
        resolved: list[tuple[dict[str, Any], int | None]] = []
        for raw in item_list:
            tombstone = self._clean_tombstone(raw)
            if tombstone is None:
                conflicts.append({
                    "fileUuid": str(raw.get("fileUuid") or ""),
                    "relativePath": str(raw.get("lastRelativePath") or ""),
                    "message": "Tombstone non valida: cancellazione ignorata.",
                })
                continue
            with get_connection() as connection:
                existing = connection.execute(
                    "SELECT sync_group_uuid, sha256 FROM sync_tombstones WHERE file_uuid = ? LIMIT 1",
                    (tombstone["fileUuid"],),
                ).fetchone()
            if existing is not None:
                existing_group = str(existing["sync_group_uuid"] or "").strip()
                existing_sha = str(existing["sha256"] or "").lower()
                if existing_group and existing_group != sync_group_uuid:
                    conflicts.append({
                        "fileUuid": tombstone["fileUuid"],
                        "relativePath": tombstone["lastRelativePath"],
                        "message": "La stessa identità media appartiene a una tombstone di un altro gruppo: cancellazione bloccata.",
                    })
                    continue
                if existing_group == sync_group_uuid and existing_sha and existing_sha != tombstone["sha256"]:
                    conflicts.append({
                        "fileUuid": tombstone["fileUuid"],
                        "relativePath": tombstone["lastRelativePath"],
                        "message": "La stessa tombstone ha SHA-256 differente: cancellazione bloccata.",
                    })
                    continue
            target_id, conflict = self._resolve_tombstone_target(tombstone)
            if conflict:
                conflicts.append({
                    "fileUuid": tombstone["fileUuid"],
                    "relativePath": tombstone["lastRelativePath"],
                    "message": conflict,
                })
                continue
            resolved.append((tombstone, target_id))

        if conflicts:
            return {
                "deletionsApplied": 0,
                "deletedMovedToTrash": 0,
                "deletionAlreadyAbsent": 0,
                "deletionConflicts": len(conflicts),
                "deletionConflictDetails": conflicts,
            }

        validate_only = bool(item_list) and all(bool(item.get("validateOnly")) for item in item_list)
        if validate_only:
            return {
                "deletionsApplied": 0,
                "deletedMovedToTrash": 0,
                "deletionAlreadyAbsent": 0,
                "deletionConflicts": 0,
                "deletionConflictDetails": [],
                "deletionsValidated": len(resolved),
            }

        handled_target_ids: set[int] = set()
        for tombstone, target_id in resolved:
            # Registra prima l'intenzione di cancellazione. Se il processo si
            # interrompe subito dopo, al prossimo tentativo la tombstone resta
            # disponibile e l'operazione può essere ripresa in modo idempotente.
            self._store_remote_tombstone(tombstone, sync_group_uuid)
            applied += 1
            if target_id is not None and target_id not in handled_target_ids:
                handled_target_ids.add(target_id)
                try:
                    # M7.5 non distrugge la copia remota: la sposta nel cestino
                    # locale. La tombstone impedisce comunque che venga ricopiata.
                    trash_gallery_file(target_id)
                    moved_to_trash += 1
                except Exception as error:
                    conflicts.append({
                        "fileUuid": tombstone["fileUuid"],
                        "relativePath": tombstone["lastRelativePath"],
                        "message": f"Tombstone registrata, ma impossibile spostare il media nel cestino Windows: {error}",
                    })
                    continue
            elif target_id is None:
                already_absent += 1
        return {
            "deletionsApplied": applied,
            "deletedMovedToTrash": moved_to_trash,
            "deletionAlreadyAbsent": already_absent,
            "deletionConflicts": len(conflicts),
            "deletionConflictDetails": conflicts,
        }

    @staticmethod
    def _clean_baseline_snapshot(value: Any) -> dict[str, Any] | None:
        if not isinstance(value, dict):
            return None
        tags_raw = value.get("tags")
        characters_raw = value.get("characters")
        if not isinstance(tags_raw, dict) or not isinstance(characters_raw, dict):
            return None
        tags: dict[str, dict[str, str]] = {}
        for raw_key, raw_value in tags_raw.items():
            key = " ".join(str(raw_key).split()).casefold()
            if not key or not isinstance(raw_value, dict):
                continue
            tag_type = str(raw_value.get("type") or "").strip().casefold()
            if tag_type not in {"general", "artist"}:
                continue
            name = " ".join(str(raw_value.get("name") or raw_key).split())
            if not name or name.casefold() == "ai":
                continue
            tags[key] = {"name": name, "type": tag_type}
        characters: dict[str, dict[str, str]] = {}
        for raw_key, raw_value in characters_raw.items():
            key = str(raw_key or "").strip().casefold()
            if not key or not isinstance(raw_value, dict):
                continue
            name = " ".join(str(raw_value.get("name") or "").split())
            franchise = " ".join(str(raw_value.get("franchiseName") or "").split())
            if not name or not franchise:
                continue
            characters[key] = {
                "name": name,
                "franchiseName": franchise,
                "relativePath": str(raw_value.get("relativePath") or "").strip(),
                "franchiseCode": str(raw_value.get("franchiseCode") or "").strip(),
                "franchiseRelativePath": str(raw_value.get("franchiseRelativePath") or "").strip(),
            }
        return {
            "version": 1,
            "tags": tags,
            "characters": characters,
            "aiGenerated": bool(value.get("aiGenerated")),
        }

    def _store_metadata_baseline_controls(
        self,
        items: list[dict[str, Any]],
        sync_group_uuid: str,
    ) -> int:
        if not items or not sync_group_uuid:
            return 0
        stored = 0
        with get_connection() as connection:
            for item in items:
                group = str(item.get("baselineSyncGroupUuid") or "").strip()
                peer = str(item.get("baselinePeerGalleryUuid") or "").strip()
                if group != sync_group_uuid or not peer:
                    continue
                if bool(item.get("baselineReset")):
                    connection.execute(
                        "DELETE FROM sync_metadata_baselines "
                        "WHERE sync_group_uuid = ? AND peer_gallery_uuid = ?",
                        (sync_group_uuid, peer),
                    )
                sha256 = str(item.get("sha256") or "").strip().lower()
                if len(sha256) != 64:
                    continue
                snapshot = self._clean_baseline_snapshot(item.get("snapshot"))
                if snapshot is None:
                    continue
                connection.execute(
                    """
                    INSERT INTO sync_metadata_baselines(
                        sync_group_uuid, peer_gallery_uuid, media_sha256,
                        snapshot_json, updated_at
                    ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(sync_group_uuid, peer_gallery_uuid, media_sha256)
                    DO UPDATE SET
                        snapshot_json = excluded.snapshot_json,
                        updated_at = CURRENT_TIMESTAMP
                    """,
                    (
                        sync_group_uuid,
                        peer,
                        sha256,
                        json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":")),
                    ),
                )
                stored += 1
        return stored

    @staticmethod
    def _metadata_key(value: str) -> str:
        return " ".join(str(value).split()).casefold()

    def _replace_file_metadata(
        self,
        connection,
        file_id: int,
        file_row,
        item: dict[str, Any],
    ) -> tuple[bool, int, int, int, int, int]:
        desired_tags: dict[str, str] = {}
        for value in item.get("tags") or []:
            name = " ".join(str(value).split())
            if name and name.casefold() != "ai":
                desired_tags[self._metadata_key(name)] = name
        desired_artists: dict[str, str] = {}
        for value in item.get("artists") or []:
            name = " ".join(str(value).split())
            if name and name.casefold() != "ai":
                key = self._metadata_key(name)
                desired_artists[key] = name
                desired_tags.pop(key, None)
        desired_ai = bool(item.get("aiGenerated"))

        desired_characters: list[int] = []
        unresolved = 0
        for character in item.get("characters") or []:
            if not isinstance(character, dict):
                continue
            character_id = self._find_character_id(connection, character)
            if character_id is None:
                unresolved += 1
            else:
                desired_characters.append(character_id)
        if unresolved:
            # Non eliminare associazioni personaggio se non possiamo ricostruire
            # integralmente lo stato desiderato.
            return False, 0, 0, 0, 0, unresolved

        current_metadata = self._metadata_for_file(connection, file_id)
        current_tags = {self._metadata_key(v) for v in current_metadata["tags"]}
        current_artists = {self._metadata_key(v) for v in current_metadata["artists"]}
        current_characters = {
            f"{self._metadata_key(c.get('franchiseName', ''))}\u0000{self._metadata_key(c.get('name', ''))}"
            for c in current_metadata["characters"]
        }
        desired_character_keys = {
            f"{self._metadata_key(str(c.get('franchiseName') or ''))}\u0000{self._metadata_key(str(c.get('name') or ''))}"
            for c in item.get("characters") or [] if isinstance(c, dict)
        }
        current_ai = bool(file_row["ai_generated"])
        changed = (
            current_tags != set(desired_tags) or
            current_artists != set(desired_artists) or
            current_characters != desired_character_keys or
            current_ai != desired_ai
        )
        if not changed:
            return False, 0, 0, 0, 0, 0

        connection.execute("UPDATE files SET ai_generated = ? WHERE id = ?", (int(desired_ai), file_id))
        connection.execute("DELETE FROM file_characters WHERE file_id = ?", (file_id,))
        for character_id in sorted(set(desired_characters)):
            connection.execute(
                "INSERT OR IGNORE INTO file_characters(file_id, character_id) VALUES (?, ?)",
                (file_id, character_id),
            )

        # Rimuove soltanto metadata gestiti dal sync (general/artist e AI),
        # lasciando intatti eventuali futuri tag di sistema non conosciuti.
        connection.execute(
            """
            DELETE FROM file_tags
            WHERE file_id = ? AND tag_id IN (
                SELECT id FROM tags
                WHERE type IN ('general', 'artist') OR name = 'AI' COLLATE NOCASE
            )
            """,
            (file_id,),
        )
        tags_added = 0
        artists_added = 0
        for name in desired_tags.values():
            tag_id, _, _ = ensure_tag(connection, name, "general")
            cursor = connection.execute(
                "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                (file_id, tag_id),
            )
            if cursor.rowcount > 0:
                tags_added += 1
        for name in desired_artists.values():
            tag_id, _, _ = ensure_tag(connection, name, "artist")
            cursor = connection.execute(
                "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                (file_id, tag_id),
            )
            if cursor.rowcount > 0:
                artists_added += 1
        if desired_ai:
            ai_id, _, _ = ensure_tag(connection, "AI", "system")
            connection.execute(
                "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                (file_id, ai_id),
            )
        return True, int(current_ai != desired_ai), tags_added, artists_added, len(set(desired_characters)), 0

    def merge_metadata(self, items: Iterable[dict[str, Any]]) -> dict[str, Any]:
        all_items = [dict(item) for item in items if isinstance(item, dict)]
        baseline_items = [item for item in all_items if bool(item.get("baselineSnapshot"))]
        tombstone_items = [
            item for item in all_items
            if bool(item.get("deleted")) and not bool(item.get("baselineSnapshot"))
        ]
        item_list = [
            item for item in all_items
            if not bool(item.get("deleted")) and not bool(item.get("baselineSnapshot"))
        ]
        merged = 0
        changed_files = 0
        ai_updated = 0
        tags_added = 0
        artists_added = 0
        character_links_added = 0
        unresolved_characters = 0

        with self._lock:
            deletion_stats = self._apply_tombstones(tombstone_items)
            with get_connection() as baseline_connection:
                baseline_group_uuid = self._current_sync_group_uuid(baseline_connection)
            baselines_stored = self._store_metadata_baseline_controls(
                baseline_items, baseline_group_uuid
            )
            catalog = self._ensure_character_catalog(item_list)
            # create_franchise/create_character aggiornano già il DB; non rilanciare
            # qui lo scanner, perché le nuove cartelle possono essere ancora vuote
            # finché non vengono aggiunte le associazioni del media.
            with get_connection() as connection:
                sync_group_uuid = self._current_sync_group_uuid(connection)
                for item in item_list:
                    sha256 = str(item.get("sha256") or "").strip().lower()
                    if len(sha256) != 64:
                        continue
                    # Una tombstone ha precedenza sul merge additivo: non ricreare
                    # metadata su un media già dichiarato eliminato.
                    deleted = connection.execute(
                        """
                        SELECT 1 FROM sync_tombstones
                        WHERE sync_group_uuid = ? AND sha256 = ?
                        LIMIT 1
                        """,
                        (sync_group_uuid, sha256),
                    ).fetchone() if sync_group_uuid else None
                    if deleted is not None:
                        continue
                    file_row = connection.execute(
                        "SELECT id, ai_generated FROM files WHERE sha256 = ? AND is_trashed = 0 LIMIT 1",
                        (sha256,),
                    ).fetchone()
                    if file_row is None:
                        continue
                    file_id = int(file_row["id"])
                    changed = False

                    if bool(item.get("replaceMetadata")):
                        (
                            replaced, ai_delta, replace_tags, replace_artists,
                            replace_characters, replace_unresolved,
                        ) = self._replace_file_metadata(connection, file_id, file_row, item)
                        unresolved_characters += replace_unresolved
                        if replace_unresolved:
                            merged += 1
                            continue
                        if replaced:
                            changed_files += 1
                            ai_updated += ai_delta
                            tags_added += replace_tags
                            artists_added += replace_artists
                            character_links_added += replace_characters
                        merged += 1
                        continue

                    if bool(item.get("aiGenerated")) and not bool(file_row["ai_generated"]):
                        connection.execute("UPDATE files SET ai_generated = 1 WHERE id = ?", (file_id,))
                        ai_id, _, _ = ensure_tag(connection, "AI", "system")
                        cursor = connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, ai_id),
                        )
                        ai_updated += 1
                        changed = True
                        if cursor.rowcount > 0:
                            tags_added += 1

                    for tag in item.get("tags") or []:
                        name = " ".join(str(tag).split())
                        if not name or name.casefold() == "ai":
                            continue
                        tag_id, _, _ = ensure_tag(connection, name, "general")
                        cursor = connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, tag_id),
                        )
                        if cursor.rowcount > 0:
                            tags_added += 1
                            changed = True

                    for artist in item.get("artists") or []:
                        name = " ".join(str(artist).split())
                        if not name or name.casefold() == "ai":
                            continue
                        tag_id, _, _ = ensure_tag(connection, name, "artist")
                        cursor = connection.execute(
                            "INSERT OR IGNORE INTO file_tags(file_id, tag_id) VALUES (?, ?)",
                            (file_id, tag_id),
                        )
                        if cursor.rowcount > 0:
                            artists_added += 1
                            changed = True

                    for character in item.get("characters") or []:
                        if not isinstance(character, dict):
                            continue
                        character_id = self._find_character_id(connection, character)
                        if character_id is None:
                            unresolved_characters += 1
                            continue
                        cursor = connection.execute(
                            "INSERT OR IGNORE INTO file_characters(file_id, character_id) VALUES (?, ?)",
                            (file_id, character_id),
                        )
                        if cursor.rowcount > 0:
                            character_links_added += 1
                            changed = True

                    if changed:
                        changed_files += 1
                    merged += 1

        return {
            "merged": merged,
            "changedFiles": changed_files,
            "aiUpdated": ai_updated,
            "tagsAdded": tags_added,
            "artistsAdded": artists_added,
            "characterLinksAdded": character_links_added,
            "createdFranchises": int(catalog["createdFranchises"]),
            "createdCharacters": int(catalog["createdCharacters"]),
            "unresolvedCharacters": unresolved_characters + int(catalog["unresolvedCatalogCharacters"]),
            "baselinesStored": baselines_stored,
            **deletion_stats,
        }

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
        # Un arresto forzato di Windows può lasciare un .part senza che FastAPI
        # abbia il tempo di eseguire il cleanup dell'eccezione. Elimina soltanto
        # temporanei M7 vecchi, così non interferiamo con upload contemporanei.
        cutoff = time.time() - (12 * 60 * 60)
        for candidate in directory.glob("m7_*.part"):
            try:
                if candidate.stat().st_mtime < cutoff:
                    candidate.unlink(missing_ok=True)
            except OSError:
                pass
        handle, name = tempfile.mkstemp(prefix="m7_", suffix=".part", dir=directory)
        os.close(handle)
        return Path(name)


MOBILE_SYNC_SERVICE = MobileSyncService()
