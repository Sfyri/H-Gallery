package com.sfyri.h_gallery_mobile

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

internal class GallerySyncBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.sfyri.h_gallery_mobile/sync"
        private const val PREFS_NAME = "h_gallery_mobile"
        private const val PREFS_GALLERIES = "galleries_v1"
    }

    private data class ConnectionInfo(
        val galleryUuid: String,
        val galleryName: String,
        val treeUri: Uri,
        val address: String,
        val port: Int,
        val deviceId: String,
        val token: String,
    )

    private data class SyncItem(
        val syncUuid: String,
        val relativePath: String,
        val filename: String,
        val extension: String,
        val mediaType: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
        val sha256: String,
        val documentUri: String = "",
        val aiGenerated: Boolean = false,
        val characters: List<Map<String, String>> = emptyList(),
        val tags: List<String> = emptyList(),
        val artists: List<String> = emptyList(),
    )

    private data class DownloadedItem(
        val remote: SyncItem,
        val actualRelativePath: String,
    )

    private val repository = GalleryMediaRepository(activity.applicationContext)
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "analyzeSync" -> runAsync(result, "SYNC_ANALYZE_FAILED") {
                val info = connectionInfo(call)
                analyze(info)
            }
            "runSync" -> runAsync(result, "SYNC_RUN_FAILED") {
                val info = connectionInfo(call)
                runSync(info)
            }
            else -> result.notImplemented()
        }
    }

    private fun connectionInfo(call: MethodCall): ConnectionInfo {
        val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
        val galleryName = call.argument<String>("galleryName")?.trim().orEmpty().ifBlank { "H-Gallery Android" }
        val address = call.argument<String>("address")?.trim().orEmpty()
        val port = call.argument<Int>("port") ?: 8000
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        val token = call.argument<String>("token")?.trim().orEmpty()
        if (galleryUuid.isEmpty() || address.isEmpty() || deviceId.isEmpty() || token.isEmpty()) {
            throw IllegalArgumentException("Dati di collegamento M7 incompleti.")
        }
        return ConnectionInfo(
            galleryUuid = galleryUuid,
            galleryName = galleryName,
            treeUri = resolveTreeUri(galleryUuid),
            address = address,
            port = port,
            deviceId = deviceId,
            token = token,
        )
    }

    private fun analyze(info: ConnectionInfo): Map<String, Any> {
        progress("scan", 0, 1, "Indicizzazione galleria Android")
        repository.scanGallery(info.galleryUuid, info.treeUri)
        val local = localItems(info.galleryUuid)
        progress("compare", 0, 1, "Confronto con Windows")
        val remoteManifest = fetchManifest(info)
        val remote = parseManifestItems(remoteManifest)
        return plan(local, remote).toMutableMap().apply {
            put("androidCount", local.size)
            put("windowsCount", remote.size)
            put("windowsGalleryUuid", remoteManifest.optString("galleryUuid"))
            put("windowsGalleryName", remoteManifest.optString("galleryName", "H-Gallery"))
        }
    }

    private fun runSync(info: ConnectionInfo): Map<String, Any> {
        val started = System.currentTimeMillis()
        progress("scan", 0, 1, "Aggiornamento indice Android")
        repository.scanGallery(info.galleryUuid, info.treeUri)
        val localBefore = localItems(info.galleryUuid)
        val remoteManifest = fetchManifest(info)
        val remote = parseManifestItems(remoteManifest)
        val remoteGalleryUuid = remoteManifest.optString("galleryUuid")
        val initialPlan = plan(localBefore, remote)

        postJson(info, "/api/mobile/sync/begin", basePayload(info))

        val localByHash = localBefore.filter { it.sha256.isNotBlank() }.associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = remote.filter { it.sha256.isNotBlank() }.associateBy { it.sha256.lowercase(Locale.ROOT) }
        val downloads = remoteByHash.filterKeys { it !in localByHash }.values.toList()
        val uploads = localByHash.filterKeys { it !in remoteByHash }.values.toList()

        val downloaded = mutableListOf<DownloadedItem>()
        downloads.forEachIndexed { index, item ->
            progress("download", index, downloads.size, item.filename)
            downloaded += downloadItem(info, item)
        }
        if (downloads.isNotEmpty()) {
            progress("scan", 0, 1, "Aggiornamento file ricevuti")
            repository.scanGallery(info.galleryUuid, info.treeUri)
            remapDownloadedUuids(info.galleryUuid, downloaded)
        }

        // Metadata from Windows is merged even when the binary already existed locally.
        progress("metadata_android", 0, remote.size, "Merge metadata su Android")
        mergeRemoteMetadata(info.galleryUuid, remote)

        uploads.forEachIndexed { index, item ->
            progress("upload", index, uploads.size, item.filename)
            uploadItem(info, item)
        }

        progress("finalize_windows", 0, 1, "Aggiornamento indice Windows")
        val finalize = postJson(info, "/api/mobile/sync/finalize", basePayload(info))

        // Push all local metadata, not only new files: this makes metadata union bidirectional.
        val localAfter = localItems(info.galleryUuid)
        val uniqueLocal = localAfter.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }.values.toList()
        var metadataMergedWindows = 0
        var unresolvedWindows = 0
        uniqueLocal.chunked(100).forEachIndexed { index, chunk ->
            progress("metadata_windows", index, (uniqueLocal.size + 99) / 100, "Merge metadata su Windows")
            val payload = basePayload(info).apply {
                put("items", JSONArray().apply { chunk.forEach { put(itemJson(it, includeDocument = false)) } })
            }
            val response = postJson(info, "/api/mobile/sync/metadata", payload)
            metadataMergedWindows += response.optInt("merged", 0)
            unresolvedWindows += response.optInt("unresolvedCharacters", 0)
        }

        recordWindowsPeer(info.galleryUuid, remoteGalleryUuid, remoteManifest.optString("galleryName", "H-Gallery Windows"))
        progress("done", 1, 1, "Sincronizzazione completata")
        return mutableMapOf<String, Any>(
            "downloaded" to downloads.size,
            "uploaded" to uploads.size,
            "alreadyPresent" to (initialPlan["alreadyPresent"] ?: 0),
            "pathConflicts" to (initialPlan["pathConflicts"] ?: 0),
            "metadataMergedWindows" to metadataMergedWindows,
            "unresolvedWindowsCharacters" to unresolvedWindows,
            "androidCount" to localAfter.size,
            "windowsCount" to finalize.optInt("count", remote.size + uploads.size),
            "elapsedMs" to (System.currentTimeMillis() - started),
        )
    }

    private fun plan(local: List<SyncItem>, remote: List<SyncItem>): Map<String, Any> {
        val localByHash = local.filter { it.sha256.isNotBlank() }.associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = remote.filter { it.sha256.isNotBlank() }.associateBy { it.sha256.lowercase(Locale.ROOT) }
        val toAndroid = remoteByHash.filterKeys { it !in localByHash }.values
        val toWindows = localByHash.filterKeys { it !in remoteByHash }.values
        val localPaths = local.associateBy { it.relativePath.lowercase(Locale.ROOT) }
        val pathConflicts = remote.count { remoteItem ->
            val localItem = localPaths[remoteItem.relativePath.lowercase(Locale.ROOT)]
            localItem != null && !localItem.sha256.equals(remoteItem.sha256, ignoreCase = true)
        }
        return mapOf(
            "toAndroid" to toAndroid.size,
            "toWindows" to toWindows.size,
            "alreadyPresent" to localByHash.keys.intersect(remoteByHash.keys).size,
            "pathConflicts" to pathConflicts,
            "bytesToAndroid" to toAndroid.sumOf { it.sizeBytes.coerceAtLeast(0L) },
            "bytesToWindows" to toWindows.sumOf { it.sizeBytes.coerceAtLeast(0L) },
        )
    }

    private fun fetchManifest(info: ConnectionInfo): JSONObject =
        postJson(info, "/api/mobile/sync/manifest", basePayload(info))

    private fun basePayload(info: ConnectionInfo): JSONObject = JSONObject().apply {
        put("device_id", info.deviceId)
        put("token", info.token)
        put("android_gallery_uuid", info.galleryUuid)
        put("android_gallery_name", info.galleryName)
    }

    private fun parseManifestItems(manifest: JSONObject): List<SyncItem> {
        val array = manifest.optJSONArray("files") ?: JSONArray()
        val values = mutableListOf<SyncItem>()
        for (index in 0 until array.length()) {
            val value = array.optJSONObject(index) ?: continue
            values += syncItemFromJson(value)
        }
        return values
    }

    private fun syncItemFromJson(value: JSONObject): SyncItem {
        fun strings(key: String): List<String> {
            val array = value.optJSONArray(key) ?: JSONArray()
            return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }
        }
        val charactersArray = value.optJSONArray("characters") ?: JSONArray()
        val characters = (0 until charactersArray.length()).mapNotNull { index ->
            val item = charactersArray.optJSONObject(index) ?: return@mapNotNull null
            mapOf(
                "name" to item.optString("name"),
                "relativePath" to item.optString("relativePath"),
                "franchiseName" to item.optString("franchiseName"),
                "franchiseCode" to item.optString("franchiseCode"),
                "franchiseRelativePath" to item.optString("franchiseRelativePath"),
            )
        }
        return SyncItem(
            syncUuid = value.optString("syncUuid"),
            relativePath = value.optString("relativePath"),
            filename = value.optString("filename"),
            extension = value.optString("extension"),
            mediaType = value.optString("mediaType", "image"),
            mimeType = value.optString("mimeType"),
            sizeBytes = value.optLong("sizeBytes", 0L),
            modifiedEpochMs = value.optLong("modifiedEpochMs", 0L),
            sha256 = value.optString("sha256"),
            aiGenerated = value.optBoolean("aiGenerated", false),
            characters = characters,
            tags = strings("tags"),
            artists = strings("artists"),
        )
    }

    private fun localItems(galleryUuid: String): List<SyncItem> {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.readableDatabase
            val items = mutableListOf<SyncItem>()
            db.rawQuery(
                """
                SELECT sync_uuid, relative_path, filename, extension, media_type,
                       mime_type, size_bytes, modified_epoch_ms, sha256,
                       document_uri, ai_generated
                FROM media
                WHERE is_present = 1
                ORDER BY relative_path COLLATE NOCASE
                """.trimIndent(),
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val syncUuid = cursor.getString(0)
                    val metadata = localMetadata(db, syncUuid)
                    items += SyncItem(
                        syncUuid = syncUuid,
                        relativePath = cursor.getString(1),
                        filename = cursor.getString(2),
                        extension = cursor.getString(3),
                        mediaType = cursor.getString(4),
                        mimeType = cursor.getString(5),
                        sizeBytes = cursor.getLong(6),
                        modifiedEpochMs = cursor.getLong(7),
                        sha256 = cursor.getString(8),
                        documentUri = cursor.getString(9),
                        aiGenerated = cursor.getInt(10) != 0,
                        characters = metadata.first,
                        tags = metadata.second,
                        artists = metadata.third,
                    )
                }
            }
            return items
        } finally {
            database.close()
        }
    }

    private fun localMetadata(db: SQLiteDatabase, syncUuid: String): Triple<List<Map<String, String>>, List<String>, List<String>> {
        val characters = mutableListOf<Map<String, String>>()
        db.rawQuery(
            """
            SELECT c.name, c.relative_path, f.name, f.code, f.relative_path
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
                    "relativePath" to cursor.getString(1),
                    "franchiseName" to cursor.getString(2),
                    "franchiseCode" to cursor.getString(3),
                    "franchiseRelativePath" to cursor.getString(4),
                )
            }
        }
        val tags = mutableListOf<String>()
        val artists = mutableListOf<String>()
        db.rawQuery(
            """
            SELECT t.name, t.type
            FROM media_tags mt JOIN tags t ON t.id = mt.tag_id
            WHERE mt.media_sync_uuid = ?
            ORDER BY t.name COLLATE NOCASE
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                when (cursor.getString(1)) {
                    "artist" -> artists += cursor.getString(0)
                    "general" -> if (!cursor.getString(0).equals("AI", true)) tags += cursor.getString(0)
                }
            }
        }
        return Triple(characters, tags, artists)
    }

    private fun downloadItem(info: ConnectionInfo, item: SyncItem): DownloadedItem {
        val target = chooseDestination(info.treeUri, item.relativePath, item.syncUuid)
        val parent = ensureDirectoryPath(info.treeUri, target.substringBeforeLast('/', ""))
        val finalName = target.substringAfterLast('/')
        val tempName = ".${finalName}.hgsync-${UUID.randomUUID().toString().take(8)}.part"
        val tempUri = DocumentsContract.createDocument(
            activity.contentResolver,
            parent,
            "application/octet-stream",
            tempName,
        ) ?: throw IllegalStateException("Impossibile creare il file temporaneo Android.")

        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(info, "/api/mobile/sync/file/${item.syncUuid}", "GET")
            connection.setRequestProperty("X-HGallery-Device", info.deviceId)
            connection.setRequestProperty("X-HGallery-Token", info.token)
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            val digest = MessageDigest.getInstance("SHA-256")
            activity.contentResolver.openOutputStream(tempUri, "w")?.use { rawOut ->
                BufferedOutputStream(rawOut).use { output ->
                    BufferedInputStream(connection.inputStream).use { input ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count > 0) {
                                output.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                            }
                        }
                        output.flush()
                    }
                }
            } ?: throw IllegalStateException("Android non consente di scrivere nella galleria.")
            val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
            if (!actualHash.equals(item.sha256, ignoreCase = true)) {
                throw IllegalStateException("Hash non valido durante il download di ${item.filename}.")
            }
            val renamed = DocumentsContract.renameDocument(activity.contentResolver, tempUri, finalName)
            if (renamed == null) {
                val finalUri = DocumentsContract.createDocument(
                    activity.contentResolver,
                    parent,
                    mimeFor(item),
                    finalName,
                ) ?: throw IllegalStateException("Impossibile creare ${item.filename} su Android.")
                activity.contentResolver.openInputStream(tempUri)?.use { input ->
                    activity.contentResolver.openOutputStream(finalUri, "w")?.use { output ->
                        input.copyTo(output, 256 * 1024)
                    } ?: throw IllegalStateException("Impossibile completare il file su Android.")
                } ?: throw IllegalStateException("Impossibile rileggere il file temporaneo Android.")
                DocumentsContract.deleteDocument(activity.contentResolver, tempUri)
            }
            return DownloadedItem(item, target)
        } catch (error: Exception) {
            try { DocumentsContract.deleteDocument(activity.contentResolver, tempUri) } catch (_: Exception) { }
            throw error
        } finally {
            connection?.disconnect()
        }
    }

    private fun uploadItem(info: ConnectionInfo, item: SyncItem) {
        // Keep the HTTP header deliberately small. Rich metadata is merged later
        // through /metadata as JSON, so the streaming upload only needs the
        // fields required to place and verify the binary safely.
        val mediaHeader = Base64.encodeToString(
            transferJson(item).toString().toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
        val connection = openConnection(info, "/api/mobile/sync/upload", "POST")
        try {
            connection.doOutput = true
            connection.setChunkedStreamingMode(256 * 1024)
            connection.setRequestProperty("Content-Type", "application/octet-stream")
            connection.setRequestProperty("X-HGallery-Device", info.deviceId)
            connection.setRequestProperty("X-HGallery-Token", info.token)
            connection.setRequestProperty("X-HGallery-Media", mediaHeader)
            activity.contentResolver.openInputStream(Uri.parse(item.documentUri))?.use { rawInput ->
                BufferedInputStream(rawInput).use { input ->
                    BufferedOutputStream(connection.outputStream).use { output ->
                        input.copyTo(output, 256 * 1024)
                        output.flush()
                    }
                }
            } ?: throw IllegalStateException("Impossibile leggere ${item.filename} dal telefono.")
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            connection.inputStream.close()
        } finally {
            connection.disconnect()
        }
    }

    private fun transferJson(item: SyncItem): JSONObject = JSONObject().apply {
        put("syncUuid", item.syncUuid)
        put("relativePath", item.relativePath)
        put("filename", item.filename)
        put("mediaType", item.mediaType)
        put("sizeBytes", item.sizeBytes)
        put("modifiedEpochMs", item.modifiedEpochMs)
        put("sha256", item.sha256)
    }

    private fun itemJson(item: SyncItem, includeDocument: Boolean): JSONObject = JSONObject().apply {
        put("syncUuid", item.syncUuid)
        put("relativePath", item.relativePath)
        put("filename", item.filename)
        put("extension", item.extension)
        put("mediaType", item.mediaType)
        put("mimeType", item.mimeType)
        put("sizeBytes", item.sizeBytes)
        put("modifiedEpochMs", item.modifiedEpochMs)
        put("sha256", item.sha256)
        put("aiGenerated", item.aiGenerated)
        put("tags", JSONArray(item.tags))
        put("artists", JSONArray(item.artists))
        put("characters", JSONArray().apply {
            item.characters.forEach { character ->
                put(JSONObject().apply { character.forEach { (key, value) -> put(key, value) } })
            }
        })
        if (includeDocument) put("documentUri", item.documentUri)
    }

    private fun remapDownloadedUuids(galleryUuid: String, downloaded: List<DownloadedItem>) {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            for (entry in downloaded) {
                val remoteUuid = entry.remote.syncUuid
                if (remoteUuid.isBlank()) continue
                val uuidUsed = db.rawQuery(
                    "SELECT sha256 FROM media WHERE sync_uuid = ? LIMIT 1",
                    arrayOf(remoteUuid),
                ).use { cursor -> cursor.moveToFirst() && !cursor.getString(0).equals(entry.remote.sha256, true) }
                if (uuidUsed) continue
                val currentUuid = db.rawQuery(
                    "SELECT sync_uuid FROM media WHERE relative_path = ? AND sha256 = ? AND is_present = 1 LIMIT 1",
                    arrayOf(entry.actualRelativePath, entry.remote.sha256),
                ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                if (currentUuid == null || currentUuid == remoteUuid) continue
                // A freshly downloaded row has no metadata relations yet.
                try {
                    db.execSQL("UPDATE media SET sync_uuid = ? WHERE sync_uuid = ?", arrayOf(remoteUuid, currentUuid))
                } catch (_: Exception) {
                    // Hash-based matching still prevents duplicates if UUID reconciliation is impossible.
                }
            }
        } finally {
            database.close()
        }
    }

    private fun mergeRemoteMetadata(galleryUuid: String, remote: List<SyncItem>) {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            db.beginTransaction()
            try {
                for (item in remote) {
                    val localUuid = db.rawQuery(
                        "SELECT sync_uuid FROM media WHERE sha256 = ? AND is_present = 1 LIMIT 1",
                        arrayOf(item.sha256),
                    ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null } ?: continue
                    if (item.aiGenerated) {
                        val values = ContentValues().apply {
                            put("ai_generated", 1)
                            put("metadata_updated_epoch_ms", System.currentTimeMillis())
                        }
                        db.update("media", values, "sync_uuid = ?", arrayOf(localUuid))
                        val aiId = ensureTag(db, "AI", "system")
                        linkTag(db, localUuid, aiId)
                    }
                    item.tags.forEach { tag -> if (tag.isNotBlank()) linkTag(db, localUuid, ensureTag(db, tag, "general")) }
                    item.artists.forEach { artist -> if (artist.isNotBlank()) linkTag(db, localUuid, ensureTag(db, artist, "artist")) }
                    item.characters.forEach { character ->
                        val characterId = ensureCharacter(db, character)
                        if (characterId != null) {
                            val values = ContentValues().apply {
                                put("media_sync_uuid", localUuid)
                                put("character_id", characterId)
                            }
                            db.insertWithOnConflict("media_characters", null, values, SQLiteDatabase.CONFLICT_IGNORE)
                        }
                    }
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }
    }

    private fun ensureTag(db: SQLiteDatabase, rawName: String, requestedType: String): Long {
        val name = rawName.trim().split(Regex("\\s+")).filter(String::isNotBlank).joinToString(" ")
        db.rawQuery("SELECT id, type FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1", arrayOf(name)).use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val current = cursor.getString(1)
                if (current == "general" && requestedType == "artist") {
                    val values = ContentValues().apply { put("type", "artist"); put("updated_at_epoch_ms", System.currentTimeMillis()) }
                    db.update("tags", values, "id = ?", arrayOf(id.toString()))
                }
                return id
            }
        }
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString())
            put("name", name)
            put("type", if (name.equals("AI", true)) "system" else requestedType)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        return db.insertOrThrow("tags", null, values)
    }

    private fun linkTag(db: SQLiteDatabase, mediaUuid: String, tagId: Long) {
        val values = ContentValues().apply { put("media_sync_uuid", mediaUuid); put("tag_id", tagId) }
        db.insertWithOnConflict("media_tags", null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    private fun ensureCharacter(db: SQLiteDatabase, value: Map<String, String>): Long? {
        val name = value["name"].orEmpty().trim()
        val franchiseName = value["franchiseName"].orEmpty().trim()
        if (name.isEmpty() || franchiseName.isEmpty()) return null
        var franchiseId = db.rawQuery(
            "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(franchiseName),
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else null }
        if (franchiseId == null) {
            val now = System.currentTimeMillis()
            var code = value["franchiseCode"].orEmpty().trim().ifBlank {
                franchiseName.filter(Char::isLetterOrDigit).uppercase(Locale.ROOT).take(8).ifBlank { "SERIE" }
            }
            var suffix = 1
            while (db.rawQuery("SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE LIMIT 1", arrayOf(code)).use { it.moveToFirst() }) {
                code = (code.take(6) + suffix.toString()).take(10)
                suffix += 1
            }
            val path = value["franchiseRelativePath"].orEmpty().trim().ifBlank { franchiseName }
            val values = ContentValues().apply {
                put("sync_uuid", UUID.randomUUID().toString()); put("name", franchiseName); put("code", code)
                put("relative_path", path); put("is_active", 1); put("created_at_epoch_ms", now); put("updated_at_epoch_ms", now)
            }
            franchiseId = db.insertOrThrow("franchises", null, values)
        }
        db.rawQuery(
            "SELECT id FROM characters WHERE franchise_id = ? AND name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(franchiseId.toString(), name),
        ).use { cursor -> if (cursor.moveToFirst()) return cursor.getLong(0) }
        val now = System.currentTimeMillis()
        val characterPath = value["relativePath"].orEmpty().trim().ifBlank {
            val franchisePath = value["franchiseRelativePath"].orEmpty().trim().ifBlank { franchiseName }
            "$franchisePath/$name"
        }
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString()); put("franchise_id", franchiseId); put("name", name)
            put("relative_path", characterPath); put("is_active", 1); put("created_at_epoch_ms", now); put("updated_at_epoch_ms", now)
        }
        return try { db.insertOrThrow("characters", null, values) } catch (_: Exception) { null }
    }

    private fun recordWindowsPeer(galleryUuid: String, windowsGalleryUuid: String, name: String) {
        if (windowsGalleryUuid.isBlank()) return
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            db.delete("sync_peers", "peer_gallery_uuid = ? AND peer_uuid <> ?", arrayOf(windowsGalleryUuid, windowsGalleryUuid))
            db.execSQL(
                """
                INSERT OR REPLACE INTO sync_peers(
                    peer_uuid, peer_gallery_uuid, display_name, platform,
                    paired_at, last_seen_at, is_active
                ) VALUES (?, ?, ?, 'windows', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                """.trimIndent(),
                arrayOf(windowsGalleryUuid, windowsGalleryUuid, name),
            )
        } finally {
            database.close()
        }
    }

    private fun chooseDestination(treeUri: Uri, requested: String, syncUuid: String): String {
        val clean = safeRelative(requested)
        val parentPath = clean.substringBeforeLast('/', "")
        val originalName = clean.substringAfterLast('/')
        val parent = ensureDirectoryPath(treeUri, parentPath)
        if (findChild(parent, originalName) == null) return clean
        val dot = originalName.lastIndexOf('.')
        val stem = if (dot > 0) originalName.substring(0, dot) else originalName
        val extension = if (dot > 0) originalName.substring(dot) else ""
        val suffix = syncUuid.filter(Char::isLetterOrDigit).take(8).ifBlank { UUID.randomUUID().toString().take(8) }
        for (index in 0 until 10000) {
            val extra = if (index == 0) "_sync_$suffix" else "_sync_${suffix}_$index"
            val name = "$stem$extra$extension"
            if (findChild(parent, name) == null) return if (parentPath.isBlank()) name else "$parentPath/$name"
        }
        throw IllegalStateException("Impossibile trovare un nome libero nella galleria Android.")
    }

    private fun safeRelative(value: String): String {
        val parts = value.replace('\\', '/').trim('/').split('/').filter(String::isNotBlank)
        if (parts.isEmpty() || parts.any { it == "." || it == ".." }) throw IllegalArgumentException("Percorso media non valido.")
        if (parts.first().lowercase(Locale.ROOT) in setOf(".user", ".todo", ".trash", ".script")) {
            throw IllegalArgumentException("Percorso interno non sincronizzabile.")
        }
        return parts.joinToString("/")
    }

    private fun ensureDirectoryPath(treeUri: Uri, relativeDirectory: String): Uri {
        var current = treeDocumentUri(treeUri)
        if (relativeDirectory.isBlank()) return current
        for (segment in safeRelative(relativeDirectory).split('/')) {
            val existing = findChild(current, segment)
            current = when {
                existing == null -> DocumentsContract.createDocument(
                    activity.contentResolver,
                    current,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ) ?: throw IllegalStateException("Impossibile creare la cartella $segment.")
                existing.second != DocumentsContract.Document.MIME_TYPE_DIR -> throw IllegalStateException("$segment esiste ma non è una cartella.")
                else -> existing.first
            }
        }
        return current
    }

    private fun findChild(parent: Uri, name: String): Pair<Uri, String>? {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0)) to cursor.getString(2)
                }
            }
        }
        return null
    }

    private fun treeDocumentUri(treeUri: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        treeUri,
        DocumentsContract.getTreeDocumentId(treeUri),
    )

    private fun resolveTreeUri(galleryUuid: String): Uri {
        val raw = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(PREFS_GALLERIES, "[]") ?: "[]"
        val profiles = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
        for (index in 0 until profiles.length()) {
            val profile = profiles.optJSONObject(index) ?: continue
            if (profile.optString("galleryUuid") != galleryUuid) continue
            val uri = Uri.parse(profile.optString("treeUri"))
            val access = activity.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
            if (!access) throw IllegalStateException("H-Gallery non ha più accesso in lettura/scrittura alla galleria Android.")
            return uri
        }
        throw IllegalArgumentException("Galleria Android non trovata.")
    }

    private fun mimeFor(item: SyncItem): String {
        if (item.mimeType.isNotBlank()) return item.mimeType
        return URLConnection.guessContentTypeFromName(item.filename)
            ?: if (item.mediaType == "video") "video/*" else "image/*"
    }

    private fun postJson(info: ConnectionInfo, path: String, payload: JSONObject): JSONObject {
        val connection = openConnection(info, path, "POST")
        try {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            val bytes = payload.toString().toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(bytes.size)
            connection.outputStream.use { it.write(bytes); it.flush() }
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return if (text.isBlank()) JSONObject() else JSONObject(text)
        } finally {
            connection.disconnect()
        }
    }

    private fun openConnection(info: ConnectionInfo, path: String, method: String): HttpURLConnection {
        val url = URL("http://${info.address}:${info.port}$path")
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 8000
            readTimeout = 120000
            useCaches = false
            setRequestProperty("Accept", "application/json, application/octet-stream")
        }
    }

    private fun httpError(connection: HttpURLConnection, code: Int): String {
        val text = try { connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty() } catch (_: Exception) { "" }
        return try {
            JSONObject(text).optString("detail").ifBlank { "Errore HTTP $code." }
        } catch (_: Exception) {
            text.takeIf(String::isNotBlank) ?: "Errore HTTP $code."
        }
    }

    private fun progress(phase: String, processed: Int, total: Int, current: String) {
        activity.runOnUiThread {
            channel.invokeMethod(
                "syncProgress",
                mapOf("phase" to phase, "processed" to processed, "total" to total, "current" to current),
            )
        }
    }

    private fun runAsync(result: MethodChannel.Result, errorCode: String, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                val message = error.message?.takeIf(String::isNotBlank) ?: "Operazione non riuscita (${error.javaClass.simpleName})."
                activity.runOnUiThread { result.error(errorCode, message, null) }
            }
        }
    }
}
