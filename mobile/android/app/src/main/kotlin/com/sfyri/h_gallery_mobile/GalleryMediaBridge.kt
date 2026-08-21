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
    private val browse = GalleryBrowseRepository(activity.applicationContext)
    private val thumbnails = GalleryThumbnailProvider(activity.applicationContext, repository)
    private val viewerSources = GalleryViewerSourceProvider(activity.applicationContext, repository)

    private val todoRepository = GalleryTodoMediaRepository(activity.applicationContext)
    private val todoThumbnails = GalleryTodoThumbnailProvider(activity.applicationContext)
    private val todoViewerSources = GalleryTodoViewerSourceProvider(activity.applicationContext)
    private val organization = GalleryOrganizationRepository(activity.applicationContext)
    private val metadataEditor = GalleryMediaMetadataEditor(activity.applicationContext)
    private val trash = GalleryTrashRepository(activity.applicationContext)
    private val trashThumbnails = GalleryTrashThumbnailProvider(activity.applicationContext, trash)
    private val trashViewerSources = GalleryTrashViewerSourceProvider(activity.applicationContext, trash)

    private val executor = Executors.newFixedThreadPool(3)
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        thumbnails.clear()
        todoThumbnails.clear()
        viewerSources.clearAll()
        todoViewerSources.clearAll()
        trashThumbnails.clear()
        trashViewerSources.clearAll()
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

            "getBrowseCatalog" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                runAsync(result, "BROWSE_CATALOG_FAILED") {
                    browse.catalog(galleryUuid)
                }
            }

            "getSeriesDetail" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
                if (relativePath.isEmpty()) {
                    result.error("INVALID_SERIES", "Serie non valida.", null)
                    return
                }
                runAsync(result, "SERIES_DETAIL_FAILED") {
                    browse.seriesDetail(galleryUuid, relativePath)
                }
            }

            "getFilterCatalog" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                runAsync(result, "FILTER_CATALOG_FAILED") {
                    browse.filterCatalog(galleryUuid)
                }
            }

            "getRankingFranchises" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                runAsync(result, "RANKING_FRANCHISES_FAILED") {
                    browse.rankingFranchises(galleryUuid)
                }
            }

            "getCharacterRanking" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val limit = (call.argument<Int>("limit") ?: 500).coerceIn(1, 500)
                val franchiseId = call.argument<Number>("franchiseId")?.toLong()
                runAsync(result, "CHARACTER_RANKING_FAILED") {
                    browse.characterRanking(galleryUuid, limit, franchiseId)
                }
            }

            "updateCharacterScore" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val characterId = call.argument<Number>("characterId")?.toLong()
                val delta = call.argument<Int>("delta")
                if (characterId == null || characterId <= 0L || (delta != -1 && delta != 1)) {
                    result.error(
                        "INVALID_CHARACTER_SCORE",
                        "Personaggio o variazione del punteggio non validi.",
                        null,
                    )
                    return
                }
                runAsync(result, "CHARACTER_SCORE_UPDATE_FAILED") {
                    browse.adjustCharacterScore(galleryUuid, characterId, delta)
                }
            }

            "queryMedia" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val text = call.argument<String>("text")?.trim().orEmpty()
                val kind = call.argument<String>("kind")?.trim().orEmpty()
                val relativePrefix = call.argument<String>("relativePrefix")?.trim().orEmpty()
                val tag = call.argument<String>("tag")?.trim().orEmpty()
                val artist = call.argument<String>("artist")?.trim().orEmpty()
                val aiOnly = call.argument<Boolean>("aiOnly") ?: false
                val limit = call.argument<Int>("limit") ?: 120
                val offset = call.argument<Int>("offset") ?: 0
                runAsync(result, "MEDIA_QUERY_FAILED") {
                    browse.queryMedia(
                        galleryUuid = galleryUuid,
                        text = text,
                        kind = kind,
                        relativePrefix = relativePrefix,
                        tag = tag,
                        artist = artist,
                        aiOnly = aiOnly,
                        limit = limit,
                        offset = offset,
                    )
                }
            }

            "queryStories" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val text = call.argument<String>("text")?.trim().orEmpty()
                val kind = call.argument<String>("kind")?.trim().orEmpty()
                val relativePrefix = call.argument<String>("relativePrefix")?.trim().orEmpty()
                val tag = call.argument<String>("tag")?.trim().orEmpty()
                val artist = call.argument<String>("artist")?.trim().orEmpty()
                val aiOnly = call.argument<Boolean>("aiOnly") ?: false
                runAsync(result, "STORY_QUERY_FAILED") {
                    browse.queryStories(
                        galleryUuid, text, kind, relativePrefix, tag, artist, aiOnly,
                    )
                }
            }
            "getStoryPages" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
                if (relativePath.isEmpty()) {
                    result.error("INVALID_STORY", "Storia non valida.", null)
                    return
                }
                runAsync(result, "STORY_PAGES_FAILED") {
                    browse.storyPages(galleryUuid, relativePath)
                }
            }
            "getMediaMetadata" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "MEDIA_METADATA_FAILED") {
                    browse.mediaMetadata(galleryUuid, syncUuid)
                }
            }

            "getEditableMediaMetadata" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "EDITABLE_MEDIA_METADATA_FAILED") {
                    metadataEditor.read(galleryUuid, syncUuid)
                }
            }

            "updateMediaMetadata" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                val characterIds = numberListArgument(call.arguments, "characterIds")
                val tags = stringListArgument(call.arguments, "tags")
                val artists = stringListArgument(call.arguments, "artists")
                val aiGenerated = call.argument<Boolean>("aiGenerated") ?: false
                runAsync(result, "MEDIA_METADATA_UPDATE_FAILED") {
                    val value = metadataEditor.update(
                        galleryUuid = galleryUuid,
                        syncUuid = syncUuid,
                        characterIds = characterIds,
                        tags = tags,
                        artists = artists,
                        aiGenerated = aiGenerated,
                    )
                    clearGalleryCaches(galleryUuid)
                    value
                }
            }

            "loadThumbnail" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                val maxPx = call.argument<Int>("maxPx") ?: 360
                runAsync(result, "THUMBNAIL_FAILED") {
                    thumbnails.loadThumbnail(galleryUuid, syncUuid, maxPx)
                }
            }

            "prepareViewerSource" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "VIEWER_SOURCE_FAILED") {
                    viewerSources.prepare(galleryUuid, syncUuid)
                }
            }

            "getTodoStats" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                runAsync(result, "TODO_STATS_FAILED") {
                    todoRepository.stats(treeUri)
                }
            }

            "listTodoMedia" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val limit = call.argument<Int>("limit") ?: 120
                val offset = call.argument<Int>("offset") ?: 0
                runAsync(result, "TODO_LIST_FAILED") {
                    todoRepository.listMedia(treeUri, limit, offset)
                }
            }

            "loadTodoThumbnail" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                val maxPx = call.argument<Int>("maxPx") ?: 360
                runAsync(result, "TODO_THUMBNAIL_FAILED") {
                    todoThumbnails.loadThumbnail(galleryUuid, syncUuid, maxPx)
                }
            }

            "prepareTodoViewerSource" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "TODO_VIEWER_SOURCE_FAILED") {
                    todoViewerSources.prepare(galleryUuid, syncUuid)
                }
            }

            "getOrganizationCatalog" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                runAsync(result, "ORGANIZATION_CATALOG_FAILED") {
                    organization.getCatalog(galleryUuid, treeUri)
                }
            }

            "createFranchise" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val name = call.argument<String>("name")?.trim().orEmpty()
                val code = call.argument<String>("code")?.trim().orEmpty()
                runAsync(result, "FRANCHISE_CREATE_FAILED") {
                    organization.createFranchise(galleryUuid, treeUri, name, code)
                }
            }

            "createCharacter" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val franchiseId = numberArgument(call.arguments, "franchiseId")
                    ?: run {
                        result.error("INVALID_FRANCHISE", "Serie non valida.", null)
                        return
                    }
                val name = call.argument<String>("name")?.trim().orEmpty()
                runAsync(result, "CHARACTER_CREATE_FAILED") {
                    organization.createCharacter(galleryUuid, treeUri, franchiseId, name)
                }
            }

            "previewTodoOrganization" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val tokens = stringListArgument(call.arguments, "tokens")
                val characterIds = numberListArgument(call.arguments, "characterIds")
                val aiGenerated = call.argument<Boolean>("aiGenerated") ?: false
                runAsync(result, "ORGANIZATION_PREVIEW_FAILED") {
                    organization.preview(
                        galleryUuid,
                        treeUri,
                        tokens,
                        characterIds,
                        aiGenerated,
                    )
                }
            }

            "organizeTodoMediaBatch" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val tokens = stringListArgument(call.arguments, "tokens")
                val characterIds = numberListArgument(call.arguments, "characterIds")
                val tags = stringListArgument(call.arguments, "tags")
                val artists = stringListArgument(call.arguments, "artists")
                val aiGenerated = call.argument<Boolean>("aiGenerated") ?: false
                val allowDuplicates = call.argument<Boolean>("allowDuplicates") ?: false
                runAsync(result, "ORGANIZATION_FAILED") {
                    val value = organization.organizeBatch(
                        galleryUuid = galleryUuid,
                        treeUri = treeUri,
                        tokens = tokens,
                        characterIds = characterIds,
                        tags = tags,
                        artists = artists,
                        aiGenerated = aiGenerated,
                        allowDuplicates = allowDuplicates,
                    )
                    thumbnails.clear()
                    todoThumbnails.clear()
                    viewerSources.clearGallery(galleryUuid)
                    todoViewerSources.clearGallery(galleryUuid)
                    value
                }
            }

            "trashMedia" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "TRASH_FAILED") {
                    trash.moveToTrash(galleryUuid, treeUri, syncUuid)
                    clearGalleryCaches(galleryUuid)
                    null
                }
            }

            "getTrashStats", "getTrashMediaStats" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                runAsync(result, "TRASH_STATS_FAILED") { trash.stats(galleryUuid) }
            }

            "listTrashItems" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val limit = call.argument<Int>("limit") ?: 120
                val offset = call.argument<Int>("offset") ?: 0
                runAsync(result, "TRASH_LIST_FAILED") { trash.listItems(galleryUuid, limit, offset) }
            }

            "loadTrashThumbnail" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                val maxPx = call.argument<Int>("maxPx") ?: 360
                runAsync(result, "TRASH_THUMBNAIL_FAILED") {
                    trashThumbnails.loadThumbnail(galleryUuid, syncUuid, maxPx)
                }
            }

            "prepareTrashViewerSource" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val syncUuid = requiredMediaId(call, result) ?: return
                runAsync(result, "TRASH_VIEWER_SOURCE_FAILED") {
                    trashViewerSources.prepare(galleryUuid, syncUuid)
                }
            }

            "restoreTrashItem" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                val treeUri = resolveTreeUri(galleryUuid, result) ?: return
                val trashId = requiredTrashId(call, result) ?: return
                val autoRename = call.argument<Boolean>("autoRename") ?: false
                runAsync(result, "TRASH_RESTORE_FAILED") {
                    val value = trash.restore(galleryUuid, treeUri, trashId, autoRename)
                    clearGalleryCaches(galleryUuid)
                    value
                }
            }

            "permanentlyDeleteTrashItem" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                val trashId = requiredTrashId(call, result) ?: return
                runAsync(result, "TRASH_DELETE_FAILED") {
                    trash.permanentlyDelete(galleryUuid, trashId)
                    clearGalleryCaches(galleryUuid)
                    null
                }
            }

            "emptyTrash" -> {
                val galleryUuid = requiredGalleryUuid(call, result) ?: return
                resolveTreeUri(galleryUuid, result) ?: return
                runAsync(result, "TRASH_EMPTY_FAILED") {
                    val value = trash.emptyTrash(galleryUuid)
                    clearGalleryCaches(galleryUuid)
                    value
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

    private fun requiredTrashId(
        call: MethodCall,
        result: MethodChannel.Result,
    ): Long? {
        val value = numberArgument(call.arguments, "trashId")
        if (value == null || value <= 0L) {
            result.error("INVALID_TRASH_ITEM", "Elemento del cestino non valido.", null)
            return null
        }
        return value
    }

    private fun requiredMediaId(
        call: MethodCall,
        result: MethodChannel.Result,
    ): String? {
        val syncUuid = call.argument<String>("syncUuid")?.trim().orEmpty()
        if (syncUuid.isEmpty()) {
            result.error("INVALID_MEDIA", "Identità del media non valida.", null)
            return null
        }
        return syncUuid
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
                permission.uri == treeUri && permission.isReadPermission && permission.isWritePermission
            }
            if (!hasAccess) {
                result.error(
                    "GALLERY_ACCESS_LOST",
                    "H-Gallery non ha più accesso completo alla directory selezionata.",
                    null,
                )
                return null
            }
            return treeUri
        }

        result.error("GALLERY_NOT_FOUND", "Galleria non trovata.", null)
        return null
    }

    private fun numberArgument(arguments: Any?, key: String): Long? {
        val map = arguments as? Map<*, *> ?: return null
        val value = map[key]
        return when (value) {
            is Int -> value.toLong()
            is Long -> value
            is Number -> value.toLong()
            else -> value?.toString()?.toLongOrNull()
        }
    }

    private fun numberListArgument(arguments: Any?, key: String): List<Long> {
        val map = arguments as? Map<*, *> ?: return emptyList()
        val values = map[key] as? List<*> ?: return emptyList()
        return values.mapNotNull { value ->
            when (value) {
                is Int -> value.toLong()
                is Long -> value
                is Number -> value.toLong()
                else -> value?.toString()?.toLongOrNull()
            }
        }
    }

    private fun stringListArgument(arguments: Any?, key: String): List<String> {
        val map = arguments as? Map<*, *> ?: return emptyList()
        val values = map[key] as? List<*> ?: return emptyList()
        return values.mapNotNull { value ->
            value?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        }
    }

    private fun clearGalleryCaches(galleryUuid: String) {
        thumbnails.clear()
        todoThumbnails.clear()
        trashThumbnails.clear()
        viewerSources.clearGallery(galleryUuid)
        todoViewerSources.clearGallery(galleryUuid)
        trashViewerSources.clearGallery(galleryUuid)
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
