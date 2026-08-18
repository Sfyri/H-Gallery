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
