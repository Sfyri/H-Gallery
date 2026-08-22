package com.sfyri.h_gallery_mobile

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.util.Locale
import java.util.UUID

/**
 * M7.4.1: metadata editor for media that are already part of an Android gallery.
 *
 * Editing metadata does not move or rename the physical media file. The database
 * becomes the explicit source of truth after the first edit by setting
 * metadata_updated_epoch_ms > 0. This is important for legacy galleries where
 * character/AI metadata could previously be inferred from the folder path.
 */
internal class GalleryMediaMetadataEditor(
    private val context: Context,
) {
    private companion object {
        const val MODE_KEEP = "keep"
        const val MODE_ADD = "add"
        const val MODE_REMOVE = "remove"
        const val MODE_REPLACE = "replace"
        val LIST_MODES = setOf(MODE_KEEP, MODE_ADD, MODE_REMOVE, MODE_REPLACE)

        const val AI_KEEP = "keep"
        const val AI_ENABLE = "enable"
        const val AI_DISABLE = "disable"
        val AI_MODES = setOf(AI_KEEP, AI_ENABLE, AI_DISABLE)
    }
    fun read(galleryUuid: String, syncUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val db = database.readableDatabase
            var relativePath = ""
            var aiGenerated = false
            var metadataUpdatedEpochMs = 0L
            db.rawQuery(
                """
                SELECT relative_path, ai_generated, metadata_updated_epoch_ms
                FROM media
                WHERE sync_uuid = ? AND is_present = 1
                LIMIT 1
                """.trimIndent(),
                arrayOf(syncUuid),
            ).use { cursor ->
                if (!cursor.moveToFirst()) {
                    throw IllegalArgumentException("Media non trovato nella galleria.")
                }
                relativePath = cursor.getString(0)
                aiGenerated = cursor.getInt(1) != 0
                metadataUpdatedEpochMs = cursor.getLong(2)
            }

            val explicit = metadataUpdatedEpochMs > 0L
            val characterIds = mutableListOf<Long>()
            val characters = mutableListOf<Map<String, Any>>()
            db.rawQuery(
                """
                SELECT c.id, c.name, f.name
                FROM media_characters mc
                JOIN characters c ON c.id = mc.character_id
                JOIN franchises f ON f.id = c.franchise_id
                WHERE mc.media_sync_uuid = ?
                ORDER BY f.name COLLATE NOCASE, c.name COLLATE NOCASE
                """.trimIndent(),
                arrayOf(syncUuid),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    characterIds += id
                    characters += mapOf<String, Any>(
                        "id" to id,
                        "name" to cursor.getString(1),
                        "franchiseName" to cursor.getString(2),
                        "label" to "${cursor.getString(2)} · ${cursor.getString(1)}",
                    )
                }
            }

            // Before the first explicit edit, preserve the legacy path-derived
            // character behavior when the corresponding catalog entry exists.
            if (!explicit && characterIds.isEmpty()) {
                inferCharacter(db, relativePath)?.let { inferred ->
                    characterIds += inferred.first
                    characters += inferred.second
                }
            }

            val tags = mutableListOf<String>()
            val artists = mutableListOf<String>()
            db.rawQuery(
                """
                SELECT t.name, t.type
                FROM media_tags mt
                JOIN tags t ON t.id = mt.tag_id
                WHERE mt.media_sync_uuid = ?
                ORDER BY t.name COLLATE NOCASE
                """.trimIndent(),
                arrayOf(syncUuid),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0)
                    when (cursor.getString(1)) {
                        "artist" -> artists += name
                        "general" -> if (!name.equals("AI", ignoreCase = true)) tags += name
                    }
                }
            }

            if (!explicit && relativePath.split('/').any { it.equals(".AI", ignoreCase = true) }) {
                aiGenerated = true
            }

            return mapOf(
                "syncUuid" to syncUuid,
                "relativePath" to relativePath,
                "metadataExplicit" to explicit,
                "characterIds" to characterIds,
                "characters" to characters,
                "tags" to tags,
                "artists" to artists,
                "aiGenerated" to aiGenerated,
            )
        } finally {
            database.close()
        }
    }

    fun update(
        galleryUuid: String,
        syncUuid: String,
        characterIds: List<Long>,
        tags: List<String>,
        artists: List<String>,
        aiGenerated: Boolean,
    ): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val db = database.writableDatabase
            val now = System.currentTimeMillis()
            var relativePath = ""
            db.rawQuery(
                "SELECT relative_path FROM media WHERE sync_uuid = ? AND is_present = 1 LIMIT 1",
                arrayOf(syncUuid),
            ).use { cursor ->
                if (!cursor.moveToFirst()) {
                    throw IllegalArgumentException("Media non trovato nella galleria.")
                }
                relativePath = cursor.getString(0)
            }

            val validCharacterIds = characterIds.distinct().filter { id ->
                db.rawQuery(
                    "SELECT 1 FROM characters WHERE id = ? AND is_active = 1 LIMIT 1",
                    arrayOf(id.toString()),
                ).use { it.moveToFirst() }
            }
            if (validCharacterIds.size != characterIds.distinct().size) {
                throw IllegalArgumentException("Uno o più personaggi selezionati non sono più disponibili.")
            }

            val cleanedTags = normalizeNames(tags)
            val cleanedArtists = normalizeNames(artists)
            val artistKeys = cleanedArtists.associateBy { key(it) }
            val finalTags = cleanedTags.filter { key(it) !in artistKeys.keys && !it.equals("AI", true) }
            val finalArtists = cleanedArtists.filterNot { it.equals("AI", true) }

            db.beginTransaction()
            try {
                db.delete("media_characters", "media_sync_uuid = ?", arrayOf(syncUuid))
                db.delete("media_tags", "media_sync_uuid = ?", arrayOf(syncUuid))

                for (characterId in validCharacterIds) {
                    val values = ContentValues().apply {
                        put("media_sync_uuid", syncUuid)
                        put("character_id", characterId)
                    }
                    db.insertWithOnConflict(
                        "media_characters",
                        null,
                        values,
                        SQLiteDatabase.CONFLICT_IGNORE,
                    )
                }

                for (tag in finalTags) {
                    val tagId = ensureTag(db, tag, "general", now)
                    insertMediaTag(db, syncUuid, tagId)
                }
                for (artist in finalArtists) {
                    val tagId = ensureTag(db, artist, "artist", now)
                    insertMediaTag(db, syncUuid, tagId)
                }
                if (aiGenerated) {
                    val tagId = ensureTag(db, "AI", "system", now)
                    insertMediaTag(db, syncUuid, tagId)
                }

                val mediaValues = ContentValues().apply {
                    put("ai_generated", if (aiGenerated) 1 else 0)
                    put("metadata_updated_epoch_ms", now)
                    put("updated_at_epoch_ms", now)
                }
                db.update("media", mediaValues, "sync_uuid = ?", arrayOf(syncUuid))

                val operation = ContentValues().apply {
                    put("operation_type", "metadata_edit")
                    put("source_relative_path", relativePath)
                    put("destination_relative_path", relativePath)
                    put("created_at_epoch_ms", now)
                }
                db.insert("operations", null, operation)
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }
        return read(galleryUuid, syncUuid)
    }

    fun updateBatch(
        galleryUuid: String,
        syncUuids: List<String>,
        characterMode: String,
        characterIds: List<Long>,
        tagMode: String,
        tags: List<String>,
        artistMode: String,
        artists: List<String>,
        aiMode: String,
    ): Map<String, Any> {
        val mediaIds = syncUuids
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
        if (mediaIds.isEmpty()) {
            throw IllegalArgumentException("Seleziona almeno un media.")
        }

        val finalCharacterMode = validateListMode(characterMode, "personaggi")
        val finalTagMode = validateListMode(tagMode, "tag")
        val finalArtistMode = validateListMode(artistMode, "artisti")
        val finalAiMode = validateAiMode(aiMode)
        if (finalCharacterMode == MODE_KEEP &&
            finalTagMode == MODE_KEEP &&
            finalArtistMode == MODE_KEEP &&
            finalAiMode == AI_KEEP
        ) {
            throw IllegalArgumentException("Non è stata selezionata alcuna modifica.")
        }

        val requestedCharacterIds = characterIds.distinct()
        val requestedTags = normalizeNames(tags).filterNot { it.equals("AI", ignoreCase = true) }
        val requestedArtists = normalizeNames(artists).filterNot { it.equals("AI", ignoreCase = true) }
        if (finalCharacterMode in setOf(MODE_ADD, MODE_REMOVE) && requestedCharacterIds.isEmpty()) {
            throw IllegalArgumentException("Seleziona almeno un personaggio da modificare.")
        }
        if (finalTagMode in setOf(MODE_ADD, MODE_REMOVE) && requestedTags.isEmpty()) {
            throw IllegalArgumentException("Inserisci almeno un tag da modificare.")
        }
        if (finalArtistMode in setOf(MODE_ADD, MODE_REMOVE) && requestedArtists.isEmpty()) {
            throw IllegalArgumentException("Inserisci almeno un artista da modificare.")
        }

        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val db = database.writableDatabase
            val now = System.currentTimeMillis()
            db.beginTransaction()
            try {
                if (finalCharacterMode != MODE_KEEP) {
                    val validCharacterIds = requestedCharacterIds.filter { id ->
                        db.rawQuery(
                            "SELECT 1 FROM characters WHERE id = ? AND is_active = 1 LIMIT 1",
                            arrayOf(id.toString()),
                        ).use { it.moveToFirst() }
                    }
                    if (validCharacterIds.size != requestedCharacterIds.size) {
                        throw IllegalArgumentException(
                            "Uno o più personaggi selezionati non sono più disponibili.",
                        )
                    }
                }

                for (syncUuid in mediaIds) {
                    val current = readEffectiveState(db, syncUuid)
                    val nextCharacterIds = applyLongMode(
                        current.characterIds,
                        requestedCharacterIds,
                        finalCharacterMode,
                    )
                    val nextTags = applyNameMode(current.tags, requestedTags, finalTagMode)
                    val nextArtists = applyNameMode(current.artists, requestedArtists, finalArtistMode)
                    val artistKeys = nextArtists.associateBy { key(it) }
                    val sanitizedTags = nextTags.filter {
                        key(it) !in artistKeys.keys && !it.equals("AI", ignoreCase = true)
                    }
                    val sanitizedArtists = nextArtists.filterNot { it.equals("AI", ignoreCase = true) }
                    val nextAiGenerated = when (finalAiMode) {
                        AI_ENABLE -> true
                        AI_DISABLE -> false
                        else -> current.aiGenerated
                    }

                    writeMetadata(
                        db = db,
                        syncUuid = syncUuid,
                        relativePath = current.relativePath,
                        characterIds = nextCharacterIds,
                        tags = sanitizedTags,
                        artists = sanitizedArtists,
                        aiGenerated = nextAiGenerated,
                        now = now,
                    )
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }

        return mapOf(
            "requestedCount" to mediaIds.size,
            "updatedCount" to mediaIds.size,
        )
    }

    private data class EffectiveMetadataState(
        val relativePath: String,
        val characterIds: List<Long>,
        val tags: List<String>,
        val artists: List<String>,
        val aiGenerated: Boolean,
    )

    private fun readEffectiveState(
        db: SQLiteDatabase,
        syncUuid: String,
    ): EffectiveMetadataState {
        var relativePath = ""
        var aiGenerated = false
        var metadataUpdatedEpochMs = 0L
        db.rawQuery(
            """
            SELECT relative_path, ai_generated, metadata_updated_epoch_ms
            FROM media
            WHERE sync_uuid = ? AND is_present = 1
            LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) {
                throw IllegalArgumentException("Uno dei media selezionati non è più disponibile.")
            }
            relativePath = cursor.getString(0)
            aiGenerated = cursor.getInt(1) != 0
            metadataUpdatedEpochMs = cursor.getLong(2)
        }

        val explicit = metadataUpdatedEpochMs > 0L
        val characterIds = mutableListOf<Long>()
        db.rawQuery(
            """
            SELECT c.id
            FROM media_characters mc
            JOIN characters c ON c.id = mc.character_id
            WHERE mc.media_sync_uuid = ? AND c.is_active = 1
            ORDER BY c.id
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) characterIds += cursor.getLong(0)
        }
        if (!explicit && characterIds.isEmpty()) {
            inferCharacter(db, relativePath)?.let { characterIds += it.first }
        }

        val tags = mutableListOf<String>()
        val artists = mutableListOf<String>()
        db.rawQuery(
            """
            SELECT t.name, t.type
            FROM media_tags mt
            JOIN tags t ON t.id = mt.tag_id
            WHERE mt.media_sync_uuid = ?
            ORDER BY t.name COLLATE NOCASE
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(0)
                when (cursor.getString(1)) {
                    "artist" -> artists += name
                    "general" -> if (!name.equals("AI", ignoreCase = true)) tags += name
                }
            }
        }
        if (!explicit && relativePath.split('/').any { it.equals(".AI", ignoreCase = true) }) {
            aiGenerated = true
        }

        return EffectiveMetadataState(
            relativePath = relativePath,
            characterIds = characterIds.distinct(),
            tags = normalizeNames(tags),
            artists = normalizeNames(artists),
            aiGenerated = aiGenerated,
        )
    }

    private fun writeMetadata(
        db: SQLiteDatabase,
        syncUuid: String,
        relativePath: String,
        characterIds: List<Long>,
        tags: List<String>,
        artists: List<String>,
        aiGenerated: Boolean,
        now: Long,
    ) {
        db.delete("media_characters", "media_sync_uuid = ?", arrayOf(syncUuid))
        db.delete("media_tags", "media_sync_uuid = ?", arrayOf(syncUuid))

        for (characterId in characterIds.distinct()) {
            val values = ContentValues().apply {
                put("media_sync_uuid", syncUuid)
                put("character_id", characterId)
            }
            db.insertWithOnConflict(
                "media_characters",
                null,
                values,
                SQLiteDatabase.CONFLICT_IGNORE,
            )
        }
        for (tag in normalizeNames(tags)) {
            val tagId = ensureTag(db, tag, "general", now)
            insertMediaTag(db, syncUuid, tagId)
        }
        for (artist in normalizeNames(artists)) {
            val tagId = ensureTag(db, artist, "artist", now)
            insertMediaTag(db, syncUuid, tagId)
        }
        if (aiGenerated) {
            val tagId = ensureTag(db, "AI", "system", now)
            insertMediaTag(db, syncUuid, tagId)
        }

        val mediaValues = ContentValues().apply {
            put("ai_generated", if (aiGenerated) 1 else 0)
            put("metadata_updated_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        val changed = db.update("media", mediaValues, "sync_uuid = ?", arrayOf(syncUuid))
        if (changed != 1) {
            throw IllegalStateException("Impossibile aggiornare uno dei media selezionati.")
        }

        val operation = ContentValues().apply {
            put("operation_type", "metadata_edit")
            put("source_relative_path", relativePath)
            put("destination_relative_path", relativePath)
            put("created_at_epoch_ms", now)
        }
        db.insert("operations", null, operation)
    }

    private fun applyLongMode(
        current: List<Long>,
        requested: List<Long>,
        mode: String,
    ): List<Long> {
        val result = LinkedHashSet<Long>()
        when (mode) {
            MODE_KEEP -> result.addAll(current)
            MODE_ADD -> {
                result.addAll(current)
                result.addAll(requested)
            }
            MODE_REMOVE -> {
                result.addAll(current)
                result.removeAll(requested.toSet())
            }
            MODE_REPLACE -> result.addAll(requested)
        }
        return result.toList()
    }

    private fun applyNameMode(
        current: List<String>,
        requested: List<String>,
        mode: String,
    ): List<String> {
        val currentValues = normalizeNames(current)
        val requestedValues = normalizeNames(requested)
        return when (mode) {
            MODE_KEEP -> currentValues
            MODE_ADD -> normalizeNames(currentValues + requestedValues)
            MODE_REMOVE -> {
                val removedKeys = requestedValues.map(::key).toSet()
                currentValues.filter { key(it) !in removedKeys }
            }
            MODE_REPLACE -> requestedValues
            else -> currentValues
        }
    }

    private fun validateListMode(value: String, label: String): String {
        val mode = value.trim().lowercase(Locale.ROOT)
        if (mode !in LIST_MODES) {
            throw IllegalArgumentException("Modalità di modifica $label non valida.")
        }
        return mode
    }

    private fun validateAiMode(value: String): String {
        val mode = value.trim().lowercase(Locale.ROOT)
        if (mode !in AI_MODES) {
            throw IllegalArgumentException("Modalità IA non valida.")
        }
        return mode
    }

    private fun inferCharacter(
        db: SQLiteDatabase,
        relativePath: String,
    ): Pair<Long, Map<String, Any>>? {
        val segments = relativePath.split('/').filter { it.isNotBlank() }
        if (segments.size < 3) return null
        val franchise = segments[0]
        val character = segments[1]
        if (franchise.startsWith('!') || franchise.startsWith('.') ||
            character.startsWith('!') || character.startsWith('.')
        ) {
            return null
        }
        db.rawQuery(
            """
            SELECT c.id, c.name, f.name
            FROM characters c
            JOIN franchises f ON f.id = c.franchise_id
            WHERE c.is_active = 1 AND f.is_active = 1
              AND (f.relative_path = ? COLLATE NOCASE OR f.name = ? COLLATE NOCASE)
              AND (c.name = ? COLLATE NOCASE OR c.relative_path = ? COLLATE NOCASE)
            LIMIT 1
            """.trimIndent(),
            arrayOf(franchise, franchise, character, "$franchise/$character"),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getLong(0)
            val characterName = cursor.getString(1)
            val franchiseName = cursor.getString(2)
            return id to mapOf(
                "id" to id,
                "name" to characterName,
                "franchiseName" to franchiseName,
                "label" to "$franchiseName · $characterName",
            )
        }
    }

    private fun ensureTag(
        db: SQLiteDatabase,
        name: String,
        requestedType: String,
        now: Long,
    ): Long {
        db.rawQuery(
            "SELECT id, type FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(name),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val currentType = cursor.getString(1)
                val finalType = when {
                    name.equals("AI", ignoreCase = true) -> "system"
                    currentType == "general" && requestedType in setOf("artist", "system") -> requestedType
                    else -> currentType
                }
                if (finalType != currentType) {
                    val values = ContentValues().apply {
                        put("type", finalType)
                        put("updated_at_epoch_ms", now)
                    }
                    db.update("tags", values, "id = ?", arrayOf(id.toString()))
                }
                return id
            }
        }
        val type = if (name.equals("AI", ignoreCase = true)) "system" else requestedType
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString())
            put("name", name)
            put("type", type)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        return db.insertOrThrow("tags", null, values)
    }

    private fun insertMediaTag(db: SQLiteDatabase, mediaSyncUuid: String, tagId: Long) {
        val values = ContentValues().apply {
            put("media_sync_uuid", mediaSyncUuid)
            put("tag_id", tagId)
        }
        db.insertWithOnConflict(
            "media_tags",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE,
        )
    }

    private fun normalizeNames(values: List<String>): List<String> {
        val unique = linkedMapOf<String, String>()
        for (value in values) {
            val cleaned = value.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.joinToString(" ")
            if (cleaned.isBlank()) continue
            unique.putIfAbsent(key(cleaned), cleaned)
        }
        return unique.values.toList()
    }

    private fun key(value: String): String = value.trim().lowercase(Locale.ROOT)
}
