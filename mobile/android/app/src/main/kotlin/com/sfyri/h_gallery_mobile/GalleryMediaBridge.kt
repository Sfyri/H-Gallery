package com.sfyri.h_gallery_mobile

import android.app.Activity
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.util.concurrent.Executors

internal class GalleryMediaBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.sfyri.h_gallery_mobile/media"
        private const val PREFS_NAME = "h_gallery_mobile"
        private const val PREFS_GALLERIES = "galleries_v1"
    }

    private val repository = GalleryMediaRepository(activity.applicationContext)
    private val thumbnails = GalleryThumbnailProvider(activity.applicationContext, repository)
    private val viewerSources = GalleryViewerSourceProvider(activity.applicationContext, repository)
    private val executor = Executors.newFixedThreadPool(3)
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        thumbnails.clear()
        executor.shutdownNow()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanGallery" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                runAsync(result, "SCAN_FAILED") {
                    val scanResult = repository.scanGallery(galleryUuid, treeUri)
                    thumbnails.clear()
                    viewerSources.clearGallery(galleryUuid)
                    scanResult
                }
            }

            "getGalleryStats" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                runAsync(result, "STATS_FAILED") {
                    repository.stats(galleryUuid)
                }
            }

            "listMedia" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val limit = call.argument<Int>("limit") ?: 120
                val offset = call.argument<Int>("offset") ?: 0
                runAsync(result, "MEDIA_LIST_FAILED") {
                    repository.listMedia(galleryUuid, limit, offset)
                }
            }

            "loadThumbnail" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = call.argument<String>("syncUuid")?.trim().orEmpty()
                if (syncUuid.isEmpty()) {
                    result.error("INVALID_MEDIA", "Identità del media non valida.", null)
                    return
                }
                val maxPx = call.argument<Int>("maxPx") ?: 360
                runAsync(result, "THUMBNAIL_FAILED") {
                    thumbnails.loadThumbnail(galleryUuid, syncUuid, maxPx)
                }
            }

            "prepareViewerSource" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = call.argument<String>("syncUuid")?.trim().orEmpty()
                if (syncUuid.isEmpty()) {
                    result.error("INVALID_MEDIA", "Identità del media non valida.", null)
                    return
                }
                runAsync(result, "VIEWER_SOURCE_FAILED") {
                    viewerSources.prepare(galleryUuid, syncUuid)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun requiredGalleryUuid(
        call: MethodCall,
        result: MethodChannel.Result,
    ): String? {
        val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
        if (galleryUuid.isEmpty()) {
            result.error("INVALID_GALLERY", "Identità della galleria non valida.", null)
            return null
        }
        return galleryUuid
    }

    private fun resolveTreeUri(
        galleryUuid: String,
        result: MethodChannel.Result,
    ): Uri? {
        val raw = activity
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PREFS_GALLERIES, "[]") ?: "[]"
        val profiles = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
        for (index in 0 until profiles.length()) {
            val profile = profiles.optJSONObject(index) ?: continue
            if (profile.optString("galleryUuid") != galleryUuid) continue
            val uriText = profile.optString("treeUri")
            if (uriText.isBlank()) break
            val treeUri = Uri.parse(uriText)
            val hasAccess = activity.contentResolver.persistedUriPermissions.any { permission ->
                permission.uri == treeUri && permission.isReadPermission
            }
            if (!hasAccess) {
                result.error(
                    "GALLERY_ACCESS_LOST",
                    "H-Gallery non ha più accesso alla directory selezionata.",
                    null,
                )
                return null
            }
            return treeUri
        }

        result.error("GALLERY_NOT_FOUND", "Galleria non trovata.", null)
        return null
    }

    private fun runAsync(
        result: MethodChannel.Result,
        errorCode: String,
        operation: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = operation()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                val message = error.message?.takeIf { it.isNotBlank() }
                    ?: "Operazione non riuscita (${error.javaClass.simpleName})."
                activity.runOnUiThread { result.error(errorCode, message, null) }
            }
        }
    }
}
