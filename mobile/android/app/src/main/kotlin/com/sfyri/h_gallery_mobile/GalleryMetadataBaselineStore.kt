package com.sfyri.h_gallery_mobile

import android.content.ContentValues
import android.content.Context
import org.json.JSONObject
import java.util.Locale

/**
 * M7.6 metadata baseline.
 *
 * A removal is propagated only when both peers share the same previous verified
 * snapshot. Without a common baseline the resolver is deliberately additive,
 * so missing metadata can never be interpreted as a deletion by accident.
 */
internal data class SyncMetadataTag(
    val name: String,
    val type: String,
)

internal data class SyncMetadataCharacter(
    val name: String,
    val franchiseName: String,
    val relativePath: String = "",
    val franchiseCode: String = "",
    val franchiseRelativePath: String = "",
) {
    fun asMap(): Map<String, String> = mapOf(
        "name" to name,
        "franchiseName" to franchiseName,
        "relativePath" to relativePath,
        "franchiseCode" to franchiseCode,
        "franchiseRelativePath" to franchiseRelativePath,
    )
}

internal data class SyncMetadataSnapshot(
    val tags: Map<String, SyncMetadataTag>,
    val characters: Map<String, SyncMetadataCharacter>,
    val aiGenerated: Boolean,
) {
    /**
     * Confronta solo lo stato sincronizzabile, non i dettagli di percorso usati
     * per ricreare un personaggio. Due peer possono rappresentare lo stesso
     * personaggio in cartelle diverse senza avere metadata logicamente diversi.
     */
    fun sameState(other: SyncMetadataSnapshot): Boolean =
        aiGenerated == other.aiGenerated &&
            tags.mapValues { it.value.type } == other.tags.mapValues { it.value.type } &&
            characters.keys == other.characters.keys

    fun toJson(): JSONObject = JSONObject().apply {
        put("version", 1)
        put("aiGenerated", aiGenerated)
        put("tags", JSONObject().apply {
            tags.toSortedMap().forEach { (key, tag) ->
                put(key, JSONObject().apply {
                    put("name", tag.name)
                    put("type", tag.type)
                })
            }
        })
        put("characters", JSONObject().apply {
            characters.toSortedMap().forEach { (key, character) ->
                put(key, JSONObject(character.asMap()))
            }
        })
    }

    companion object {
        fun fromJson(value: JSONObject?): SyncMetadataSnapshot? {
            value ?: return null
            val tagsObject = value.optJSONObject("tags") ?: return null
            val charactersObject = value.optJSONObject("characters") ?: return null
            val tags = linkedMapOf<String, SyncMetadataTag>()
            val tagKeys = tagsObject.keys()
            while (tagKeys.hasNext()) {
                val rawKey = tagKeys.next()
                val item = tagsObject.optJSONObject(rawKey) ?: continue
                val type = item.optString("type").trim().lowercase(Locale.ROOT)
                if (type !in setOf("general", "artist")) continue
                val name = normalizeMetadataText(item.optString("name", rawKey))
                val key = normalizeMetadataKey(rawKey)
                if (name.isBlank() || key.isBlank() || name.equals("AI", true)) continue
                tags[key] = SyncMetadataTag(name = name, type = type)
            }
            val characters = linkedMapOf<String, SyncMetadataCharacter>()
            val characterKeys = charactersObject.keys()
            while (characterKeys.hasNext()) {
                val rawKey = characterKeys.next()
                val item = charactersObject.optJSONObject(rawKey) ?: continue
                val name = normalizeMetadataText(item.optString("name"))
                val franchise = normalizeMetadataText(item.optString("franchiseName"))
                if (name.isBlank() || franchise.isBlank()) continue
                val key = characterMetadataKey(franchise, name)
                characters[key] = SyncMetadataCharacter(
                    name = name,
                    franchiseName = franchise,
                    relativePath = item.optString("relativePath").trim(),
                    franchiseCode = item.optString("franchiseCode").trim(),
                    franchiseRelativePath = item.optString("franchiseRelativePath").trim(),
                )
            }
            return SyncMetadataSnapshot(
                tags = tags,
                characters = characters,
                aiGenerated = value.optBoolean("aiGenerated", false),
            )
        }
    }
}

internal data class SyncMetadataResolution(
    val snapshot: SyncMetadataSnapshot,
    val baselineReady: Boolean,
    val conflicts: List<String> = emptyList(),
)

internal fun normalizeMetadataText(value: String): String =
    value.trim().split(Regex("\\s+")).filter(String::isNotBlank).joinToString(" ")

internal fun normalizeMetadataKey(value: String): String =
    normalizeMetadataText(value).lowercase(Locale.ROOT)

internal fun characterMetadataKey(franchise: String, name: String): String =
    "${normalizeMetadataKey(franchise)}\u0000${normalizeMetadataKey(name)}"

internal object SyncMetadataResolver {
    fun fromValues(
        tags: List<String>,
        artists: List<String>,
        characters: List<Map<String, String>>,
        aiGenerated: Boolean,
    ): SyncMetadataSnapshot {
        val typed = linkedMapOf<String, SyncMetadataTag>()
        for (raw in tags) {
            val name = normalizeMetadataText(raw)
            val key = normalizeMetadataKey(name)
            if (key.isBlank() || name.equals("AI", true)) continue
            typed.putIfAbsent(key, SyncMetadataTag(name, "general"))
        }
        for (raw in artists) {
            val name = normalizeMetadataText(raw)
            val key = normalizeMetadataKey(name)
            if (key.isBlank() || name.equals("AI", true)) continue
            typed[key] = SyncMetadataTag(name, "artist")
        }
        val characterValues = linkedMapOf<String, SyncMetadataCharacter>()
        for (value in characters) {
            val name = normalizeMetadataText(value["name"].orEmpty())
            val franchise = normalizeMetadataText(value["franchiseName"].orEmpty())
            if (name.isBlank() || franchise.isBlank()) continue
            val key = characterMetadataKey(franchise, name)
            characterValues[key] = SyncMetadataCharacter(
                name = name,
                franchiseName = franchise,
                relativePath = value["relativePath"].orEmpty(),
                franchiseCode = value["franchiseCode"].orEmpty(),
                franchiseRelativePath = value["franchiseRelativePath"].orEmpty(),
            )
        }
        return SyncMetadataSnapshot(typed, characterValues, aiGenerated)
    }

    fun resolve(
        local: SyncMetadataSnapshot,
        remote: SyncMetadataSnapshot,
        localBaseline: SyncMetadataSnapshot?,
        remoteBaseline: SyncMetadataSnapshot?,
    ): SyncMetadataResolution {
        val baselineReady = localBaseline != null && remoteBaseline != null && localBaseline.sameState(remoteBaseline)
        if (!baselineReady) {
            return SyncMetadataResolution(additive(local, remote), baselineReady = false)
        }
        val baseline = localBaseline!!
        val conflicts = mutableListOf<String>()
        val tags = linkedMapOf<String, SyncMetadataTag>()
        val allTagKeys = (baseline.tags.keys + local.tags.keys + remote.tags.keys).toSortedSet()
        for (key in allTagKeys) {
            val baseState = baseline.tags[key]?.type
            val localState = local.tags[key]?.type
            val remoteState = remote.tags[key]?.type
            val finalState = resolveState(baseState, localState, remoteState)
            if (finalState.conflict) {
                val label = remote.tags[key]?.name ?: local.tags[key]?.name ?: baseline.tags[key]?.name ?: key
                conflicts += "Modifiche concorrenti sul metadata '$label'."
                continue
            }
            val state = finalState.value ?: continue
            // Il tipo del tag è globale nell'attuale schema Android/Windows.
            // Una demozione Artista -> Tag generale su un solo peer potrebbe
            // quindi alterare anche altri media. M7.6 non la deduce mai:
            // richiede una risoluzione manuale invece di fare una modifica
            // potenzialmente distruttiva.
            if (
                state == "general" &&
                (baseState == "artist" || localState == "artist" || remoteState == "artist") &&
                !(localState == "general" && remoteState == "general")
            ) {
                val label = remote.tags[key]?.name ?: local.tags[key]?.name ?: baseline.tags[key]?.name ?: key
                conflicts += "Demozione Artista → Tag generale su '$label': risoluzione manuale richiesta."
                continue
            }
            val display = when (state) {
                localState -> local.tags[key]?.name
                remoteState -> remote.tags[key]?.name
                else -> null
            } ?: local.tags[key]?.name ?: remote.tags[key]?.name ?: baseline.tags[key]?.name ?: key
            tags[key] = SyncMetadataTag(display, state)
        }

        val characters = linkedMapOf<String, SyncMetadataCharacter>()
        val allCharacterKeys = (baseline.characters.keys + local.characters.keys + remote.characters.keys).toSortedSet()
        for (key in allCharacterKeys) {
            val baseState = key in baseline.characters
            val localState = key in local.characters
            val remoteState = key in remote.characters
            val resolved = resolveBoolean(baseState, localState, remoteState)
            if (resolved.conflict) {
                val label = remote.characters[key] ?: local.characters[key] ?: baseline.characters[key]
                conflicts += "Modifiche concorrenti sul personaggio '${label?.franchiseName} · ${label?.name}'."
                continue
            }
            if (resolved.value == true) {
                characters[key] = local.characters[key] ?: remote.characters[key] ?: baseline.characters.getValue(key)
            }
        }

        val ai = resolveBoolean(baseline.aiGenerated, local.aiGenerated, remote.aiGenerated)
        if (ai.conflict) conflicts += "Modifiche concorrenti sul flag Contenuto IA."
        return SyncMetadataResolution(
            snapshot = SyncMetadataSnapshot(tags, characters, ai.value ?: (local.aiGenerated || remote.aiGenerated)),
            baselineReady = true,
            conflicts = conflicts,
        )
    }

    private data class StateResult<T>(val value: T?, val conflict: Boolean = false)

    private fun <T> resolveState(base: T?, local: T?, remote: T?): StateResult<T> {
        if (local == remote) return StateResult(local)
        val localChanged = local != base
        val remoteChanged = remote != base
        return when {
            localChanged && !remoteChanged -> StateResult(local)
            !localChanged && remoteChanged -> StateResult(remote)
            localChanged && remoteChanged -> StateResult(null, conflict = true)
            else -> StateResult(local)
        }
    }

    private fun resolveBoolean(base: Boolean, local: Boolean, remote: Boolean): StateResult<Boolean> =
        resolveState(base, local, remote)

    private fun additive(local: SyncMetadataSnapshot, remote: SyncMetadataSnapshot): SyncMetadataSnapshot {
        val tags = linkedMapOf<String, SyncMetadataTag>()
        for (key in (local.tags.keys + remote.tags.keys).toSortedSet()) {
            val left = local.tags[key]
            val right = remote.tags[key]
            val chosen = when {
                left?.type == "artist" -> left
                right?.type == "artist" -> right
                left != null -> left
                else -> right
            }
            if (chosen != null) tags[key] = chosen
        }
        val characters = linkedMapOf<String, SyncMetadataCharacter>()
        for (key in (local.characters.keys + remote.characters.keys).toSortedSet()) {
            characters[key] = local.characters[key] ?: remote.characters.getValue(key)
        }
        return SyncMetadataSnapshot(
            tags = tags,
            characters = characters,
            aiGenerated = local.aiGenerated || remote.aiGenerated,
        )
    }
}

internal class GalleryMetadataBaselineStore(
    private val context: Context,
) {
    fun read(
        galleryUuid: String,
        syncGroupUuid: String,
        peerGalleryUuid: String,
    ): Map<String, SyncMetadataSnapshot> {
        if (syncGroupUuid.isBlank() || peerGalleryUuid.isBlank()) return emptyMap()
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val db = database.readableDatabase
            val result = linkedMapOf<String, SyncMetadataSnapshot>()
            db.rawQuery(
                """
                SELECT media_sha256, snapshot_json
                FROM sync_metadata_baselines
                WHERE sync_group_uuid = ? AND peer_gallery_uuid = ?
                ORDER BY media_sha256
                """.trimIndent(),
                arrayOf(syncGroupUuid, peerGalleryUuid),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val sha = cursor.getString(0).orEmpty().lowercase(Locale.ROOT)
                    val snapshot = try {
                        SyncMetadataSnapshot.fromJson(JSONObject(cursor.getString(1)))
                    } catch (_: Exception) {
                        null
                    }
                    if (sha.length == 64 && snapshot != null) result[sha] = snapshot
                }
            }
            return result
        } finally {
            database.close()
        }
    }

    fun replace(
        galleryUuid: String,
        syncGroupUuid: String,
        peerGalleryUuid: String,
        values: Map<String, SyncMetadataSnapshot>,
    ) {
        require(syncGroupUuid.isNotBlank()) { "Gruppo di sincronizzazione non valido." }
        require(peerGalleryUuid.isNotBlank()) { "Peer di sincronizzazione non valido." }
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val db = database.writableDatabase
            val now = System.currentTimeMillis()
            db.beginTransaction()
            try {
                db.delete(
                    "sync_metadata_baselines",
                    "sync_group_uuid = ? AND peer_gallery_uuid = ?",
                    arrayOf(syncGroupUuid, peerGalleryUuid),
                )
                values.toSortedMap().forEach { (sha, snapshot) ->
                    if (sha.length != 64) return@forEach
                    val row = ContentValues().apply {
                        put("sync_group_uuid", syncGroupUuid)
                        put("peer_gallery_uuid", peerGalleryUuid)
                        put("media_sha256", sha.lowercase(Locale.ROOT))
                        put("snapshot_json", snapshot.toJson().toString())
                        put("updated_at_epoch_ms", now)
                    }
                    db.insertOrThrow("sync_metadata_baselines", null, row)
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }
    }
}
