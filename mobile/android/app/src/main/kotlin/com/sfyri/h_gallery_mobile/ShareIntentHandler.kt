package com.sfyri.h_gallery_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

internal class ShareIntentHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val resolveGalleryTreeUri: (String) -> Uri?,
) {
    companion object {
        private const val CHANNEL = "com.sfyri.h_gallery_mobile/share"
        private const val DELETE_ORIGINALS_REQUEST = 41022
        private const val MAX_SHARE_ITEMS = 2000
        private const val DELETE_REQUEST_CHUNK_SIZE = 500

        private val IMAGE_EXTENSIONS = setOf(
            "jpg", "jpeg", "png", "webp", "gif", "bmp", "tif", "tiff",
        )
        private val VIDEO_EXTENSIONS = setOf(
            "mp4", "mkv", "webm", "avi", "mov", "m4v",
        )
        private val SUPPORTED_EXTENSIONS = IMAGE_EXTENSIONS + VIDEO_EXTENSIONS
    }

    private data class SharedEntry(
        val uri: Uri,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
    )

    private data class PendingBatch(
        val token: String,
        val entries: List<SharedEntry>,
        val rejectedCount: Int,
        val receivedAtEpochMs: Long,
    )

    private data class CopyFailure(
        val entry: SharedEntry,
        val message: String,
    )

    private data class DeletePreparation(
        val directlyDeleted: Int,
        val promptUris: List<Uri>,
        val notDeletable: Int,
    )

    private data class PendingDeleteOperation(
        val result: MethodChannel.Result,
        val response: MutableMap<String, Any>,
        val chunks: ArrayDeque<List<Uri>>,
        var deletedByPrompt: Int = 0,
        var notDeleted: Int = 0,
        var currentChunkSize: Int = 0,
        var confirmationShown: Boolean = false,
    )

    private val resolver = activity.contentResolver
    private val executor = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var pendingBatch: PendingBatch? = null
    private var pendingDelete: PendingDeleteOperation? = null

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
        synchronized(lock) {
            pendingDelete = null
            pendingBatch = null
        }
    }

    fun acceptIntent(intent: Intent?): Boolean {
        val value = intent ?: return false
        if (value.action != Intent.ACTION_SEND && value.action != Intent.ACTION_SEND_MULTIPLE) {
            return false
        }

        val uris = extractUris(value)
        if (uris.isEmpty()) return false

        val limitedUris = uris.take(MAX_SHARE_ITEMS)
        val entries = limitedUris.mapNotNull(::readSharedEntry)
        val rejected = (uris.size - limitedUris.size) + (limitedUris.size - entries.size)
        val batch = PendingBatch(
            token = UUID.randomUUID().toString(),
            entries = entries,
            rejectedCount = rejected,
            receivedAtEpochMs = System.currentTimeMillis(),
        )

        synchronized(lock) {
            pendingBatch = batch
        }
        activity.runOnUiThread {
            channel.invokeMethod("sharedMediaReceived", batchToPlatformMap(batch))
        }
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != DELETE_ORIGINALS_REQUEST) return false

        val operation = synchronized(lock) { pendingDelete } ?: return true
        if (resultCode == Activity.RESULT_OK) {
            operation.deletedByPrompt += operation.currentChunkSize
            operation.currentChunkSize = 0
            startNextDeletePrompt(operation)
        } else {
            operation.notDeleted += operation.currentChunkSize
            operation.currentChunkSize = 0
            while (operation.chunks.isNotEmpty()) {
                operation.notDeleted += operation.chunks.removeFirst().size
            }
            completeDeleteOperation(operation)
        }
        return true
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPendingShare" -> {
                val batch = synchronized(lock) { pendingBatch }
                result.success(batch?.let(::batchToPlatformMap))
            }

            "clearPendingShare" -> {
                val token = call.argument<String>("token")?.trim().orEmpty()
                synchronized(lock) {
                    if (token.isEmpty() || pendingBatch?.token == token) {
                        pendingBatch = null
                    }
                }
                result.success(null)
            }

            "importPendingShare" -> importPendingShare(call, result)
            else -> result.notImplemented()
        }
    }

    private fun importPendingShare(call: MethodCall, result: MethodChannel.Result) {
        val token = call.argument<String>("token")?.trim().orEmpty()
        val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
        val removeOriginals = call.argument<Boolean>("removeOriginals") ?: false

        if (token.isEmpty()) {
            result.error("INVALID_SHARE", "Condivisione non valida.", null)
            return
        }
        if (galleryUuid.isEmpty()) {
            result.error("INVALID_GALLERY", "Galleria non valida.", null)
            return
        }
        synchronized(lock) {
            if (pendingDelete != null) {
                result.error(
                    "DELETE_ALREADY_PENDING",
                    "È già in corso una richiesta di eliminazione degli originali.",
                    null,
                )
                return
            }
        }

        val batch = synchronized(lock) { pendingBatch }
        if (batch == null || batch.token != token) {
            result.error(
                "STALE_SHARE",
                "È arrivata una nuova condivisione. Ricarica l'elenco dei file ricevuti.",
                null,
            )
            return
        }
        if (batch.entries.isEmpty()) {
            result.error(
                "NO_SUPPORTED_MEDIA",
                "La condivisione non contiene immagini o video supportati da H-Gallery.",
                null,
            )
            return
        }

        val treeUri = resolveGalleryTreeUri(galleryUuid)
        if (treeUri == null) {
            result.error(
                "GALLERY_ACCESS_LOST",
                "H-Gallery non ha più accesso completo alla galleria selezionata.",
                null,
            )
            return
        }

        executor.execute {
            try {
                val todoDirectory = ensureTodoDirectory(treeUri)
                val usedNames = queryChildNames(todoDirectory).toMutableSet()
                val copied = mutableListOf<SharedEntry>()
                val failures = mutableListOf<CopyFailure>()

                for (entry in batch.entries) {
                    try {
                        copyEntry(entry, todoDirectory, usedNames)
                        copied += entry
                    } catch (error: Exception) {
                        failures += CopyFailure(entry, safeMessage(error))
                    }
                }

                synchronized(lock) {
                    if (pendingBatch?.token == batch.token) {
                        pendingBatch = if (failures.isEmpty()) {
                            null
                        } else {
                            PendingBatch(
                                token = UUID.randomUUID().toString(),
                                entries = failures.map { it.entry },
                                rejectedCount = 0,
                                receivedAtEpochMs = batch.receivedAtEpochMs,
                            )
                        }
                    }
                }

                val response = mutableMapOf<String, Any>(
                    "copied" to copied.size,
                    "failed" to failures.size,
                    "failures" to failures.take(20).map {
                        "${it.entry.displayName}: ${it.message}"
                    },
                    "remainingPending" to failures.size,
                    "removeOriginalsRequested" to removeOriginals,
                    "deletedOriginals" to 0,
                    "originalsNotDeleted" to 0,
                    "deleteConfirmationShown" to false,
                )

                if (!removeOriginals || copied.isEmpty()) {
                    activity.runOnUiThread { result.success(response) }
                    return@execute
                }

                val deletion = prepareDeletion(copied)
                response["deletedOriginals"] = deletion.directlyDeleted
                response["originalsNotDeleted"] = deletion.notDeletable

                activity.runOnUiThread {
                    if (deletion.promptUris.isEmpty()) {
                        result.success(response)
                    } else {
                        beginDeletePrompts(
                            result = result,
                            response = response,
                            uris = deletion.promptUris,
                        )
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("SHARE_IMPORT_FAILED", safeMessage(error), null)
                }
            }
        }
    }

    private fun beginDeletePrompts(
        result: MethodChannel.Result,
        response: MutableMap<String, Any>,
        uris: List<Uri>,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            response["originalsNotDeleted"] =
                (response["originalsNotDeleted"] as Int) + uris.size
            result.success(response)
            return
        }

        val chunks = ArrayDeque<List<Uri>>()
        uris.chunked(DELETE_REQUEST_CHUNK_SIZE).forEach(chunks::addLast)
        val operation = PendingDeleteOperation(
            result = result,
            response = response,
            chunks = chunks,
        )
        synchronized(lock) {
            pendingDelete = operation
        }
        startNextDeletePrompt(operation)
    }

    private fun startNextDeletePrompt(operation: PendingDeleteOperation) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            completeDeleteOperation(operation)
            return
        }

        while (operation.chunks.isNotEmpty()) {
            val chunk = operation.chunks.removeFirst()
            try {
                val pendingIntent = MediaStore.createDeleteRequest(resolver, chunk)
                operation.currentChunkSize = chunk.size
                operation.confirmationShown = true
                activity.startIntentSenderForResult(
                    pendingIntent.intentSender,
                    DELETE_ORIGINALS_REQUEST,
                    null,
                    0,
                    0,
                    0,
                )
                return
            } catch (_: Exception) {
                operation.notDeleted += chunk.size
            }
        }
        completeDeleteOperation(operation)
    }

    private fun completeDeleteOperation(operation: PendingDeleteOperation) {
        synchronized(lock) {
            if (pendingDelete === operation) pendingDelete = null
        }
        val alreadyDeleted = operation.response["deletedOriginals"] as Int
        val alreadyNotDeleted = operation.response["originalsNotDeleted"] as Int
        operation.response["deletedOriginals"] = alreadyDeleted + operation.deletedByPrompt
        operation.response["originalsNotDeleted"] = alreadyNotDeleted + operation.notDeleted
        operation.response["deleteConfirmationShown"] = operation.confirmationShown
        operation.result.success(operation.response)
    }

    private fun prepareDeletion(
        copied: List<SharedEntry>,
    ): DeletePreparation {
        var directlyDeleted = 0
        var notDeletable = 0
        val promptUris = mutableListOf<Uri>()

        for (entry in copied) {
            val uri = entry.uri
            if (hasWriteAccess(uri) && deleteDirectly(uri)) {
                directlyDeleted += 1
                continue
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isMediaStoreUri(uri)) {
                promptUris += uri
            } else {
                notDeletable += 1
            }
        }

        return DeletePreparation(
            directlyDeleted = directlyDeleted,
            promptUris = promptUris,
            notDeletable = notDeletable,
        )
    }

    private fun hasWriteAccess(uri: Uri): Boolean {
        return activity.checkUriPermission(
            uri,
            Process.myPid(),
            Process.myUid(),
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun deleteDirectly(uri: Uri): Boolean {
        return try {
            if (DocumentsContract.isDocumentUri(activity, uri)) {
                DocumentsContract.deleteDocument(resolver, uri)
            } else {
                resolver.delete(uri, null, null) > 0
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isMediaStoreUri(uri: Uri): Boolean {
        return uri.scheme.equals("content", ignoreCase = true) &&
            uri.authority.equals(MediaStore.AUTHORITY, ignoreCase = true)
    }

    private fun copyEntry(
        entry: SharedEntry,
        todoDirectory: Uri,
        usedNames: MutableSet<String>,
    ) {
        val targetName = uniqueName(entry.displayName, usedNames)
        val targetUri = DocumentsContract.createDocument(
            resolver,
            todoDirectory,
            entry.mimeType.ifBlank { "application/octet-stream" },
            targetName,
        ) ?: throw IllegalStateException("Impossibile creare $targetName in .toDo.")

        try {
            val copiedBytes = resolver.openInputStream(entry.uri)?.use { input ->
                resolver.openOutputStream(targetUri, "w")?.use { output ->
                    input.copyTo(output)
                } ?: throw IllegalStateException("Impossibile scrivere $targetName.")
            } ?: throw IllegalStateException("Impossibile leggere ${entry.displayName}.")

            if (copiedBytes <= 0L) {
                throw IllegalStateException("Il file ricevuto è vuoto.")
            }
            val targetSize = queryDocumentSize(targetUri)
            if (targetSize > 0L && targetSize != copiedBytes) {
                throw IllegalStateException(
                    "Verifica della copia non riuscita (${targetSize} B su ${copiedBytes} B scritti).",
                )
            }
            usedNames += targetName.lowercase(Locale.ROOT)
        } catch (error: Exception) {
            try {
                DocumentsContract.deleteDocument(resolver, targetUri)
            } catch (_: Exception) {
                // La copia incompleta viene rimossa quando il provider lo consente.
            }
            throw error
        }
    }

    private fun queryDocumentSize(uri: Uri): Long {
        return try {
            resolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    cursor.getLong(0).coerceAtLeast(0L)
                } else {
                    0L
                }
            } ?: 0L
        } catch (_: Exception) {
            0L
        }
    }

    private fun ensureTodoDirectory(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        val root = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        findDirectory(root, ".toDo")?.let { return it }
        return DocumentsContract.createDocument(
            resolver,
            root,
            DocumentsContract.Document.MIME_TYPE_DIR,
            ".toDo",
        ) ?: throw IllegalStateException("Impossibile creare la cartella .toDo.")
    }

    private fun findDirectory(parent: Uri, name: String): Uri? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            )
            val nameColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
            val mimeColumn = cursor.getColumnIndexOrThrow(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
            while (cursor.moveToNext()) {
                if (!cursor.getString(nameColumn).equals(name, ignoreCase = true)) continue
                if (cursor.getString(mimeColumn) != DocumentsContract.Document.MIME_TYPE_DIR) {
                    throw IllegalStateException("$name esiste già, ma non è una cartella.")
                }
                return DocumentsContract.buildDocumentUriUsingTree(
                    parent,
                    cursor.getString(idColumn),
                )
            }
        }
        return null
    }

    private fun queryChildNames(parent: Uri): Set<String> {
        val parentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentId)
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        val names = mutableSetOf<String>()
        resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                cursor.getString(0)?.trim()?.takeIf { it.isNotEmpty() }?.let {
                    names += it.lowercase(Locale.ROOT)
                }
            }
        } ?: throw IllegalStateException("Android non consente di leggere la cartella .toDo.")
        return names
    }

    private fun uniqueName(original: String, usedNames: Set<String>): String {
        var candidate = sanitizeFilename(original)
        if (candidate.lowercase(Locale.ROOT) !in usedNames) return candidate

        val dot = candidate.lastIndexOf('.')
        val stem = if (dot > 0) candidate.substring(0, dot) else candidate
        val extension = if (dot > 0) candidate.substring(dot) else ""
        var suffix = 1
        while (true) {
            val value = "$stem ($suffix)$extension"
            if (value.lowercase(Locale.ROOT) !in usedNames) return value
            suffix += 1
        }
    }

    private fun sanitizeFilename(value: String): String {
        val cleaned = buildString {
            for (char in value.trim()) {
                append(
                    when {
                        char.code < 32 -> '_'
                        char in charArrayOf('\\', '/', ':', '*', '?', '"', '<', '>', '|') -> '_'
                        else -> char
                    },
                )
            }
        }.trim().trim('.')
        val safe = cleaned.ifBlank { "shared_media" }
        return if (safe.length <= 180) safe else shortenFilename(safe, 180)
    }

    private fun shortenFilename(value: String, maxLength: Int): String {
        val dot = value.lastIndexOf('.')
        if (dot <= 0) return value.take(maxLength)
        val extension = value.substring(dot)
        val allowedStem = (maxLength - extension.length).coerceAtLeast(1)
        return value.substring(0, dot).take(allowedStem) + extension
    }

    private fun readSharedEntry(uri: Uri): SharedEntry? {
        val metadata = querySourceMetadata(uri)
        val rawMime = try {
            resolver.getType(uri)?.trim()?.lowercase(Locale.ROOT).orEmpty()
        } catch (_: Exception) {
            ""
        }
        if (
            rawMime.isNotEmpty() &&
            rawMime != "application/octet-stream" &&
            !rawMime.startsWith("image/") &&
            !rawMime.startsWith("video/")
        ) {
            return null
        }

        val rawName = metadata.first.ifBlank {
            uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
                ?: "shared_media"
        }
        val rawExtension = rawName.substringAfterLast('.', "").lowercase(Locale.ROOT)
        val inferredExtension = inferExtension(rawMime)
        val extension = when {
            rawExtension in SUPPORTED_EXTENSIONS -> rawExtension
            inferredExtension in SUPPORTED_EXTENSIONS -> inferredExtension
            else -> return null
        }

        val displayName = if (rawExtension in SUPPORTED_EXTENSIONS) {
            sanitizeFilename(rawName)
        } else {
            val base = rawName.substringBeforeLast('.', rawName).ifBlank { "shared_media" }
            sanitizeFilename("$base.$extension")
        }
        val mimeType = rawMime.ifBlank { mimeForExtension(extension) }

        return SharedEntry(
            uri = uri,
            displayName = displayName,
            mimeType = mimeType,
            sizeBytes = metadata.second,
        )
    }

    private fun querySourceMetadata(uri: Uri): Pair<String, Long> {
        var name = ""
        var size = 0L
        try {
            resolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameColumn >= 0 && !cursor.isNull(nameColumn)) {
                        name = cursor.getString(nameColumn).orEmpty()
                    }
                    if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                        size = cursor.getLong(sizeColumn).coerceAtLeast(0L)
                    }
                }
            }
        } catch (_: Exception) {
            // Alcuni provider non espongono metadata, ma possono comunque fornire lo stream.
        }
        return name to size
    }

    private fun inferExtension(mimeType: String): String {
        val manual = when (mimeType) {
            "image/jpeg", "image/jpg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            "image/gif" -> "gif"
            "image/bmp", "image/x-ms-bmp" -> "bmp"
            "image/tiff" -> "tiff"
            "video/mp4" -> "mp4"
            "video/x-matroska", "video/mkv" -> "mkv"
            "video/webm" -> "webm"
            "video/x-msvideo", "video/avi" -> "avi"
            "video/quicktime" -> "mov"
            "video/x-m4v" -> "m4v"
            else -> ""
        }
        if (manual.isNotEmpty()) return manual
        return MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType)
            ?.lowercase(Locale.ROOT)
            .orEmpty()
    }

    private fun mimeForExtension(extension: String): String {
        val manual = when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "bmp" -> "image/bmp"
            "tif", "tiff" -> "image/tiff"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "m4v" -> "video/x-m4v"
            else -> "application/octet-stream"
        }
        return manual
    }

    @Suppress("DEPRECATION")
    private fun extractUris(intent: Intent): List<Uri> {
        val values = LinkedHashSet<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(values::add)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.forEach(values::add)
            }
        }
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(values::add)
            }
        }
        return values.toList()
    }

    private fun batchToPlatformMap(batch: PendingBatch): Map<String, Any> {
        return mapOf(
            "token" to batch.token,
            "count" to batch.entries.size,
            "rejectedCount" to batch.rejectedCount,
            "receivedAtEpochMs" to batch.receivedAtEpochMs,
            "totalSizeBytes" to batch.entries.sumOf { it.sizeBytes.coerceAtLeast(0L) },
            "items" to batch.entries.map { entry ->
                mapOf(
                    "name" to entry.displayName,
                    "mimeType" to entry.mimeType,
                    "sizeBytes" to entry.sizeBytes,
                )
            },
        )
    }

    private fun safeMessage(error: Exception): String {
        return error.message?.takeIf { it.isNotBlank() }
            ?: "Operazione non riuscita (${error.javaClass.simpleName})."
    }
}
