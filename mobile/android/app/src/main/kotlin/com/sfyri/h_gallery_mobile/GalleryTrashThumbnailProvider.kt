package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import android.util.LruCache
import kotlin.math.max

internal class GalleryTrashThumbnailProvider(
    private val context: Context,
    private val repository: GalleryTrashRepository,
) {
    private val cache = object : LruCache<String, ByteArray>(32 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = max(1, value.size / 1024)
    }

    fun loadThumbnail(galleryUuid: String, syncUuid: String, maxPx: Int): ByteArray? {
        val safeMaxPx = maxPx.coerceIn(96, 1024)
        val key = "$galleryUuid:$syncUuid:$safeMaxPx"
        cache.get(key)?.let { return it }
        val media = repository.mediaForThumbnail(galleryUuid, syncUuid) ?: return null
        val uri = Uri.parse(media.first)
        val bitmap = if (media.second == "video") {
            GalleryThumbnailCodec.loadVideoFrame(context, uri)
        } else {
            GalleryThumbnailCodec.loadImage(context, uri, safeMaxPx)
        } ?: return null
        val scaled = GalleryThumbnailCodec.scaleDown(bitmap, safeMaxPx)
        val bytes = GalleryThumbnailCodec.encodeJpeg(scaled)
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        if (bytes.isNotEmpty()) cache.put(key, bytes)
        return bytes.takeIf { it.isNotEmpty() }
    }

    fun clear() = cache.evictAll()
}
