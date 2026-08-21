from __future__ import annotations

import hashlib
import json
from typing import Any

from fastapi import HTTPException
from pydantic import BaseModel, Field

import main as core
from backend.database import get_connection


app = core.app


class _CharacterScoreItem(BaseModel):
    franchiseName: str = Field(min_length=1, max_length=160)
    characterName: str = Field(min_length=1, max_length=160)
    sessionId: str = Field(min_length=1, max_length=160)
    pendingDelta: int = Field(ge=-100_000, le=100_000)


class _CharacterScoreSyncRequest(core._M7SyncRequest):
    items: list[_CharacterScoreItem] = Field(default_factory=list, max_length=500)


def _score_state_key(
    sync_group_uuid: str,
    android_gallery_uuid: str,
    franchise_name: str,
    character_name: str,
) -> str:
    identity = "\x1f".join(
        (
            sync_group_uuid.strip(),
            android_gallery_uuid.strip(),
            franchise_name.strip().casefold(),
            character_name.strip().casefold(),
        )
    )
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()
    return f"android_character_score:{digest}"


def _read_score_state(connection, key: str) -> dict[str, Any] | None:
    row = connection.execute(
        "SELECT value FROM sync_state WHERE key = ? LIMIT 1",
        (key,),
    ).fetchone()
    if row is None:
        return None
    try:
        value = json.loads(str(row["value"]))
    except (TypeError, ValueError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _write_score_state(connection, key: str, value: dict[str, Any]) -> None:
    connection.execute(
        """
        INSERT INTO sync_state(key, value, updated_at)
        VALUES (?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = CURRENT_TIMESTAMP
        """,
        (key, json.dumps(value, ensure_ascii=False, separators=(",", ":"))),
    )


def _character_row(connection, franchise_name: str, character_name: str):
    return connection.execute(
        """
        SELECT characters.id, characters.score
        FROM characters
        JOIN franchises ON franchises.id = characters.franchise_id
        WHERE characters.is_active = 1
          AND franchises.is_active = 1
          AND franchises.name = ? COLLATE NOCASE
          AND characters.name = ? COLLATE NOCASE
        LIMIT 1
        """,
        (franchise_name, character_name),
    ).fetchone()


def _score_catalog(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        SELECT
            franchises.name AS franchise_name,
            characters.name AS character_name,
            characters.score
        FROM characters
        JOIN franchises ON franchises.id = characters.franchise_id
        WHERE characters.is_active = 1
          AND franchises.is_active = 1
        ORDER BY characters.name COLLATE NOCASE,
                 franchises.name COLLATE NOCASE
        """
    ).fetchall()
    return [
        {
            "franchiseName": str(row["franchise_name"]),
            "characterName": str(row["character_name"]),
            "score": max(0, int(row["score"])),
        }
        for row in rows
    ]


@app.post("/api/mobile/sync/character-scores")
def _m9_character_scores(request: _CharacterScoreSyncRequest):
    core._m7_authorize(request.device_id, request.token, touch=True)
    core._m7_require_link(request.sync_group_uuid, request.windows_gallery_uuid)

    applied: list[dict[str, Any]] = []
    unresolved: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()

    try:
        with get_connection() as connection:
            for item in request.items:
                franchise_name = item.franchiseName.strip()
                character_name = item.characterName.strip()
                identity = (franchise_name.casefold(), character_name.casefold())
                if identity in seen:
                    raise ValueError(
                        f"Punteggio duplicato nella richiesta: {franchise_name} / {character_name}."
                    )
                seen.add(identity)

                row = _character_row(connection, franchise_name, character_name)
                if row is None:
                    unresolved.append(
                        {
                            "franchiseName": franchise_name,
                            "characterName": character_name,
                        }
                    )
                    continue

                current_score = max(0, int(row["score"]))
                state_key = _score_state_key(
                    request.sync_group_uuid,
                    request.android_gallery_uuid,
                    franchise_name,
                    character_name,
                )
                previous = _read_score_state(connection, state_key)
                if previous and str(previous.get("sessionId", "")) == item.sessionId:
                    previous_base = int(previous.get("baseScore", current_score))
                    previous_result = int(previous.get("resultScore", current_score))
                    external_delta = current_score - previous_result
                    base_score = previous_base + external_delta
                else:
                    base_score = current_score

                result_score = max(0, base_score + item.pendingDelta)
                connection.execute(
                    "UPDATE characters SET score = ? WHERE id = ?",
                    (result_score, int(row["id"])),
                )
                _write_score_state(
                    connection,
                    state_key,
                    {
                        "sessionId": item.sessionId,
                        "baseScore": base_score,
                        "resultScore": result_score,
                        "pendingDelta": item.pendingDelta,
                    },
                )
                applied.append(
                    {
                        "franchiseName": franchise_name,
                        "characterName": character_name,
                        "sessionId": item.sessionId,
                        "pendingDelta": item.pendingDelta,
                        "score": result_score,
                    }
                )

            scores = _score_catalog(connection)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=f"Sincronizzazione classifica non riuscita: {error}",
        ) from error

    return {
        "applied": applied,
        "scores": scores,
        "unresolved": len(unresolved),
        "unresolvedItems": unresolved,
    }
