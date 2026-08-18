package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import java.security.MessageDigest
import java.util.Locale

internal class GalleryTrashRepository(private val context: Context) {
    companion object {
        private const val TRASH_FOLDER = ".trash"
    }

    private data class ChildEntry(
        val uri: Uri,
        val documentId: String,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
    )

    @Synchronized
    fun moveToTrash(galleryUuid: String, treeUri: Uri, syncUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            reconcileMissing(database)
            val source = database.trashSource(syncUuid)
                ?: throw IllegalStateException("Il media non è più disponibile nella Gallery.")
            val sourceUri = Uri.parse(source.documentUri)
            if (!documentExists(sourceUri)) {
                throw IllegalStateException("Il file non è più disponibile nella posizione indicizzata.")
            }

            val root = rootDocumentUri(treeUri)
            val trashRoot = ensureDirectory(root, TRASH_FOLDER)
            val originalParentPath = source.relativePath.substringBeforeLast('/', "")
            val trashParent = ensurePath(trashRoot, originalParentPath)
            val targetName = uniqueFilename(trashParent, source.filename)
            val targetRelativePath = joinRelative(TRASH_FOLDER, joinRelative(originalParentPath, targetName))
            val mimeType = source.mimeType.ifBlank { mimeTypeForExtension(source.extension) }

            val target = DocumentsContract.createDocument(
                context.contentResolver,
                trashParent,
                mimeType,
                targetName,
            ) ?: throw IllegalStateException("Android non ha creato il file nel cestino.")

            var sourceDeleted = false
            var recorded = false
            try {
                copyDocument(sourceUri, target)
                val copiedSha = calculateSha256(target)
                if (!copiedSha.equals(source.sha256, ignoreCase = true)) {
                    throw IllegalStateException("La verifica SHA-256 della copia nel cestino non è riuscita.")
                }
                if (!DocumentsContract.deleteDocument(context.contentResolver, sourceUri)) {
                    throw IllegalStateException("Android non ha rimosso il file dalla posizione originale.")
                }
                sourceDeleted = true

                val metadata = queryDocument(target)
                database.markTrashed(
                    mediaSyncUuid = source.syncUuid,
                    originalRelativePath = source.relativePath,
                    trashRelativePath = targetRelativePath,
                    trashDocumentUri = target.toString(),
                    trashDocumentId = DocumentsContract.getDocumentId(target),
                    trashFilename = targetName,
                    sizeBytes = metadata?.sizeBytes?.coerceAtLeast(0L) ?: source.sizeBytes,
                    modifiedEpochMs = metadata?.modifiedEpochMs?.coerceAtLeast(0L)
                        ?: System.currentTimeMillis(),
                )
                recorded = true
                return mapOf(
                    "status" to "trashed",
                    "syncUuid" to source.syncUuid,
                    "originalRelativePath" to source.relativePath,
                    "trashRelativePath" to targetRelativePath,
                )
            } catch (error: Exception) {
                if (recorded) {
                    try {
                        database.rollbackTrash(source.syncUuid)
                    } catch (_: Exception) {
                        // Continua con il recupero fisico del file.
                    }
                }
                if (sourceDeleted) {
                    try {
                        val originalParent = ensurePath(root, originalParentPath)
                        val restored = DocumentsContract.createDocument(
                            context.contentResolver,
                            originalParent,
                            mimeType,
                            source.filename,
                        )
                        if (restored != null) {
                            copyDocument(target, restored)
                            if (calculateSha256(restored).equals(source.sha256, ignoreCase = true)) {
                                DocumentsContract.deleteDocument(context.contentResolver, target)
                            }
                        }
                    } catch (_: Exception) {
                        // Conserva almeno la copia nel cestino in caso di rollback incompleto.
                    }
                } else {
                    try {
                        DocumentsContract.deleteDocument(context.contentResolver, target)
                    } catch (_: Exception) {
                        // Non nascondere l'errore originale.
                    }
                }
                throw error
            }
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun stats(galleryUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            reconcileMissing(database)
            database.trashStats()
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun listItems(galleryUuid: String, limit: Int, offset: Int): List<Map<String, Any>> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            reconcileMissing(database)
            database.listTrashItems(limit, offset)
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun restore(
        galleryUuid: String,
        treeUri: Uri,
        trashId: Long,
        autoRename: Boolean,
    ): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            reconcileMissing(database)
            val record = database.trashRecord(trashId)
                ?: throw IllegalStateException("Elemento del cestino non più disponibile.")
            val source = Uri.parse(record.trashDocumentUri)
            if (!documentExists(source)) {
                database.permanentlyDeleteTrash(trashId)
                throw IllegalStateException("Il file nel cestino non esiste più ed è stato registrato come eliminato.")
            }

            val root = rootDocumentUri(treeUri)
            val requestedParentPath = record.originalRelativePath.substringBeforeLast('/', "")
            val requestedName = record.originalRelativePath.substringAfterLast('/')
            val parent = ensurePath(root, requestedParentPath)
            var targetName = requestedName
            val conflict = findChild(parent, targetName)
            if (conflict != null) {
                if (!autoRename) {
                    return mapOf(
                        "status" to "conflict",
                        "relativePath" to record.originalRelativePath,
                        "renamed" to false,
                    )
                }
                targetName = uniqueRestoredFilename(parent, requestedName)
            }

            val mimeType = record.mimeType.ifBlank { mimeTypeForExtension(record.extension) }
            val destination = DocumentsContract.createDocument(
                context.contentResolver,
                parent,
                mimeType,
                targetName,
            ) ?: throw IllegalStateException("Android non ha creato il file da ripristinare.")
            var sourceDeleted = false
            try {
                copyDocument(source, destination)
                val copiedSha = calculateSha256(destination)
                if (!copiedSha.equals(record.sha256, ignoreCase = true)) {
                    throw IllegalStateException("La verifica SHA-256 del ripristino non è riuscita.")
                }
                if (!DocumentsContract.deleteDocument(context.contentResolver, source)) {
                    throw IllegalStateException("Android non ha rimosso la copia dal cestino.")
                }
                sourceDeleted = true

                val metadata = queryDocument(destination)
                val relativePath = joinRelative(requestedParentPath, targetName)
                database.restoreTrash(
                    trashId = trashId,
                    relativePath = relativePath,
                    filename = targetName,
                    documentUri = destination.toString(),
                    documentId = DocumentsContract.getDocumentId(destination),
                    sizeBytes = metadata?.sizeBytes?.coerceAtLeast(0L) ?: record.sizeBytes,
                    modifiedEpochMs = metadata?.modifiedEpochMs?.coerceAtLeast(0L)
                        ?: System.currentTimeMillis(),
                )
                return mapOf(
                    "status" to "restored",
                    "relativePath" to relativePath,
                    "renamed" to (targetName != requestedName),
                )
            } catch (error: Exception) {
                if (sourceDeleted) {
                    try {
                        val trashParentPath = record.trashRelativePath
                            .removePrefix("$TRASH_FOLDER/")
                            .substringBeforeLast('/', "")
                        val trashRoot = ensureDirectory(root, TRASH_FOLDER)
                        val trashParent = ensurePath(trashRoot, trashParentPath)
                        val restoredTrash = DocumentsContract.createDocument(
                            context.contentResolver,
                            trashParent,
                            mimeType,
                            record.trashFilename,
                        )
                        if (restoredTrash != null) {
                            copyDocument(destination, restoredTrash)
                            if (calculateSha256(restoredTrash).equals(record.sha256, true)) {
                                DocumentsContract.deleteDocument(context.contentResolver, destination)
                            }
                        }
                    } catch (_: Exception) {
                        // Conserva la copia disponibile; la scansione successiva potrà riconciliarla.
                    }
                } else {
                    try {
                        DocumentsContract.deleteDocument(context.contentResolver, destination)
                    } catch (_: Exception) {
                        // Non nascondere l'errore originale.
                    }
                }
                throw error
            }
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun permanentlyDelete(galleryUuid: String, trashId: Long): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val record = database.trashRecord(trashId)
                ?: return mapOf("deleted" to false)
            val uri = Uri.parse(record.trashDocumentUri)
            if (documentExists(uri)) {
                if (!DocumentsContract.deleteDocument(context.contentResolver, uri)) {
                    throw IllegalStateException("Android non ha eliminato definitivamente il file.")
                }
            }
            database.permanentlyDeleteTrash(trashId)
            return mapOf("deleted" to true)
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun emptyTrash(galleryUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        var deleted = 0
        val errors = mutableListOf<Map<String, String>>()
        try {
            reconcileMissing(database)
            val records = database.allTrashRecords()
            for (record in records) {
                try {
                    val uri = Uri.parse(record.trashDocumentUri)
                    if (documentExists(uri) &&
                        !DocumentsContract.deleteDocument(context.contentResolver, uri)
                    ) {
                        throw IllegalStateException("Android non ha eliminato il file.")
                    }
                    database.permanentlyDeleteTrash(record.trashId)
                    deleted += 1
                } catch (error: Exception) {
                    errors += mapOf(
                        "relativePath" to record.trashRelativePath,
                        "message" to safeMessage(error),
                    )
                }
            }
            return mapOf(
                "deleted" to deleted,
                "errors" to errors,
            )
        } finally {
            database.close()
        }
    }

    fun mediaForThumbnail(galleryUuid: String, syncUuid: String): Pair<String, String>? {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.trashMediaForThumbnail(syncUuid)
        } finally {
            database.close()
        }
    }

    fun mediaForViewer(galleryUuid: String, syncUuid: String): ViewerMediaRecord? {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            database.trashMediaForViewer(syncUuid)
        } finally {
            database.close()
        }
    }

    private fun reconcileMissing(database: GalleryIndexDatabase) {
        for (record in database.allTrashRecords()) {
            if (!documentExists(Uri.parse(record.trashDocumentUri))) {
                database.permanentlyDeleteTrash(record.trashId)
            }
        }
    }

    private fun rootDocumentUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun ensurePath(root: Uri, relativePath: String): Uri {
        if (relativePath.isBlank()) return root
        var current = root
        for (component in relativePath.split('/').filter { it.isNotBlank() }) {
            current = ensureDirectory(current, component)
        }
        return current
    }

    private fun ensureDirectory(parent: Uri, name: String): Uri {
        val existing = findChild(parent, name)
        if (existing != null) {
            if (existing.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IllegalStateException("Esiste già un file chiamato $name.")
            }
            return existing.uri
        }
        return DocumentsContract.createDocument(
            context.contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IllegalStateException("Android non ha creato la cartella $name.")
    }

    private fun findChild(parent: Uri, name: String): ChildEntry? =
        queryChildren(parent).firstOrNull { it.displayName.equals(name, ignoreCase = true) }

    private fun queryChildren(parent: Uri): List<ChildEntry> {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val values = mutableListOf<ChildEntry>()
        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val name = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mime = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val size = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modified = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(id) ?: continue
                values += ChildEntry(
                    uri = DocumentsContract.buildDocumentUriUsingTree(parent, documentId),
                    documentId = documentId,
                    displayName = cursor.getString(name).orEmpty(),
                    mimeType = cursor.getString(mime).orEmpty(),
                    sizeBytes = if (size >= 0 && !cursor.isNull(size)) cursor.getLong(size) else 0L,
                    modifiedEpochMs = if (modified >= 0 && !cursor.isNull(modified)) {
                        cursor.getLong(modified)
                    } else {
                        0L
                    },
                )
            }
        } ?: throw IllegalStateException("Android non consente di leggere una cartella della galleria.")
        return values
    }

    private fun queryDocument(uri: Uri): ChildEntry? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val name = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mime = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val size = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modified = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            return ChildEntry(
                uri = uri,
                documentId = cursor.getString(id).orEmpty(),
                displayName = cursor.getString(name).orEmpty(),
                mimeType = cursor.getString(mime).orEmpty(),
                sizeBytes = if (size >= 0 && !cursor.isNull(size)) cursor.getLong(size) else 0L,
                modifiedEpochMs = if (modified >= 0 && !cursor.isNull(modified)) cursor.getLong(modified) else 0L,
            )
        }
        return null
    }

    private fun uniqueFilename(parent: Uri, requested: String): String {
        if (findChild(parent, requested) == null) return requested
        val stem = requested.substringBeforeLast('.', requested)
        val extension = requested.substringAfterLast('.', "")
        var counter = 1
        while (counter < 10000) {
            val suffix = "_trashed_${counter.toString().padStart(3, '0')}"
            val candidate = if (extension.isBlank()) "$stem$suffix" else "$stem$suffix.$extension"
            if (findChild(parent, candidate) == null) return candidate
            counter += 1
        }
        throw IllegalStateException("Impossibile trovare un nome libero nel cestino.")
    }

    private fun uniqueRestoredFilename(parent: Uri, requested: String): String {
        val stem = requested.substringBeforeLast('.', requested)
        val extension = requested.substringAfterLast('.', "")
        var counter = 1
        while (counter < 10000) {
            val suffix = "_restored_${counter.toString().padStart(3, '0')}"
            val candidate = if (extension.isBlank()) "$stem$suffix" else "$stem$suffix.$extension"
            if (findChild(parent, candidate) == null) return candidate
            counter += 1
        }
        throw IllegalStateException("Impossibile trovare un nome libero per il ripristino.")
    }

    private fun copyDocument(source: Uri, destination: Uri) {
        context.contentResolver.openInputStream(source)?.use { input ->
            context.contentResolver.openOutputStream(destination, "w")?.use { output ->
                input.copyTo(output)
            } ?: throw IllegalStateException("Android non consente di scrivere il file.")
        } ?: throw IllegalStateException("Android non consente di leggere il file.")
    }

    private fun calculateSha256(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        context.contentResolver.openInputStream(uri)?.use { input ->
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        } ?: throw IllegalStateException("Android non consente di leggere il file.")
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun documentExists(uri: Uri): Boolean {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { it.moveToFirst() } == true
        } catch (_: Exception) {
            false
        }
    }

    private fun mimeTypeForExtension(extension: String): String {
        return MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension.lowercase(Locale.ROOT))
            ?: "application/octet-stream"
    }

    private fun joinRelative(prefix: String, name: String): String {
        if (prefix.isBlank()) return name
        if (name.isBlank()) return prefix
        return "$prefix/$name"
    }

    private fun safeMessage(error: Exception): String =
        error.message?.takeIf { it.isNotBlank() }
            ?: "Operazione non riuscita (${error.javaClass.simpleName})."
}
