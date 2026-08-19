package com.sfyri.h_gallery_mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.sfyri.h_gallery_mobile/gallery"
        private const val PICK_DIRECTORY_REQUEST = 41021
        private const val PREFS_NAME = "h_gallery_mobile"
        private const val PREFS_GALLERIES = "galleries_v1"
        private const val IDENTITY_FILE = "h_gallery_android.json"
        private const val IDENTITY_SCHEMA_VERSION = 1
    }

    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingGalleryName: String = ""
    private var mediaBridge: GalleryMediaBridge? = null
    private var syncBridge: GallerySyncBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        mediaBridge?.dispose()
        mediaBridge = GalleryMediaBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        syncBridge?.dispose()
        syncBridge = GallerySyncBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "listGalleries" -> {
                try {
                    result.success(loadProfiles().map(::profileToPlatformMap))
                } catch (error: Exception) {
                    result.error("GALLERY_LIST_FAILED", safeMessage(error), null)
                }
            }

            "pickGalleryDirectory" -> {
                if (pendingPickerResult != null) {
                    result.error(
                        "PICKER_ALREADY_OPEN",
                        "Il selettore di cartelle è già aperto.",
                        null,
                    )
                    return
                }

                pendingGalleryName = call.argument<String>("nameHint")?.trim().orEmpty()
                pendingPickerResult = result

                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                }
                startActivityForResult(intent, PICK_DIRECTORY_REQUEST)
            }

            "renameGallery" -> {
                val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
                val name = call.argument<String>("name")?.trim().orEmpty()
                if (galleryUuid.isEmpty()) {
                    result.error("INVALID_GALLERY", "Identità della galleria non valida.", null)
                    return
                }
                if (name.isEmpty()) {
                    result.error("INVALID_GALLERY_NAME", "Il nome della galleria non può essere vuoto.", null)
                    return
                }
                try {
                    renameGallery(galleryUuid, name)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("GALLERY_RENAME_FAILED", safeMessage(error), null)
                }
            }

            "disconnectGallery" -> {
                val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
                if (galleryUuid.isEmpty()) {
                    result.error("INVALID_GALLERY", "Identità della galleria non valida.", null)
                    return
                }
                try {
                    disconnectGallery(galleryUuid)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("GALLERY_DISCONNECT_FAILED", safeMessage(error), null)
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onDestroy() {
        syncBridge?.dispose()
        syncBridge = null
        mediaBridge?.dispose()
        mediaBridge = null
        super.onDestroy()
    }

    @Deprecated("Deprecated in Android, kept for the system document picker callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_DIRECTORY_REQUEST) return

        val flutterResult = pendingPickerResult ?: return
        pendingPickerResult = null
        val requestedName = pendingGalleryName
        pendingGalleryName = ""

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            flutterResult.success(null)
            return
        }

        val treeUri = data.data!!
        try {
            persistTreePermission(treeUri, data.flags)
            val profile = registerGallery(treeUri, requestedName)
            flutterResult.success(profileToPlatformMap(profile))
        } catch (error: Exception) {
            flutterResult.error("GALLERY_SETUP_FAILED", safeMessage(error), null)
        }
    }

    private fun persistTreePermission(treeUri: Uri, resultFlags: Int) {
        val readFlag = Intent.FLAG_GRANT_READ_URI_PERMISSION
        val writeFlag = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val grantedFlags = resultFlags and (readFlag or writeFlag)

        if (grantedFlags and readFlag == 0 || grantedFlags and writeFlag == 0) {
            throw IllegalStateException(
                "La cartella deve consentire a H-Gallery sia la lettura sia la scrittura.",
            )
        }

        contentResolver.takePersistableUriPermission(treeUri, grantedFlags)
        if (!hasPersistedAccess(treeUri)) {
            throw IllegalStateException(
                "Android non ha mantenuto il permesso sulla cartella selezionata.",
            )
        }
    }

    private fun registerGallery(treeUri: Uri, requestedName: String): JSONObject {
        if (!hasPersistedAccess(treeUri)) {
            throw IllegalStateException("H-Gallery non ha accesso persistente alla cartella.")
        }

        val rootDocument = treeDocumentUri(treeUri)
        val directoryName = queryDisplayName(rootDocument).ifBlank { "H-Gallery" }
        val locationLabel = locationLabel(treeUri, directoryName)
        val dataDirectory = ensureGalleryLayout(treeUri)
        val profiles = loadProfiles().toMutableList()

        val existingIndex = profiles.indexOfFirst {
            it.optString("treeUri") == treeUri.toString()
        }

        val existingUuid = profiles.getOrNull(existingIndex)?.optString("galleryUuid")
            ?.takeIf(::isValidUuid)

        var galleryUuid = existingUuid ?: readGalleryIdentity(dataDirectory)
            ?.takeIf(::isValidUuid)
            ?: UUID.randomUUID().toString()

        val duplicateIndex = profiles.indexOfFirst {
            it.optString("galleryUuid") == galleryUuid &&
                it.optString("treeUri") != treeUri.toString()
        }
        if (duplicateIndex >= 0) {
            // Una copia manuale dell'intera cartella non deve creare due gallerie
            // locali con la stessa identità.
            galleryUuid = UUID.randomUUID().toString()
        }

        writeGalleryIdentity(dataDirectory, galleryUuid)

        val now = System.currentTimeMillis()
        val profile = JSONObject().apply {
            put("galleryUuid", galleryUuid)
            put("name", requestedName.ifBlank { directoryName })
            put("treeUri", treeUri.toString())
            put("directoryName", directoryName)
            put("locationLabel", locationLabel)
            put("createdAtEpochMs", profiles.getOrNull(existingIndex)?.optLong("createdAtEpochMs", now) ?: now)
        }

        if (existingIndex >= 0) {
            profiles[existingIndex] = profile
        } else {
            profiles.add(profile)
        }
        saveProfiles(profiles)
        return profile
    }

    private fun renameGallery(galleryUuid: String, name: String) {
        val profiles = loadProfiles().toMutableList()
        val index = profiles.indexOfFirst { it.optString("galleryUuid") == galleryUuid }
        if (index < 0) {
            throw IllegalArgumentException("Galleria non trovata.")
        }

        val profile = profiles[index]
        profile.put("name", name.trim())
        profiles[index] = profile
        saveProfiles(profiles)
    }

    private fun disconnectGallery(galleryUuid: String) {
        val profiles = loadProfiles().toMutableList()
        val index = profiles.indexOfFirst { it.optString("galleryUuid") == galleryUuid }
        if (index < 0) return

        val removed = profiles.removeAt(index)
        saveProfiles(profiles)

        val treeUri = Uri.parse(removed.optString("treeUri"))
        val stillUsed = profiles.any { it.optString("treeUri") == treeUri.toString() }
        if (!stillUsed) {
            try {
                contentResolver.releasePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Il permesso può essere già stato revocato dall'utente/sistema.
            }
        }
    }

    private fun profileToPlatformMap(profile: JSONObject): Map<String, Any> {
        val treeUri = Uri.parse(profile.optString("treeUri"))
        val accessible = hasPersistedAccess(treeUri)
        val layoutReady = accessible && isGalleryLayoutReady(treeUri)

        return mapOf(
            "galleryUuid" to profile.optString("galleryUuid"),
            "name" to profile.optString("name"),
            "treeUri" to treeUri.toString(),
            "directoryName" to profile.optString("directoryName"),
            "locationLabel" to profile.optString("locationLabel"),
            "accessible" to accessible,
            "layoutReady" to layoutReady,
        )
    }

    private fun ensureGalleryLayout(treeUri: Uri): Uri {
        val root = treeDocumentUri(treeUri)
        val user = ensureDirectory(root, ".user")
        val data = ensureDirectory(user, "data")
        ensureDirectory(user, "backups")
        ensureDirectory(root, ".toDo")
        ensureDirectory(root, ".trash")
        return data
    }

    private fun isGalleryLayoutReady(treeUri: Uri): Boolean {
        return try {
            val root = treeDocumentUri(treeUri)
            val user = findDirectory(root, ".user") ?: return false
            findDirectory(user, "data") != null &&
                findDirectory(user, "backups") != null &&
                findDirectory(root, ".toDo") != null &&
                findDirectory(root, ".trash") != null
        } catch (_: Exception) {
            false
        }
    }

    private fun ensureDirectory(parent: Uri, name: String): Uri {
        findChild(parent, name)?.let { child ->
            if (child.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IllegalStateException(
                    "Esiste già un elemento chiamato $name, ma non è una cartella.",
                )
            }
            return child.uri
        }

        return DocumentsContract.createDocument(
            contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IllegalStateException("Impossibile creare la cartella $name.")
    }

    private fun findDirectory(parent: Uri, name: String): Uri? {
        val child = findChild(parent, name) ?: return null
        return child.uri.takeIf {
            child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR
        }
    }

    private data class ChildDocument(
        val uri: Uri,
        val mimeType: String,
    )

    private fun findChild(parent: Uri, name: String): ChildDocument? {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            parentDocumentId,
        )

        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )

        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
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
                if (cursor.getString(nameColumn) == name) {
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(
                        parent,
                        cursor.getString(idColumn),
                    )
                    return ChildDocument(childUri, cursor.getString(mimeColumn))
                }
            }
        }
        return null
    }

    private fun readGalleryIdentity(dataDirectory: Uri): String? {
        val identity = findChild(dataDirectory, IDENTITY_FILE) ?: return null
        if (identity.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) return null

        return try {
            val text = contentResolver.openInputStream(identity.uri)?.use { stream ->
                stream.readBytes().toString(StandardCharsets.UTF_8)
            } ?: return null
            JSONObject(text).optString("gallery_uuid").takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private fun writeGalleryIdentity(dataDirectory: Uri, galleryUuid: String) {
        val existing = findChild(dataDirectory, IDENTITY_FILE)
        val identityUri = when {
            existing == null -> DocumentsContract.createDocument(
                contentResolver,
                dataDirectory,
                "application/json",
                IDENTITY_FILE,
            ) ?: throw IllegalStateException("Impossibile creare l'identità della galleria.")

            existing.mimeType == DocumentsContract.Document.MIME_TYPE_DIR -> {
                throw IllegalStateException("$IDENTITY_FILE esiste già come cartella.")
            }

            else -> existing.uri
        }

        val payload = JSONObject().apply {
            put("schema_version", IDENTITY_SCHEMA_VERSION)
            put("gallery_uuid", galleryUuid)
            put("platform", "android")
            put("updated_at_epoch_ms", System.currentTimeMillis())
        }.toString(2)

        contentResolver.openOutputStream(identityUri, "wt")?.use { stream ->
            stream.write(payload.toByteArray(StandardCharsets.UTF_8))
            stream.flush()
        } ?: throw IllegalStateException("Impossibile salvare l'identità della galleria.")
    }

    private fun treeDocumentUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun queryDisplayName(documentUri: Uri): String {
        val projection = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        contentResolver.query(documentUri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getString(0).orEmpty()
            }
        }
        return ""
    }

    private fun locationLabel(treeUri: Uri, fallbackName: String): String {
        return try {
            val documentId = DocumentsContract.getTreeDocumentId(treeUri)
            val parts = documentId.split(":", limit = 2)
            if (parts.size != 2) return fallbackName

            val volume = parts[0]
            val relativePath = parts[1].trim('/')
            val prefix = if (volume.equals("primary", ignoreCase = true)) {
                "Memoria interna"
            } else {
                "Archivio $volume"
            }
            if (relativePath.isBlank()) prefix else "$prefix/$relativePath"
        } catch (_: Exception) {
            fallbackName
        }
    }

    private fun hasPersistedAccess(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.uri == treeUri &&
                permission.isReadPermission &&
                permission.isWritePermission
        }
    }

    private fun loadProfiles(): List<JSONObject> {
        val raw = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getString(PREFS_GALLERIES, "[]") ?: "[]"
        val array = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }

        val profiles = mutableListOf<JSONObject>()
        for (index in 0 until array.length()) {
            array.optJSONObject(index)?.let(profiles::add)
        }
        return profiles.sortedBy { it.optString("name").lowercase() }
    }

    private fun saveProfiles(profiles: List<JSONObject>) {
        val array = JSONArray()
        profiles.forEach(array::put)
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(PREFS_GALLERIES, array.toString())
            .apply()
    }

    private fun isValidUuid(value: String): Boolean {
        return try {
            UUID.fromString(value)
            true
        } catch (_: IllegalArgumentException) {
            false
        }
    }

    private fun safeMessage(error: Exception): String {
        return error.message?.takeIf { it.isNotBlank() }
            ?: "Operazione non riuscita (${error.javaClass.simpleName})."
    }
}
