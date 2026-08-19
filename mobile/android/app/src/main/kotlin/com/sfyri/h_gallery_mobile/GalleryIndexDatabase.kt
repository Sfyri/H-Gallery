package com.sfyri.h_gallery_mobile

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.util.Locale
import java.util.UUID

internal data class IndexedMediaDocument(
    val relativePath: String,
    val filename: String,
    val extension: String,
    val mediaType: String,
    val isAnimated: Boolean,
    val mimeType: String,
    val sizeBytes: Long,
    val modifiedEpochMs: Long,
    val documentUri: String,
    val documentId: String,
    val sha256: String,
)

internal data class MediaDatabaseRow(
    val syncUuid: String,
    val relativePath: String,
    val filename: String,
    val extension: String,
    val mediaType: String,
    val isAnimated: Boolean,
    val mimeType: String,
    val sizeBytes: Long,
    val modifiedEpochMs: Long,
    val documentUri: String,
    val documentId: String,
    val sha256: String,
    val isPresent: Boolean,
)

internal data class ReconcileResult(
    val added: Int,
    val updated: Int,
    val moved: Int,
    val removed: Int,
)

internal data class ViewerMediaRecord(
    val documentUri: String,
    val mediaType: String,
    val extension: String,
    val sha256: String,
)

internal data class FranchiseRecord(
    val id: Long,
    val syncUuid: String,
    val name: String,
    val code: String,
    val relativePath: String,
)

internal data class CharacterRecord(
    val id: Long,
    val syncUuid: String,
    val franchiseId: Long,
    val name: String,
    val relativePath: String,
    val franchiseName: String,
    val franchiseCode: String,
    val franchiseRelativePath: String,
)

internal data class DuplicateMediaRecord(
    val syncUuid: String,
    val filename: String,
    val relativePath: String,
)

internal data class OrganizedMediaRecord(
    val syncUuid: String,
    val relativePath: String,
    val filename: String,
    val extension: String,
    val mediaType: String,
    val isAnimated: Boolean,
    val mimeType: String,
    val sizeBytes: Long,
    val modifiedEpochMs: Long,
    val documentUri: String,
    val documentId: String,
    val sha256: String,
    val aiGenerated: Boolean,
)

internal data class TrashSourceRecord(
    val syncUuid: String,
    val relativePath: String,
    val filename: String,
    val extension: String,
    val mediaType: String,
    val isAnimated: Boolean,
    val mimeType: String,
    val sizeBytes: Long,
    val modifiedEpochMs: Long,
    val documentUri: String,
    val documentId: String,
    val sha256: String,
)

internal data class TrashDatabaseRecord(
    val trashId: Long,
    val mediaSyncUuid: String,
    val originalRelativePath: String,
    val trashRelativePath: String,
    val trashDocumentUri: String,
    val trashDocumentId: String,
    val trashFilename: String,
    val deletedEpochMs: Long,
    val extension: String,
    val mediaType: String,
    val isAnimated: Boolean,
    val mimeType: String,
    val sizeBytes: Long,
    val modifiedEpochMs: Long,
    val sha256: String,
)

internal class GalleryIndexDatabase(
    context: Context,
    galleryUuid: String,
) : SQLiteOpenHelper(
    context,
    "gallery_${galleryUuid.replace("-", "")}.db",
    null,
    DATABASE_VERSION,
) {
    companion object {
        private const val DATABASE_VERSION = 6
    }

    override fun onConfigure(db: SQLiteDatabase) {
        super.onConfigure(db)
        db.setForeignKeyConstraintsEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE media (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_uuid TEXT NOT NULL UNIQUE,
                relative_path TEXT NOT NULL,
                filename TEXT NOT NULL,
                extension TEXT NOT NULL,
                media_type TEXT NOT NULL,
                is_animated INTEGER NOT NULL DEFAULT 0,
                mime_type TEXT NOT NULL DEFAULT '',
                size_bytes INTEGER NOT NULL DEFAULT 0,
                modified_epoch_ms INTEGER NOT NULL DEFAULT 0,
                document_uri TEXT NOT NULL,
                document_id TEXT NOT NULL,
                sha256 TEXT NOT NULL,
                is_present INTEGER NOT NULL DEFAULT 1,
                ai_generated INTEGER NOT NULL DEFAULT 0,
                metadata_updated_epoch_ms INTEGER NOT NULL DEFAULT 0,
                created_at_epoch_ms INTEGER NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        createMediaIndexes(db)
        createMetadataSchema(db)
        createBrowseIndexes(db)
        createTrashAndSyncSchema(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            val columns = columnNames(db, "media")
            if ("ai_generated" !in columns) {
                db.execSQL(
                    "ALTER TABLE media ADD COLUMN ai_generated INTEGER NOT NULL DEFAULT 0",
                )
            }
            if ("metadata_updated_epoch_ms" !in columns) {
                db.execSQL(
                    "ALTER TABLE media ADD COLUMN metadata_updated_epoch_ms INTEGER NOT NULL DEFAULT 0",
                )
            }
            createMetadataSchema(db)
        }
        createMediaIndexes(db)
        createBrowseIndexes(db)
        if (oldVersion < 4) {
            createTrashAndSyncSchema(db)
        }
        if (oldVersion < 5) {
            ensureSyncTombstoneGroupColumn(db)
        }
        if (oldVersion < 6) {
            createMetadataBaselineSchema(db)
        }
    }

    private fun createTrashAndSyncSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS trash_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                media_sync_uuid TEXT NOT NULL UNIQUE,
                original_relative_path TEXT NOT NULL,
                trash_relative_path TEXT NOT NULL UNIQUE,
                trash_document_uri TEXT NOT NULL,
                trash_document_id TEXT NOT NULL,
                trash_filename TEXT NOT NULL,
                deleted_epoch_ms INTEGER NOT NULL,
                FOREIGN KEY(media_sync_uuid) REFERENCES media(sync_uuid) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_trash_deleted ON trash_items(deleted_epoch_ms DESC)",
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sync_peers (
                peer_uuid TEXT PRIMARY KEY,
                peer_gallery_uuid TEXT NOT NULL,
                display_name TEXT NOT NULL,
                platform TEXT NOT NULL DEFAULT 'unknown'
                    CHECK(platform IN ('windows', 'android', 'unknown')),
                paired_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                last_seen_at TEXT,
                is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
                UNIQUE(peer_gallery_uuid)
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sync_peers_active ON sync_peers(is_active, display_name)",
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sync_tombstones (
                file_uuid TEXT PRIMARY KEY,
                sha256 TEXT NOT NULL,
                media_type TEXT NOT NULL,
                last_relative_path TEXT NOT NULL,
                deleted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                origin_peer_uuid TEXT,
                created_locally INTEGER NOT NULL DEFAULT 1 CHECK(created_locally IN (0, 1)),
                sync_group_uuid TEXT NOT NULL DEFAULT ''
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sync_tombstones_deleted ON sync_tombstones(deleted_at)",
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sync_tombstone_acks (
                file_uuid TEXT NOT NULL,
                peer_uuid TEXT NOT NULL,
                acknowledged_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY(file_uuid, peer_uuid),
                FOREIGN KEY(file_uuid) REFERENCES sync_tombstones(file_uuid) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """.trimIndent(),
        )
        ensureSyncTombstoneGroupColumn(db)
        createMetadataBaselineSchema(db)
    }

    private fun createMetadataBaselineSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sync_metadata_baselines (
                sync_group_uuid TEXT NOT NULL,
                peer_gallery_uuid TEXT NOT NULL,
                media_sha256 TEXT NOT NULL,
                snapshot_json TEXT NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL,
                PRIMARY KEY(sync_group_uuid, peer_gallery_uuid, media_sha256)
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sync_metadata_baselines_pair " +
                "ON sync_metadata_baselines(sync_group_uuid, peer_gallery_uuid)",
        )
    }

    private fun ensureSyncTombstoneGroupColumn(db: SQLiteDatabase) {
        val columns = columnNames(db, "sync_tombstones")
        if ("sync_group_uuid" !in columns) {
            db.execSQL(
                "ALTER TABLE sync_tombstones ADD COLUMN sync_group_uuid TEXT NOT NULL DEFAULT ''",
            )
        }
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_sync_tombstones_group_deleted " +
                "ON sync_tombstones(sync_group_uuid, deleted_at)",
        )
    }

    private fun createMediaIndexes(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_media_present_unique_path " +
                "ON media(relative_path) WHERE is_present = 1",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_present_path ON media(is_present, relative_path)",
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_media_sha256 ON media(sha256)")
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_media_document_id ON media(document_id)")
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_type ON media(is_present, media_type, is_animated)",
        )
    }

    private fun createBrowseIndexes(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_present_filename " +
                "ON media(is_present, filename COLLATE NOCASE)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_present_ai " +
                "ON media(is_present, ai_generated)",
        )
    }

    private fun createMetadataSchema(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS franchises (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_uuid TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                code TEXT NOT NULL COLLATE NOCASE UNIQUE,
                relative_path TEXT NOT NULL UNIQUE,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at_epoch_ms INTEGER NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS characters (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_uuid TEXT NOT NULL UNIQUE,
                franchise_id INTEGER NOT NULL,
                name TEXT NOT NULL COLLATE NOCASE,
                relative_path TEXT NOT NULL UNIQUE,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at_epoch_ms INTEGER NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL,
                FOREIGN KEY(franchise_id) REFERENCES franchises(id) ON DELETE CASCADE,
                UNIQUE(franchise_id, name)
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS tags (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_uuid TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                type TEXT NOT NULL DEFAULT 'general'
                    CHECK(type IN ('general', 'artist', 'system')),
                created_at_epoch_ms INTEGER NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS media_characters (
                media_sync_uuid TEXT NOT NULL,
                character_id INTEGER NOT NULL,
                PRIMARY KEY(media_sync_uuid, character_id),
                FOREIGN KEY(media_sync_uuid) REFERENCES media(sync_uuid) ON DELETE CASCADE,
                FOREIGN KEY(character_id) REFERENCES characters(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS media_tags (
                media_sync_uuid TEXT NOT NULL,
                tag_id INTEGER NOT NULL,
                PRIMARY KEY(media_sync_uuid, tag_id),
                FOREIGN KEY(media_sync_uuid) REFERENCES media(sync_uuid) ON DELETE CASCADE,
                FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
            )
            """.trimIndent(),
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS operations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                operation_type TEXT NOT NULL,
                source_relative_path TEXT NOT NULL,
                destination_relative_path TEXT NOT NULL,
                created_at_epoch_ms INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_characters_franchise ON characters(franchise_id, is_active)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_characters_character ON media_characters(character_id, media_sync_uuid)",
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS idx_media_tags_tag ON media_tags(tag_id, media_sync_uuid)",
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_tags_type ON tags(type, name)")
    }

    fun reconcile(scanned: List<IndexedMediaDocument>): ReconcileResult {
        val db = writableDatabase
        val existing = readAllRows(db)
        val trashedUuids = readTrashedMediaUuids(db)
        val byPath = existing.filter { it.isPresent }.associateBy { it.relativePath }
        val byPathAll = existing.groupBy { it.relativePath }
        val byDocumentId = existing.groupBy { it.documentId }
        val byHash = existing.groupBy { it.sha256 }
        val scannedPaths = scanned.asSequence().map { it.relativePath }.toHashSet()
        val claimedUuids = hashSetOf<String>()

        var added = 0
        var updated = 0
        var moved = 0
        var removed = 0
        val now = System.currentTimeMillis()

        db.beginTransaction()
        try {
            for (document in scanned) {
                var matched = byPath[document.relativePath]

                if (matched == null) {
                    val samePathCandidates = byPathAll[document.relativePath]
                        .orEmpty()
                        .filter {
                            !it.isPresent &&
                                it.syncUuid !in trashedUuids &&
                                it.sha256 == document.sha256 &&
                                it.syncUuid !in claimedUuids
                        }
                    if (samePathCandidates.size == 1) {
                        matched = samePathCandidates.single()
                    }
                }

                if (matched == null) {
                    val documentCandidates = byDocumentId[document.documentId]
                        .orEmpty()
                        .filter {
                            it.syncUuid !in claimedUuids &&
                                it.syncUuid !in trashedUuids &&
                                it.relativePath !in scannedPaths
                        }
                    if (documentCandidates.size == 1) {
                        matched = documentCandidates.single()
                    }
                }

                if (matched == null) {
                    val hashCandidates = byHash[document.sha256]
                        .orEmpty()
                        .filter {
                            it.syncUuid !in claimedUuids &&
                                it.syncUuid !in trashedUuids &&
                                it.relativePath !in scannedPaths
                        }
                    if (hashCandidates.size == 1) {
                        matched = hashCandidates.single()
                    }
                }

                if (matched == null) {
                    insertDocument(db, UUID.randomUUID().toString(), document, now)
                    added += 1
                    continue
                }

                claimedUuids += matched.syncUuid
                val pathChanged = matched.relativePath != document.relativePath
                val contentChanged = matched.sha256 != document.sha256
                val metadataChanged = matched.filename != document.filename ||
                    matched.extension != document.extension ||
                    matched.mediaType != document.mediaType ||
                    matched.isAnimated != document.isAnimated ||
                    matched.mimeType != document.mimeType ||
                    matched.sizeBytes != document.sizeBytes ||
                    matched.modifiedEpochMs != document.modifiedEpochMs ||
                    matched.documentUri != document.documentUri ||
                    matched.documentId != document.documentId ||
                    !matched.isPresent

                updateDocument(db, matched.syncUuid, document, now)
                when {
                    pathChanged -> moved += 1
                    contentChanged || metadataChanged -> updated += 1
                }
            }

            for (row in existing) {
                if (row.syncUuid in claimedUuids) continue
                if (row.relativePath in scannedPaths) continue
                if (!row.isPresent) continue

                val values = ContentValues().apply {
                    put("is_present", 0)
                    put("updated_at_epoch_ms", now)
                }
                db.update("media", values, "sync_uuid = ?", arrayOf(row.syncUuid))
                removed += 1
            }

            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }

        return ReconcileResult(
            added = added,
            updated = updated,
            moved = moved,
            removed = removed,
        )
    }

    fun stats(): Map<String, Any> {
        val db = readableDatabase
        db.rawQuery(
            """
            SELECT
                COUNT(*) AS total,
                COALESCE(SUM(CASE WHEN media_type = 'image' AND is_animated = 0 THEN 1 ELSE 0 END), 0) AS photos,
                COALESCE(SUM(CASE WHEN media_type = 'image' AND is_animated = 1 THEN 1 ELSE 0 END), 0) AS animated,
                COALESCE(SUM(CASE WHEN media_type = 'video' THEN 1 ELSE 0 END), 0) AS videos
            FROM media
            WHERE is_present = 1
            """.trimIndent(),
            null,
        ).use { cursor ->
            cursor.moveToFirst()
            return mapOf(
                "total" to cursor.getInt(cursor.getColumnIndexOrThrow("total")),
                "photos" to cursor.getInt(cursor.getColumnIndexOrThrow("photos")),
                "animated" to cursor.getInt(cursor.getColumnIndexOrThrow("animated")),
                "videos" to cursor.getInt(cursor.getColumnIndexOrThrow("videos")),
            )
        }
    }

    fun listMedia(limit: Int, offset: Int): List<Map<String, Any>> {
        val safeLimit = limit.coerceIn(1, 500)
        val safeOffset = offset.coerceAtLeast(0)
        val rows = mutableListOf<Map<String, Any>>()
        readableDatabase.rawQuery(
            """
            SELECT sync_uuid, relative_path, filename, extension, media_type,
                   is_animated, mime_type, size_bytes, modified_epoch_ms, sha256
            FROM media
            WHERE is_present = 1
            ORDER BY relative_path COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """.trimIndent(),
            arrayOf(safeLimit.toString(), safeOffset.toString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                rows += mapOf(
                    "syncUuid" to cursor.getString(0),
                    "relativePath" to cursor.getString(1),
                    "filename" to cursor.getString(2),
                    "extension" to cursor.getString(3),
                    "mediaType" to cursor.getString(4),
                    "isAnimated" to (cursor.getInt(5) != 0),
                    "mimeType" to cursor.getString(6),
                    "sizeBytes" to cursor.getLong(7),
                    "modifiedEpochMs" to cursor.getLong(8),
                    "sha256" to cursor.getString(9),
                )
            }
        }
        return rows
    }

    fun browseCatalog(): Map<String, Any> {
        val series = linkedMapOf<String, MutableBrowseCollection>()
        val special = linkedMapOf<String, MutableBrowseCollection>()
        var total = 0

        readableDatabase.rawQuery(
            "SELECT sync_uuid, relative_path FROM media WHERE is_present = 1 " +
                "ORDER BY relative_path COLLATE NOCASE",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                total += 1
                val syncUuid = cursor.getString(0)
                val relativePath = cursor.getString(1)
                val segments = relativePath.split('/').filter { it.isNotBlank() }
                if (segments.size < 2) continue
                val top = segments.first()
                if (top.startsWith('.')) continue

                val target = when {
                    top.equals("!Crossovers", ignoreCase = true) -> special
                    top.startsWith('!') -> continue
                    else -> series
                }
                val key = top.lowercase(Locale.ROOT)
                val kind = if (target === special) "special" else "series"
                val displayName = if (kind == "special") "Crossovers" else top
                val accumulator = target.getOrPut(key) {
                    MutableBrowseCollection(
                        name = displayName,
                        relativePath = top,
                        kind = kind,
                    )
                }
                accumulator.mediaCount += 1
                if (accumulator.coverSyncUuid.isEmpty()) {
                    accumulator.coverSyncUuid = syncUuid
                }
            }
        }

        return mapOf(
            "series" to series.values
                .sortedBy { it.name.lowercase(Locale.ROOT) }
                .map(::browseCollectionToMap),
            "special" to special.values
                .sortedBy { it.name.lowercase(Locale.ROOT) }
                .map(::browseCollectionToMap),
            "total" to total,
        )
    }

    fun seriesDetail(relativePath: String): Map<String, Any> {
        val requested = relativePath.trim().trim('/')
        if (requested.isEmpty()) {
            throw IllegalArgumentException("Serie non valida.")
        }
        val prefix = "$requested/"
        val collections = linkedMapOf<String, MutableBrowseCollection>()
        var mediaCount = 0
        var coverSyncUuid = ""
        var displayName = requested.substringAfterLast('/')

        readableDatabase.rawQuery(
            "SELECT sync_uuid, relative_path FROM media WHERE is_present = 1 " +
                "ORDER BY relative_path COLLATE NOCASE",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val syncUuid = cursor.getString(0)
                val path = cursor.getString(1)
                if (!path.startsWith(prefix, ignoreCase = true)) continue
                mediaCount += 1
                if (coverSyncUuid.isEmpty()) coverSyncUuid = syncUuid

                val remainder = path.substring(prefix.length)
                val slash = remainder.indexOf('/')
                if (slash <= 0) continue
                val folderName = remainder.substring(0, slash)
                val folderPath = "$requested/$folderName"
                val kind: String
                val name: String
                when {
                    folderName.equals("!Multiple", ignoreCase = true) -> {
                        kind = "multiple"
                        name = "Multiple"
                    }
                    folderName.startsWith('.') -> {
                        kind = "other"
                        name = folderName.trimStart('.').ifBlank { "Altri" }
                    }
                    folderName.startsWith('!') -> {
                        kind = "special"
                        name = folderName.trimStart('!').ifBlank { folderName }
                    }
                    else -> {
                        kind = "character"
                        name = folderName
                    }
                }

                val key = "$kind:${folderPath.lowercase(Locale.ROOT)}"
                val accumulator = collections.getOrPut(key) {
                    MutableBrowseCollection(
                        name = name,
                        relativePath = folderPath,
                        kind = kind,
                    )
                }
                accumulator.mediaCount += 1
                if (accumulator.coverSyncUuid.isEmpty()) {
                    accumulator.coverSyncUuid = syncUuid
                }
            }
        }

        listFranchises().firstOrNull {
            it.relativePath.equals(requested, ignoreCase = true)
        }?.let { displayName = it.name }

        val ordered = collections.values.sortedWith(
            compareBy<MutableBrowseCollection> {
                when (it.kind) {
                    "character" -> 0
                    "multiple" -> 1
                    else -> 2
                }
            }.thenBy { it.name.lowercase(Locale.ROOT) },
        )

        return mapOf(
            "name" to displayName,
            "relativePath" to requested,
            "mediaCount" to mediaCount,
            "coverSyncUuid" to coverSyncUuid,
            "collections" to ordered.map(::browseCollectionToMap),
        )
    }

    fun filterCatalog(): Map<String, Any> {
        val browse = browseCatalog()
        @Suppress("UNCHECKED_CAST")
        val series = browse["series"] as? List<Map<String, Any>> ?: emptyList()
        @Suppress("UNCHECKED_CAST")
        val special = browse["special"] as? List<Map<String, Any>> ?: emptyList()
        val locations = mutableListOf<Map<String, Any>>()
        val seriesNames = linkedMapOf<String, String>()

        for (entry in series) {
            val name = entry["name"]?.toString().orEmpty()
            val path = entry["relativePath"]?.toString().orEmpty()
            if (path.isEmpty()) continue
            seriesNames[path.lowercase(Locale.ROOT)] = name
            locations += mapOf(
                "label" to name,
                "relativePath" to path,
                "kind" to "series",
            )
        }

        val children = linkedMapOf<String, Map<String, Any>>()
        readableDatabase.rawQuery(
            "SELECT relative_path FROM media WHERE is_present = 1 " +
                "ORDER BY relative_path COLLATE NOCASE",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.getString(0)
                val segments = path.split('/').filter { it.isNotBlank() }
                if (segments.size < 3) continue
                val top = segments[0]
                val seriesName = seriesNames[top.lowercase(Locale.ROOT)] ?: continue
                val folder = segments[1]
                val childPath = "$top/$folder"
                val key = childPath.lowercase(Locale.ROOT)
                if (key in children) continue
                val kind: String
                val childName: String
                when {
                    folder.equals("!Multiple", ignoreCase = true) -> {
                        kind = "multiple"
                        childName = "Multiple"
                    }
                    folder.startsWith('.') -> {
                        kind = "other"
                        childName = folder.trimStart('.').ifBlank { "Altri" }
                    }
                    folder.startsWith('!') -> {
                        kind = "special"
                        childName = folder.trimStart('!').ifBlank { folder }
                    }
                    else -> {
                        kind = "character"
                        childName = folder
                    }
                }
                children[key] = mapOf(
                    "label" to "$seriesName · $childName",
                    "relativePath" to childPath,
                    "kind" to kind,
                )
            }
        }
        locations += children.values.sortedBy {
            it["label"]?.toString()?.lowercase(Locale.ROOT).orEmpty()
        }

        for (entry in special) {
            val name = entry["name"]?.toString().orEmpty()
            val path = entry["relativePath"]?.toString().orEmpty()
            if (path.isEmpty()) continue
            locations += mapOf(
                "label" to name,
                "relativePath" to path,
                "kind" to "special",
            )
        }

        return mapOf(
            "locations" to locations,
            "tags" to listTagNames("general"),
            "artists" to listTagNames("artist"),
        )
    }

    fun queryMedia(
        text: String,
        kind: String,
        relativePrefix: String,
        tag: String,
        artist: String,
        aiOnly: Boolean,
        limit: Int,
        offset: Int,
    ): Map<String, Any> {
        val where = mutableListOf("m.is_present = 1")
        val args = mutableListOf<String>()
        val cleanText = text.trim()
        val cleanPrefix = relativePrefix.trim().trim('/')
        val cleanTag = tag.trim()
        val cleanArtist = artist.trim()

        if (cleanText.isNotEmpty()) {
            val pattern = "%${escapeLike(cleanText)}%"
            where += """
                (
                    m.filename LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                    m.relative_path LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                    EXISTS (
                        SELECT 1 FROM media_tags mt
                        JOIN tags t ON t.id = mt.tag_id
                        WHERE mt.media_sync_uuid = m.sync_uuid
                          AND t.name LIKE ? ESCAPE '\\' COLLATE NOCASE
                    ) OR
                    EXISTS (
                        SELECT 1 FROM media_characters mc
                        JOIN characters c ON c.id = mc.character_id
                        JOIN franchises f ON f.id = c.franchise_id
                        WHERE mc.media_sync_uuid = m.sync_uuid
                          AND (
                              c.name LIKE ? ESCAPE '\\' COLLATE NOCASE OR
                              f.name LIKE ? ESCAPE '\\' COLLATE NOCASE
                          )
                    )
                )
            """.trimIndent()
            repeat(5) { args += pattern }
        }

        when (kind) {
            "photo" -> where += "m.media_type = 'image' AND m.is_animated = 0"
            "animated" -> where += "m.media_type = 'image' AND m.is_animated = 1"
            "video" -> where += "m.media_type = 'video'"
        }

        if (cleanPrefix.isNotEmpty()) {
            where += "m.relative_path LIKE ? ESCAPE '\\' COLLATE NOCASE"
            args += "${escapeLike(cleanPrefix)}/%"
        }
        if (cleanTag.isNotEmpty()) {
            where += """
                EXISTS (
                    SELECT 1 FROM media_tags mt
                    JOIN tags t ON t.id = mt.tag_id
                    WHERE mt.media_sync_uuid = m.sync_uuid
                      AND t.type = 'general'
                      AND t.name = ? COLLATE NOCASE
                )
            """.trimIndent()
            args += cleanTag
        }
        if (cleanArtist.isNotEmpty()) {
            where += """
                EXISTS (
                    SELECT 1 FROM media_tags mt
                    JOIN tags t ON t.id = mt.tag_id
                    WHERE mt.media_sync_uuid = m.sync_uuid
                      AND t.type = 'artist'
                      AND t.name = ? COLLATE NOCASE
                )
            """.trimIndent()
            args += cleanArtist
        }
        if (aiOnly) {
            where += "(m.ai_generated = 1 OR m.relative_path LIKE '%/.AI/%' COLLATE NOCASE)"
        }

        val whereSql = where.joinToString(" AND ")
        val db = readableDatabase
        val total = db.rawQuery(
            "SELECT COUNT(*) FROM media m WHERE $whereSql",
            args.toTypedArray(),
        ).use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) else 0
        }

        val safeLimit = limit.coerceIn(1, 500)
        val safeOffset = offset.coerceAtLeast(0)
        val queryArgs = args.toMutableList().apply {
            add(safeLimit.toString())
            add(safeOffset.toString())
        }
        val items = mutableListOf<Map<String, Any>>()
        db.rawQuery(
            """
            SELECT m.sync_uuid, m.relative_path, m.filename, m.extension, m.media_type,
                   m.is_animated, m.mime_type, m.size_bytes, m.modified_epoch_ms, m.sha256
            FROM media m
            WHERE $whereSql
            ORDER BY m.relative_path COLLATE NOCASE ASC
            LIMIT ? OFFSET ?
            """.trimIndent(),
            queryArgs.toTypedArray(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                items += mapOf(
                    "syncUuid" to cursor.getString(0),
                    "relativePath" to cursor.getString(1),
                    "filename" to cursor.getString(2),
                    "extension" to cursor.getString(3),
                    "mediaType" to cursor.getString(4),
                    "isAnimated" to (cursor.getInt(5) != 0),
                    "mimeType" to cursor.getString(6),
                    "sizeBytes" to cursor.getLong(7),
                    "modifiedEpochMs" to cursor.getLong(8),
                    "sha256" to cursor.getString(9),
                )
            }
        }
        return mapOf("total" to total, "items" to items)
    }

    fun mediaMetadata(syncUuid: String): Map<String, Any> {
        val db = readableDatabase
        var aiGenerated = false
        var relativePath = ""
        db.rawQuery(
            "SELECT ai_generated, relative_path FROM media " +
                "WHERE sync_uuid = ? AND is_present = 1 LIMIT 1",
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) {
                return mapOf(
                    "aiGenerated" to false,
                    "characters" to emptyList<Map<String, Any>>(),
                    "tags" to emptyList<String>(),
                    "artists" to emptyList<String>(),
                )
            }
            aiGenerated = cursor.getInt(0) != 0
            relativePath = cursor.getString(1)
        }
        if (relativePath.split('/').any { it.equals(".AI", ignoreCase = true) }) {
            aiGenerated = true
        }

        val characters = mutableListOf<Map<String, Any>>()
        db.rawQuery(
            """
            SELECT c.name, f.name
            FROM media_characters mc
            JOIN characters c ON c.id = mc.character_id
            JOIN franchises f ON f.id = c.franchise_id
            WHERE mc.media_sync_uuid = ?
            ORDER BY f.name COLLATE NOCASE, c.name COLLATE NOCASE
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                characters += mapOf(
                    "name" to cursor.getString(0),
                    "franchiseName" to cursor.getString(1),
                )
            }
        }
        if (characters.isEmpty()) {
            val segments = relativePath.split('/').filter { it.isNotBlank() }
            if (segments.size >= 3) {
                val franchise = segments[0]
                val character = segments[1]
                if (!franchise.startsWith('!') && !franchise.startsWith('.') &&
                    !character.startsWith('!') && !character.startsWith('.')
                ) {
                    characters += mapOf(
                        "name" to character,
                        "franchiseName" to franchise,
                    )
                }
            }
        }

        fun tagsOfType(type: String): List<String> {
            val values = mutableListOf<String>()
            db.rawQuery(
                """
                SELECT t.name
                FROM media_tags mt
                JOIN tags t ON t.id = mt.tag_id
                WHERE mt.media_sync_uuid = ? AND t.type = ?
                ORDER BY t.name COLLATE NOCASE
                """.trimIndent(),
                arrayOf(syncUuid, type),
            ).use { cursor ->
                while (cursor.moveToNext()) values += cursor.getString(0)
            }
            return values
        }

        return mapOf(
            "aiGenerated" to aiGenerated,
            "characters" to characters,
            "tags" to tagsOfType("general"),
            "artists" to tagsOfType("artist"),
        )
    }

    fun mediaForThumbnail(syncUuid: String): Pair<String, String>? {
        readableDatabase.rawQuery(
            """
            SELECT document_uri, media_type
            FROM media
            WHERE sync_uuid = ? AND is_present = 1
            LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return cursor.getString(0) to cursor.getString(1)
        }
    }

    fun mediaForViewer(syncUuid: String): ViewerMediaRecord? {
        readableDatabase.rawQuery(
            """
            SELECT document_uri, media_type, extension, sha256
            FROM media
            WHERE sync_uuid = ? AND is_present = 1
            LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return ViewerMediaRecord(
                documentUri = cursor.getString(0),
                mediaType = cursor.getString(1),
                extension = cursor.getString(2),
                sha256 = cursor.getString(3),
            )
        }
    }

    fun findDuplicate(sha256: String): DuplicateMediaRecord? {
        readableDatabase.rawQuery(
            """
            SELECT sync_uuid, filename, relative_path
            FROM media
            WHERE sha256 = ? AND is_present = 1
            ORDER BY id
            LIMIT 1
            """.trimIndent(),
            arrayOf(sha256),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return DuplicateMediaRecord(
                syncUuid = cursor.getString(0),
                filename = cursor.getString(1),
                relativePath = cursor.getString(2),
            )
        }
    }

    fun listFranchises(): List<FranchiseRecord> {
        val rows = mutableListOf<FranchiseRecord>()
        readableDatabase.rawQuery(
            """
            SELECT id, sync_uuid, name, code, relative_path
            FROM franchises
            WHERE is_active = 1
            ORDER BY name COLLATE NOCASE
            """.trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                rows += FranchiseRecord(
                    id = cursor.getLong(0),
                    syncUuid = cursor.getString(1),
                    name = cursor.getString(2),
                    code = cursor.getString(3),
                    relativePath = cursor.getString(4),
                )
            }
        }
        return rows
    }

    fun listCharacters(): List<CharacterRecord> {
        val rows = mutableListOf<CharacterRecord>()
        readableDatabase.rawQuery(
            """
            SELECT c.id, c.sync_uuid, c.franchise_id, c.name, c.relative_path,
                   f.name, f.code, f.relative_path
            FROM characters c
            JOIN franchises f ON f.id = c.franchise_id
            WHERE c.is_active = 1 AND f.is_active = 1
            ORDER BY f.name COLLATE NOCASE, c.name COLLATE NOCASE
            """.trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                rows += CharacterRecord(
                    id = cursor.getLong(0),
                    syncUuid = cursor.getString(1),
                    franchiseId = cursor.getLong(2),
                    name = cursor.getString(3),
                    relativePath = cursor.getString(4),
                    franchiseName = cursor.getString(5),
                    franchiseCode = cursor.getString(6),
                    franchiseRelativePath = cursor.getString(7),
                )
            }
        }
        return rows
    }

    fun charactersByIds(ids: List<Long>): List<CharacterRecord> {
        val uniqueIds = ids.distinct()
        if (uniqueIds.isEmpty()) return emptyList()
        val placeholders = uniqueIds.joinToString(",") { "?" }
        val rows = mutableMapOf<Long, CharacterRecord>()
        readableDatabase.rawQuery(
            """
            SELECT c.id, c.sync_uuid, c.franchise_id, c.name, c.relative_path,
                   f.name, f.code, f.relative_path
            FROM characters c
            JOIN franchises f ON f.id = c.franchise_id
            WHERE c.id IN ($placeholders)
              AND c.is_active = 1 AND f.is_active = 1
            """.trimIndent(),
            uniqueIds.map { it.toString() }.toTypedArray(),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                val record = CharacterRecord(
                    id = cursor.getLong(0),
                    syncUuid = cursor.getString(1),
                    franchiseId = cursor.getLong(2),
                    name = cursor.getString(3),
                    relativePath = cursor.getString(4),
                    franchiseName = cursor.getString(5),
                    franchiseCode = cursor.getString(6),
                    franchiseRelativePath = cursor.getString(7),
                )
                rows[record.id] = record
            }
        }
        return uniqueIds.mapNotNull(rows::get)
    }

    fun listTagNames(type: String): List<String> {
        val safeType = type.takeIf { it == "general" || it == "artist" || it == "system" }
            ?: return emptyList()
        val values = mutableListOf<String>()
        readableDatabase.rawQuery(
            "SELECT name FROM tags WHERE type = ? ORDER BY name COLLATE NOCASE",
            arrayOf(safeType),
        ).use { cursor ->
            while (cursor.moveToNext()) values += cursor.getString(0)
        }
        return values
    }

    fun ensureDiscoveredFranchise(
        name: String,
        relativePath: String,
        derivedCode: String,
    ): FranchiseRecord {
        val db = writableDatabase
        db.rawQuery(
            """
            SELECT id, sync_uuid, name, code, relative_path
            FROM franchises
            WHERE name = ? COLLATE NOCASE OR relative_path = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(name, relativePath),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val now = System.currentTimeMillis()
                val values = ContentValues().apply {
                    put("name", name)
                    put("relative_path", relativePath)
                    put("is_active", 1)
                    put("updated_at_epoch_ms", now)
                }
                db.update("franchises", values, "id = ?", arrayOf(id.toString()))
                return FranchiseRecord(
                    id = id,
                    syncUuid = cursor.getString(1),
                    name = name,
                    code = cursor.getString(3),
                    relativePath = relativePath,
                )
            }
        }
        return insertFranchise(db, name, uniqueFranchiseCode(db, derivedCode), relativePath)
    }

    fun createFranchise(name: String, code: String, relativePath: String): FranchiseRecord {
        val db = writableDatabase
        db.rawQuery(
            "SELECT 1 FROM franchises WHERE name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(name),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                throw IllegalArgumentException("Esiste già una serie con questo nome.")
            }
        }
        return insertFranchise(db, name, uniqueFranchiseCode(db, code), relativePath)
    }

    fun ensureDiscoveredCharacter(
        franchiseId: Long,
        name: String,
        relativePath: String,
    ): CharacterRecord {
        val db = writableDatabase
        db.rawQuery(
            """
            SELECT id, sync_uuid
            FROM characters
            WHERE (franchise_id = ? AND name = ? COLLATE NOCASE) OR relative_path = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(franchiseId.toString(), name, relativePath),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val values = ContentValues().apply {
                    put("franchise_id", franchiseId)
                    put("name", name)
                    put("relative_path", relativePath)
                    put("is_active", 1)
                    put("updated_at_epoch_ms", System.currentTimeMillis())
                }
                db.update("characters", values, "id = ?", arrayOf(id.toString()))
                return characterById(id)
                    ?: throw IllegalStateException("Personaggio non leggibile dopo l'aggiornamento.")
            }
        }
        return insertCharacter(db, franchiseId, name, relativePath)
    }

    fun createCharacter(franchiseId: Long, name: String, relativePath: String): CharacterRecord {
        val db = writableDatabase
        db.rawQuery(
            """
            SELECT 1 FROM characters
            WHERE franchise_id = ? AND name = ? COLLATE NOCASE
            LIMIT 1
            """.trimIndent(),
            arrayOf(franchiseId.toString(), name),
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                throw IllegalArgumentException("Questo personaggio esiste già nella serie selezionata.")
            }
        }
        return insertCharacter(db, franchiseId, name, relativePath)
    }

    fun recordOrganizedMedia(
        media: OrganizedMediaRecord,
        characterIds: List<Long>,
        tags: List<String>,
        artists: List<String>,
        sourceRelativePath: String,
    ) {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            db.rawQuery(
                "SELECT 1 FROM media WHERE relative_path = ? AND is_present = 1 LIMIT 1",
                arrayOf(media.relativePath),
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    throw IllegalStateException(
                        "Il percorso di destinazione è già indicizzato: ${media.relativePath}",
                    )
                }
            }

            val values = ContentValues().apply {
                put("sync_uuid", media.syncUuid)
                put("relative_path", media.relativePath)
                put("filename", media.filename)
                put("extension", media.extension)
                put("media_type", media.mediaType)
                put("is_animated", if (media.isAnimated) 1 else 0)
                put("mime_type", media.mimeType)
                put("size_bytes", media.sizeBytes)
                put("modified_epoch_ms", media.modifiedEpochMs)
                put("document_uri", media.documentUri)
                put("document_id", media.documentId)
                put("sha256", media.sha256)
                put("is_present", 1)
                put("ai_generated", if (media.aiGenerated) 1 else 0)
                put("metadata_updated_epoch_ms", now)
                put("created_at_epoch_ms", now)
                put("updated_at_epoch_ms", now)
            }
            db.insertOrThrow("media", null, values)

            for (characterId in characterIds.distinct()) {
                val relation = ContentValues().apply {
                    put("media_sync_uuid", media.syncUuid)
                    put("character_id", characterId)
                }
                db.insertOrThrow("media_characters", null, relation)
            }

            val seenNames = hashSetOf<String>()
            for (tag in tags) {
                val cleaned = normalizeMetadataName(tag)
                val key = cleaned.lowercase(Locale.ROOT)
                if (cleaned.isEmpty() || key == "ai" || !seenNames.add(key)) continue
                val tagId = ensureTag(db, cleaned, "general", now)
                insertMediaTag(db, media.syncUuid, tagId)
            }
            for (artist in artists) {
                val cleaned = normalizeMetadataName(artist)
                val key = cleaned.lowercase(Locale.ROOT)
                if (cleaned.isEmpty() || key == "ai" || !seenNames.add(key)) continue
                val tagId = ensureTag(db, cleaned, "artist", now)
                insertMediaTag(db, media.syncUuid, tagId)
            }
            if (media.aiGenerated) {
                val tagId = ensureTag(db, "AI", "system", now)
                insertMediaTag(db, media.syncUuid, tagId)
            }

            val operation = ContentValues().apply {
                put("operation_type", "organize")
                put("source_relative_path", sourceRelativePath)
                put("destination_relative_path", media.relativePath)
                put("created_at_epoch_ms", now)
            }
            db.insertOrThrow("operations", null, operation)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun rollbackOrganizedMedia(syncUuid: String, destinationRelativePath: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            db.delete(
                "operations",
                "operation_type = 'organize' AND destination_relative_path = ?",
                arrayOf(destinationRelativePath),
            )
            db.delete("media", "sync_uuid = ?", arrayOf(syncUuid))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun trashSource(syncUuid: String): TrashSourceRecord? {
        readableDatabase.rawQuery(
            """
            SELECT sync_uuid, relative_path, filename, extension, media_type,
                   is_animated, mime_type, size_bytes, modified_epoch_ms,
                   document_uri, document_id, sha256
            FROM media
            WHERE sync_uuid = ? AND is_present = 1
            LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return TrashSourceRecord(
                syncUuid = cursor.getString(0),
                relativePath = cursor.getString(1),
                filename = cursor.getString(2),
                extension = cursor.getString(3),
                mediaType = cursor.getString(4),
                isAnimated = cursor.getInt(5) != 0,
                mimeType = cursor.getString(6),
                sizeBytes = cursor.getLong(7),
                modifiedEpochMs = cursor.getLong(8),
                documentUri = cursor.getString(9),
                documentId = cursor.getString(10),
                sha256 = cursor.getString(11),
            )
        }
    }

    fun markTrashed(
        mediaSyncUuid: String,
        originalRelativePath: String,
        trashRelativePath: String,
        trashDocumentUri: String,
        trashDocumentId: String,
        trashFilename: String,
        sizeBytes: Long,
        modifiedEpochMs: Long,
    ) {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            db.rawQuery(
                "SELECT 1 FROM trash_items WHERE media_sync_uuid = ? LIMIT 1",
                arrayOf(mediaSyncUuid),
            ).use { cursor ->
                if (cursor.moveToFirst()) throw IllegalStateException("Il media è già nel cestino.")
            }
            val trash = ContentValues().apply {
                put("media_sync_uuid", mediaSyncUuid)
                put("original_relative_path", originalRelativePath)
                put("trash_relative_path", trashRelativePath)
                put("trash_document_uri", trashDocumentUri)
                put("trash_document_id", trashDocumentId)
                put("trash_filename", trashFilename)
                put("deleted_epoch_ms", now)
            }
            db.insertOrThrow("trash_items", null, trash)
            val media = ContentValues().apply {
                put("is_present", 0)
                put("size_bytes", sizeBytes)
                put("modified_epoch_ms", modifiedEpochMs)
                put("updated_at_epoch_ms", now)
            }
            if (db.update("media", media, "sync_uuid = ?", arrayOf(mediaSyncUuid)) != 1) {
                throw IllegalStateException("Il database non ha aggiornato il media nel cestino.")
            }
            val operation = ContentValues().apply {
                put("operation_type", "trash")
                put("source_relative_path", originalRelativePath)
                put("destination_relative_path", trashRelativePath)
                put("created_at_epoch_ms", now)
            }
            db.insertOrThrow("operations", null, operation)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun rollbackTrash(mediaSyncUuid: String) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val original = db.rawQuery(
                "SELECT original_relative_path, trash_relative_path FROM trash_items WHERE media_sync_uuid = ?",
                arrayOf(mediaSyncUuid),
            ).use { cursor ->
                if (!cursor.moveToFirst()) null else cursor.getString(0) to cursor.getString(1)
            }
            if (original != null) {
                db.delete("trash_items", "media_sync_uuid = ?", arrayOf(mediaSyncUuid))
                db.delete(
                    "operations",
                    "operation_type = 'trash' AND source_relative_path = ? AND destination_relative_path = ?",
                    arrayOf(original.first, original.second),
                )
                val values = ContentValues().apply {
                    put("is_present", 1)
                    put("updated_at_epoch_ms", System.currentTimeMillis())
                }
                db.update("media", values, "sync_uuid = ?", arrayOf(mediaSyncUuid))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun trashStats(): Map<String, Any> {
        readableDatabase.rawQuery(
            """
            SELECT COUNT(*), COALESCE(SUM(m.size_bytes), 0),
                   COALESCE(SUM(CASE WHEN m.media_type = 'image' AND m.is_animated = 0 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN m.media_type = 'image' AND m.is_animated = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN m.media_type = 'video' THEN 1 ELSE 0 END), 0)
            FROM trash_items t
            JOIN media m ON m.sync_uuid = t.media_sync_uuid
            """.trimIndent(),
            null,
        ).use { cursor ->
            cursor.moveToFirst()
            return mapOf(
                "total" to cursor.getInt(0),
                "totalBytes" to cursor.getLong(1),
                "photos" to cursor.getInt(2),
                "animated" to cursor.getInt(3),
                "videos" to cursor.getInt(4),
            )
        }
    }

    fun listTrashItems(limit: Int, offset: Int): List<Map<String, Any>> {
        val safeLimit = limit.coerceIn(1, 500)
        val safeOffset = offset.coerceAtLeast(0)
        val values = mutableListOf<Map<String, Any>>()
        readableDatabase.rawQuery(
            """
            SELECT t.id, t.original_relative_path, t.trash_relative_path, t.deleted_epoch_ms,
                   m.sync_uuid, t.trash_filename, m.extension, m.media_type, m.is_animated,
                   m.mime_type, m.size_bytes, m.modified_epoch_ms, m.sha256
            FROM trash_items t
            JOIN media m ON m.sync_uuid = t.media_sync_uuid
            ORDER BY t.deleted_epoch_ms DESC, t.id DESC
            LIMIT ? OFFSET ?
            """.trimIndent(),
            arrayOf(safeLimit.toString(), safeOffset.toString()),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                values += mapOf(
                    "trashId" to cursor.getLong(0),
                    "originalRelativePath" to cursor.getString(1),
                    "trashRelativePath" to cursor.getString(2),
                    "deletedAtEpochMs" to cursor.getLong(3),
                    "syncUuid" to cursor.getString(4),
                    "relativePath" to cursor.getString(2),
                    "filename" to cursor.getString(5),
                    "extension" to cursor.getString(6),
                    "mediaType" to cursor.getString(7),
                    "isAnimated" to (cursor.getInt(8) != 0),
                    "mimeType" to cursor.getString(9),
                    "sizeBytes" to cursor.getLong(10),
                    "modifiedEpochMs" to cursor.getLong(11),
                    "sha256" to cursor.getString(12),
                )
            }
        }
        return values
    }

    fun trashRecord(trashId: Long): TrashDatabaseRecord? {
        readableDatabase.rawQuery(
            """
            SELECT t.id, t.media_sync_uuid, t.original_relative_path, t.trash_relative_path,
                   t.trash_document_uri, t.trash_document_id, t.trash_filename, t.deleted_epoch_ms,
                   m.extension, m.media_type, m.is_animated, m.mime_type, m.size_bytes,
                   m.modified_epoch_ms, m.sha256
            FROM trash_items t
            JOIN media m ON m.sync_uuid = t.media_sync_uuid
            WHERE t.id = ? LIMIT 1
            """.trimIndent(),
            arrayOf(trashId.toString()),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return TrashDatabaseRecord(
                trashId = cursor.getLong(0),
                mediaSyncUuid = cursor.getString(1),
                originalRelativePath = cursor.getString(2),
                trashRelativePath = cursor.getString(3),
                trashDocumentUri = cursor.getString(4),
                trashDocumentId = cursor.getString(5),
                trashFilename = cursor.getString(6),
                deletedEpochMs = cursor.getLong(7),
                extension = cursor.getString(8),
                mediaType = cursor.getString(9),
                isAnimated = cursor.getInt(10) != 0,
                mimeType = cursor.getString(11),
                sizeBytes = cursor.getLong(12),
                modifiedEpochMs = cursor.getLong(13),
                sha256 = cursor.getString(14),
            )
        }
    }

    fun allTrashRecords(): List<TrashDatabaseRecord> {
        val ids = mutableListOf<Long>()
        readableDatabase.rawQuery("SELECT id FROM trash_items ORDER BY id", null).use { cursor ->
            while (cursor.moveToNext()) ids += cursor.getLong(0)
        }
        return ids.mapNotNull(::trashRecord)
    }

    fun trashMediaForThumbnail(syncUuid: String): Pair<String, String>? {
        readableDatabase.rawQuery(
            """
            SELECT t.trash_document_uri, m.media_type
            FROM trash_items t JOIN media m ON m.sync_uuid = t.media_sync_uuid
            WHERE t.media_sync_uuid = ? LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return cursor.getString(0) to cursor.getString(1)
        }
    }

    fun trashMediaForViewer(syncUuid: String): ViewerMediaRecord? {
        readableDatabase.rawQuery(
            """
            SELECT t.trash_document_uri, m.media_type, m.extension, m.sha256
            FROM trash_items t JOIN media m ON m.sync_uuid = t.media_sync_uuid
            WHERE t.media_sync_uuid = ? LIMIT 1
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return ViewerMediaRecord(
                documentUri = cursor.getString(0),
                mediaType = cursor.getString(1),
                extension = cursor.getString(2),
                sha256 = cursor.getString(3),
            )
        }
    }

    fun restoreTrash(
        trashId: Long,
        relativePath: String,
        filename: String,
        documentUri: String,
        documentId: String,
        sizeBytes: Long,
        modifiedEpochMs: Long,
    ) {
        val db = writableDatabase
        val now = System.currentTimeMillis()
        db.beginTransaction()
        try {
            val record = trashRecord(trashId)
                ?: throw IllegalStateException("Elemento del cestino non trovato.")
            db.rawQuery(
                "SELECT 1 FROM media WHERE relative_path = ? AND is_present = 1 LIMIT 1",
                arrayOf(relativePath),
            ).use { cursor ->
                if (cursor.moveToFirst()) throw IllegalStateException("Esiste già un media nella destinazione.")
            }
            val media = ContentValues().apply {
                put("relative_path", relativePath)
                put("filename", filename)
                put("document_uri", documentUri)
                put("document_id", documentId)
                put("size_bytes", sizeBytes)
                put("modified_epoch_ms", modifiedEpochMs)
                put("is_present", 1)
                put("updated_at_epoch_ms", now)
            }
            db.update("media", media, "sync_uuid = ?", arrayOf(record.mediaSyncUuid))
            db.delete("trash_items", "id = ?", arrayOf(trashId.toString()))
            val operation = ContentValues().apply {
                put("operation_type", "restore")
                put("source_relative_path", record.trashRelativePath)
                put("destination_relative_path", relativePath)
                put("created_at_epoch_ms", now)
            }
            db.insertOrThrow("operations", null, operation)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun permanentlyDeleteTrash(
        trashId: Long,
        createSyncTombstone: Boolean = true,
    ) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val record = trashRecord(trashId) ?: run {
                db.setTransactionSuccessful()
                return
            }
            val syncGroupUuid = db.rawQuery(
                "SELECT value FROM sync_state WHERE key = ? LIMIT 1",
                arrayOf("sync_group_uuid"),
            ).use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0).trim() else ""
            }
            // Una cancellazione locale diventa sincronizzabile solo se la
            // galleria appartiene già a un gruppo. Non retro-associamo mai
            // cancellazioni eseguite mentre la galleria era scollegata.
            val normalizedSha256 = record.sha256.trim().lowercase(Locale.ROOT)
            if (createSyncTombstone &&
                syncGroupUuid.isNotBlank() &&
                record.mediaSyncUuid.isNotBlank() &&
                normalizedSha256.length == 64 &&
                normalizedSha256.all { it in '0'..'9' || it in 'a'..'f' }
            ) {
                val tombstone = ContentValues().apply {
                    put("file_uuid", record.mediaSyncUuid)
                    put("sha256", normalizedSha256)
                    put("media_type", record.mediaType)
                    put("last_relative_path", record.originalRelativePath)
                    put("created_locally", 1)
                    put("sync_group_uuid", syncGroupUuid)
                }
                db.insertWithOnConflict(
                    "sync_tombstones",
                    null,
                    tombstone,
                    SQLiteDatabase.CONFLICT_IGNORE,
                )
            }
            val operation = ContentValues().apply {
                put("operation_type", "permanent_delete")
                put("source_relative_path", record.trashRelativePath)
                put("destination_relative_path", "")
                put("created_at_epoch_ms", System.currentTimeMillis())
            }
            db.insertOrThrow("operations", null, operation)
            db.delete("media", "sync_uuid = ?", arrayOf(record.mediaSyncUuid))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun characterById(id: Long): CharacterRecord? {
        readableDatabase.rawQuery(
            """
            SELECT c.id, c.sync_uuid, c.franchise_id, c.name, c.relative_path,
                   f.name, f.code, f.relative_path
            FROM characters c
            JOIN franchises f ON f.id = c.franchise_id
            WHERE c.id = ?
            LIMIT 1
            """.trimIndent(),
            arrayOf(id.toString()),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return null
            return CharacterRecord(
                id = cursor.getLong(0),
                syncUuid = cursor.getString(1),
                franchiseId = cursor.getLong(2),
                name = cursor.getString(3),
                relativePath = cursor.getString(4),
                franchiseName = cursor.getString(5),
                franchiseCode = cursor.getString(6),
                franchiseRelativePath = cursor.getString(7),
            )
        }
    }

    private fun insertFranchise(
        db: SQLiteDatabase,
        name: String,
        code: String,
        relativePath: String,
    ): FranchiseRecord {
        val now = System.currentTimeMillis()
        val syncUuid = UUID.randomUUID().toString()
        val values = ContentValues().apply {
            put("sync_uuid", syncUuid)
            put("name", name)
            put("code", code)
            put("relative_path", relativePath)
            put("is_active", 1)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        val id = db.insertOrThrow("franchises", null, values)
        return FranchiseRecord(id, syncUuid, name, code, relativePath)
    }

    private fun insertCharacter(
        db: SQLiteDatabase,
        franchiseId: Long,
        name: String,
        relativePath: String,
    ): CharacterRecord {
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString())
            put("franchise_id", franchiseId)
            put("name", name)
            put("relative_path", relativePath)
            put("is_active", 1)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        val id = db.insertOrThrow("characters", null, values)
        return characterById(id)
            ?: throw IllegalStateException("Personaggio non leggibile dopo la creazione.")
    }

    private fun uniqueFranchiseCode(db: SQLiteDatabase, requested: String): String {
        val base = requested.uppercase(Locale.ROOT).filter { it in 'A'..'Z' || it in '0'..'9' }
            .take(10)
            .ifBlank { "FR" }
        fun exists(candidate: String): Boolean {
            db.rawQuery(
                "SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE LIMIT 1",
                arrayOf(candidate),
            ).use { return it.moveToFirst() }
        }
        if (!exists(base)) return base
        var number = 1
        while (true) {
            val suffix = number.toString().padStart(2, '0')
            val prefix = base.take((10 - suffix.length).coerceAtLeast(1))
            val candidate = "$prefix$suffix"
            if (!exists(candidate)) return candidate
            number += 1
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

    private fun normalizeMetadataName(value: String): String {
        return value.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.joinToString(" ")
    }

    private class MutableBrowseCollection(
        val name: String,
        val relativePath: String,
        val kind: String,
        var mediaCount: Int = 0,
        var coverSyncUuid: String = "",
    )

    private fun browseCollectionToMap(value: MutableBrowseCollection): Map<String, Any> {
        return mapOf(
            "name" to value.name,
            "relativePath" to value.relativePath,
            "kind" to value.kind,
            "mediaCount" to value.mediaCount,
            "coverSyncUuid" to value.coverSyncUuid,
        )
    }

    private fun escapeLike(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")
    }

    private fun readTrashedMediaUuids(db: SQLiteDatabase): Set<String> {
        val values = hashSetOf<String>()
        db.rawQuery("SELECT media_sync_uuid FROM trash_items", null).use { cursor ->
            while (cursor.moveToNext()) values += cursor.getString(0)
        }
        return values
    }

    private fun readAllRows(db: SQLiteDatabase): List<MediaDatabaseRow> {
        val rows = mutableListOf<MediaDatabaseRow>()
        db.rawQuery(
            """
            SELECT sync_uuid, relative_path, filename, extension, media_type,
                   is_animated, mime_type, size_bytes, modified_epoch_ms,
                   document_uri, document_id, sha256, is_present
            FROM media
            """.trimIndent(),
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                rows += MediaDatabaseRow(
                    syncUuid = cursor.getString(0),
                    relativePath = cursor.getString(1),
                    filename = cursor.getString(2),
                    extension = cursor.getString(3),
                    mediaType = cursor.getString(4),
                    isAnimated = cursor.getInt(5) != 0,
                    mimeType = cursor.getString(6),
                    sizeBytes = cursor.getLong(7),
                    modifiedEpochMs = cursor.getLong(8),
                    documentUri = cursor.getString(9),
                    documentId = cursor.getString(10),
                    sha256 = cursor.getString(11),
                    isPresent = cursor.getInt(12) != 0,
                )
            }
        }
        return rows
    }

    private fun insertDocument(
        db: SQLiteDatabase,
        syncUuid: String,
        document: IndexedMediaDocument,
        now: Long,
    ) {
        val values = documentValues(document, now).apply {
            put("sync_uuid", syncUuid)
            put("created_at_epoch_ms", now)
        }
        db.insertOrThrow("media", null, values)
    }

    private fun updateDocument(
        db: SQLiteDatabase,
        syncUuid: String,
        document: IndexedMediaDocument,
        now: Long,
    ) {
        db.update(
            "media",
            documentValues(document, now),
            "sync_uuid = ?",
            arrayOf(syncUuid),
        )
    }

    private fun documentValues(document: IndexedMediaDocument, now: Long) =
        ContentValues().apply {
            put("relative_path", document.relativePath)
            put("filename", document.filename)
            put("extension", document.extension)
            put("media_type", document.mediaType)
            put("is_animated", if (document.isAnimated) 1 else 0)
            put("mime_type", document.mimeType)
            put("size_bytes", document.sizeBytes)
            put("modified_epoch_ms", document.modifiedEpochMs)
            put("document_uri", document.documentUri)
            put("document_id", document.documentId)
            put("sha256", document.sha256)
            put("is_present", 1)
            put("updated_at_epoch_ms", now)
        }

    private fun columnNames(db: SQLiteDatabase, table: String): Set<String> {
        val values = mutableSetOf<String>()
        db.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val nameColumn = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) values += cursor.getString(nameColumn)
        }
        return values
    }
}
