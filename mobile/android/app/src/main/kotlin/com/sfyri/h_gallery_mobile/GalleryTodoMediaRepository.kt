package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.util.Locale

internal class GalleryTodoMediaRepository(private val context: Context) {
    companion object {
        private val IMAGE_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff",
        )
        private val VIDEO_EXTENSIONS = setOf(
            "mp4", "mkv", "webm", "avi", "mov", "m4v",
        )
    }

    private data class DirectoryNode(
        val uri: Uri,
        val relativePrefix: String,
    )

    private data class ChildEntry(
        val documentId: String,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
        val uri: Uri,
    )

    private data class TodoEntry(
        val relativePath: String,
        val filename: String,
        val extension: String,
        val mediaType: String,
        val isAnimated: Boolean,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
        val uri: Uri,
        val parentUri: Uri,
    ) {
        fun toPlatformMap(): Map<String, Any> {
            return mapOf(
                "syncUuid" to TodoMediaToken.encode(
                    mediaType = mediaType,
                    extension = extension,
                    modifiedEpochMs = modifiedEpochMs,
                    uri = uri,
                    parentUri = parentUri,
                    relativePath = relativePath,
                ),
                "relativePath" to relativePath,
                "filename" to filename,
                "extension" to extension,
                "mediaType" to mediaType,
                "isAnimated" to isAnimated,
                "mimeType" to mimeType,
                "sizeBytes" to sizeBytes,
                "modifiedEpochMs" to modifiedEpochMs,
                "sha256" to "",
            )
        }
    }

    fun stats(treeUri: Uri): Map<String, Any> {
        val entries = scanTodo(treeUri)
        val animated = entries.count { it.isAnimated }
        val videos = entries.count { it.mediaType == "video" }
        val photos = entries.size - animated - videos
        return mapOf(
            "total" to entries.size,
            "photos" to photos.coerceAtLeast(0),
            "animated" to animated,
            "videos" to videos,
        )
    }

    fun listMedia(treeUri: Uri, limit: Int, offset: Int): List<Map<String, Any>> {
        val safeLimit = limit.coerceIn(1, 2000)
        val safeOffset = offset.coerceAtLeast(0)
        return scanTodo(treeUri)
            .drop(safeOffset)
            .take(safeLimit)
            .map(TodoEntry::toPlatformMap)
    }

    private fun scanTodo(treeUri: Uri): List<TodoEntry> {
        val todoRoot = findTodoRoot(treeUri) ?: return emptyList()
        val stack = ArrayDeque<DirectoryNode>()
        stack.add(DirectoryNode(todoRoot, ".toDo"))
        val media = mutableListOf<TodoEntry>()

        while (stack.isNotEmpty()) {
            val directory = stack.removeLast()
            for (child in queryChildren(directory.uri)) {
                if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    stack.add(
                        DirectoryNode(
                            uri = child.uri,
                            relativePrefix = joinRelative(
                                directory.relativePrefix,
                                child.displayName,
                            ),
                        ),
                    )
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

                media += TodoEntry(
                    relativePath = joinRelative(directory.relativePrefix, child.displayName),
                    filename = child.displayName,
                    extension = extension,
                    mediaType = mediaType,
                    isAnimated = mediaType == "image" && extension == "gif",
                    mimeType = child.mimeType.takeUnless {
                        it == "application/octet-stream"
                    }.orEmpty(),
                    sizeBytes = child.sizeBytes.coerceAtLeast(0L),
                    modifiedEpochMs = child.modifiedEpochMs.coerceAtLeast(0L),
                    uri = child.uri,
                    parentUri = directory.uri,
                )
            }
        }

        return media.sortedBy { it.relativePath.lowercase(Locale.ROOT) }
    }

    private fun findTodoRoot(treeUri: Uri): Uri? {
        val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocumentId)
        return queryChildren(rootUri)
            .firstOrNull {
                it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR &&
                    it.displayName.equals(".toDo", ignoreCase = true)
            }
            ?.uri
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
            val sizeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
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
        } ?: throw IllegalStateException("Android non consente di leggere la cartella .toDo.")

        return children
    }

    private fun joinRelative(prefix: String, name: String): String {
        return if (prefix.isBlank()) name else "$prefix/$name"
    }
}
