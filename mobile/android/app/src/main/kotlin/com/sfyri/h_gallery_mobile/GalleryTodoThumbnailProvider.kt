package com.sfyri.h_gallery_mobile

import android.content.Context
import android.util.LruCache
import kotlin.math.max

internal class GalleryTodoThumbnailProvider(
    private val context: Context,
) {
    private val cache = object : LruCache<String, ByteArray>(24 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int {
            return max(1, value.size / 1024)
        }
    }

    fun loadThumbnail(galleryUuid: String, token: String, maxPx: Int): ByteArray? {
        val data = TodoMediaToken.decode(token)
        val safeMaxPx = maxPx.coerceIn(96, 1024)
        val cacheKey = "$galleryUuid:$token:$safeMaxPx"
        cache.get(cacheKey)?.let { return it }

        val bitmap = when (data.mediaType) {
            "video" -> GalleryThumbnailCodec.loadVideoFrame(context, data.uri)
            else -> GalleryThumbnailCodec.loadImage(context, data.uri, safeMaxPx)
        } ?: return null

        val scaled = GalleryThumbnailCodec.scaleDown(bitmap, safeMaxPx)
        val bytes = GalleryThumbnailCodec.encodeJpeg(scaled)
        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        if (bytes.isNotEmpty()) cache.put(cacheKey, bytes)
        return bytes.takeIf { it.isNotEmpty() }
    }

    fun clear() {
        cache.evictAll()
    }
}
