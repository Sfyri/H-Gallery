package com.sfyri.h_gallery_mobile

import android.content.Context

internal class GalleryBrowseRepository(private val context: Context) {
    fun catalog(galleryUuid: String): Map<String, Any> {
        return withDatabase(galleryUuid) { it.browseCatalog() }
    }

    fun seriesDetail(galleryUuid: String, relativePath: String): Map<String, Any> {
        return withDatabase(galleryUuid) { it.seriesDetail(relativePath) }
    }

    fun filterCatalog(galleryUuid: String): Map<String, Any> {
        return withDatabase(galleryUuid) { it.filterCatalog() }
    }

    fun rankingFranchises(galleryUuid: String): List<Map<String, Any>> {
        return withDatabase(galleryUuid) { it.rankingFranchises() }
    }

    fun characterRanking(
        galleryUuid: String,
        limit: Int,
        franchiseId: Long?,
    ): List<Map<String, Any>> {
        return withDatabase(galleryUuid) { it.characterRanking(limit, franchiseId) }
    }

    fun adjustCharacterScore(
        galleryUuid: String,
        characterId: Long,
        delta: Int,
    ): Map<String, Any> {
        return withDatabase(galleryUuid) { it.adjustCharacterScore(characterId, delta) }
    }

    fun queryMedia(
        galleryUuid: String,
        text: String,
        kind: String,
        relativePrefix: String,
        tag: String,
        artist: String,
        aiOnly: Boolean,
        limit: Int,
        offset: Int,
    ): Map<String, Any> {
        return withDatabase(galleryUuid) {
            it.queryMedia(
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

    fun queryStories(
        galleryUuid: String,
        text: String,
        kind: String,
        relativePrefix: String,
        tag: String,
        artist: String,
        aiOnly: Boolean,
    ): List<Map<String, Any>> {
        return withDatabase(galleryUuid) {
            it.queryStories(text, kind, relativePrefix, tag, artist, aiOnly)
        }
    }

    fun storyPages(galleryUuid: String, relativePath: String): List<Map<String, Any>> {
        return withDatabase(galleryUuid) { it.storyPages(relativePath) }
    }

    fun mediaMetadata(galleryUuid: String, syncUuid: String): Map<String, Any> {
        return withDatabase(galleryUuid) { it.mediaMetadata(syncUuid) }
    }

    private inline fun <T> withDatabase(
        galleryUuid: String,
        operation: (GalleryIndexDatabase) -> T,
    ): T {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            operation(database)
        } finally {
            database.close()
        }
    }
}
