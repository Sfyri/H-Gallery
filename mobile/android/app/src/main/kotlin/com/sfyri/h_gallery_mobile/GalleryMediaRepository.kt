package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.security.MessageDigest
import java.util.Locale

internal class GalleryMediaRepository(private val context: Context) {
    companion object {
        private val IMAGE_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff",
        )
        private val VIDEO_EXTENSIONS = setOf(
            "mp4", "mkv", "webm", "avi", "mov", "m4v",
        )
        private val ROOT_EXCLUDED_DIRECTORIES = setOf(".user", ".todo", ".trash")
    }

    private data class DirectoryNode(
        val uri: Uri,
        val relativePrefix: String,
        val isRoot: Boolean,
    )

    private data class ChildEntry(
        val documentId: String,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
        val uri: Uri,
    )

    fun scanGallery(galleryUuid: String, treeUri: Uri): Map<String, Any> {
        val startedAt = System.currentTimeMillis()
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val scanned = scanDocuments(treeUri)
            val changes = database.reconcile(scanned)
            val stats = database.stats().toMutableMap()
            stats["added"] = changes.added
            stats["updated"] = changes.updated
            stats["moved"] = changes.moved
            stats["removed"] = changes.removed
            stats["durationMs"] = System.currentTimeMillis() - startedAt
            return stats
        } finally {
            database.close()
        }
    }

    fun stats(galleryUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.stats()
        } finally {
            database.close()
        }
    }

    fun listMedia(galleryUuid: String, limit: Int, offset: Int): List<Map<String, Any>> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.listMedia(limit, offset)
        } finally {
            database.close()
        }
    }

    fun mediaForThumbnail(galleryUuid: String, syncUuid: String): Pair<String, String>? {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.mediaForThumbnail(syncUuid)
        } finally {
            database.close()
        }
    }

    fun mediaForViewer(galleryUuid: String, syncUuid: String): ViewerMediaRecord? {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.mediaForViewer(syncUuid)
        } finally {
            database.close()
        }
    }

    private fun scanDocuments(treeUri: Uri): List<IndexedMediaDocument> {
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocumentId)
        val stack = ArrayDeque<DirectoryNode>()
        stack.add(DirectoryNode(rootUri, "", true))
        val media = mutableListOf<IndexedMediaDocument>()

        while (stack.isNotEmpty()) {
            val directory = stack.removeLast()
            for (child in queryChildren(directory.uri)) {
                if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (directory.isRoot && child.displayName.lowercase(Locale.ROOT) in ROOT_EXCLUDED_DIRECTORIES) {
                        continue
                    }
                    val prefix = joinRelative(directory.relativePrefix, child.displayName)
                    stack.add(DirectoryNode(child.uri, prefix, false))
                    continue
                }

                val extension = child.displayName
                    .substringAfterLast('.', missingDelimiterValue = "")
                    .lowercase(Locale.ROOT)
                val mediaType = when (extension) {
                    in IMAGE_EXTENSIONS -> "image"
                    in VIDEO_EXTENSIONS -> "video"
                    else -> null
                } ?: continue

                val relativePath = joinRelative(directory.relativePrefix, child.displayName)
                val sha256 = calculateSha256(child.uri)
                media += IndexedMediaDocument(
                    relativePath = relativePath,
                    filename = child.displayName,
                    extension = extension,
                    mediaType = mediaType,
                    isAnimated = mediaType == "image" && extension == "gif",
                    mimeType = child.mimeType.takeUnless {
                        it == "application/octet-stream"
                    }.orEmpty(),
                    sizeBytes = child.sizeBytes.coerceAtLeast(0L),
                    modifiedEpochMs = child.modifiedEpochMs.coerceAtLeast(0L),
                    documentUri = child.uri.toString(),
                    documentId = child.documentId,
                    sha256 = sha256,
                )
            }
        }

        return media.sortedBy { it.relativePath.lowercase(Locale.ROOT) }
    }

    private fun queryChildren(parent: Uri): List<ChildEntry> {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            parentDocumentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val children = mutableListOf<ChildEntry>()

        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            val sizeColumn = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_SIZE,
            )
            val modifiedColumn = cursor.getColumnIndex(
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )

            while (cursor.moveToNext()) {
                val documentId = cursor.getString(idColumn) ?: continue
                val displayName = cursor.getString(nameColumn)?.trim().orEmpty()
                if (displayName.isEmpty()) continue
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    parent,
                    documentId,
                )
                children += ChildEntry(
                    documentId = documentId,
                    displayName = displayName,
                    mimeType = cursor.getString(mimeColumn).orEmpty(),
                    sizeBytes = if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                        cursor.getLong(sizeColumn)
                    } else {
                        0L
                    },
                    modifiedEpochMs = if (modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)) {
                        cursor.getLong(modifiedColumn)
                    } else {
                        0L
                    },
                    uri = documentUri,
                )
            }
        } ?: throw IllegalStateException(
            "Android non consente di leggere una delle cartelle della galleria.",
        )
        return children
    }

    private fun calculateSha256(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        context.contentResolver.openInputStream(uri)?.use { stream ->
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        } ?: throw IllegalStateException("Impossibile leggere il file: $uri")
        return digest.digest().joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private fun joinRelative(prefix: String, name: String): String {
        return if (prefix.isBlank()) name else "$prefix/$name"
    }
}
