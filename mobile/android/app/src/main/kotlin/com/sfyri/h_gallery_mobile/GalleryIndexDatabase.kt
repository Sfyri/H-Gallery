package com.sfyri.h_gallery_mobile

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
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
        private const val DATABASE_VERSION = 1
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
                created_at_epoch_ms INTEGER NOT NULL,
                updated_at_epoch_ms INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE UNIQUE INDEX idx_media_present_unique_path " +
                "ON media(relative_path) WHERE is_present = 1",
        )
        db.execSQL("CREATE INDEX idx_media_present_path ON media(is_present, relative_path)")
        db.execSQL("CREATE INDEX idx_media_sha256 ON media(sha256)")
        db.execSQL("CREATE INDEX idx_media_document_id ON media(document_id)")
        db.execSQL("CREATE INDEX idx_media_type ON media(is_present, media_type, is_animated)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Prima versione dello schema Android. Le migrazioni future verranno
        // aggiunte qui senza distruggere gli UUID persistenti dei media.
    }

    fun reconcile(scanned: List<IndexedMediaDocument>): ReconcileResult {
        val db = writableDatabase
        val existing = readAllRows(db)
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
                            it.syncUuid !in claimedUuids && it.relativePath !in scannedPaths
                        }
                    if (documentCandidates.size == 1) {
                        matched = documentCandidates.single()
                    }
                }

                if (matched == null) {
                    val hashCandidates = byHash[document.sha256]
                        .orEmpty()
                        .filter {
                            it.syncUuid !in claimedUuids && it.relativePath !in scannedPaths
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
            val syncColumn = cursor.getColumnIndexOrThrow("sync_uuid")
            val pathColumn = cursor.getColumnIndexOrThrow("relative_path")
            val filenameColumn = cursor.getColumnIndexOrThrow("filename")
            val extensionColumn = cursor.getColumnIndexOrThrow("extension")
            val typeColumn = cursor.getColumnIndexOrThrow("media_type")
            val animatedColumn = cursor.getColumnIndexOrThrow("is_animated")
            val mimeColumn = cursor.getColumnIndexOrThrow("mime_type")
            val sizeColumn = cursor.getColumnIndexOrThrow("size_bytes")
            val modifiedColumn = cursor.getColumnIndexOrThrow("modified_epoch_ms")
            val shaColumn = cursor.getColumnIndexOrThrow("sha256")
            while (cursor.moveToNext()) {
                rows += mapOf(
                    "syncUuid" to cursor.getString(syncColumn),
                    "relativePath" to cursor.getString(pathColumn),
                    "filename" to cursor.getString(filenameColumn),
                    "extension" to cursor.getString(extensionColumn),
                    "mediaType" to cursor.getString(typeColumn),
                    "isAnimated" to (cursor.getInt(animatedColumn) != 0),
                    "mimeType" to cursor.getString(mimeColumn),
                    "sizeBytes" to cursor.getLong(sizeColumn),
                    "modifiedEpochMs" to cursor.getLong(modifiedColumn),
                    "sha256" to cursor.getString(shaColumn),
                )
            }
        }
        return rows
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
}
