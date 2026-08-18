package com.sfyri.h_gallery_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.LruCache
import java.io.ByteArrayOutputStream
import kotlin.math.max

internal class GalleryThumbnailProvider(
    private val context: Context,
    private val repository: GalleryMediaRepository,
) {
    private val cache = object : LruCache<String, ByteArray>(32 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int {
            return max(1, value.size / 1024)
        }
    }

    fun loadThumbnail(galleryUuid: String, syncUuid: String, maxPx: Int): ByteArray? {
        val safeMaxPx = maxPx.coerceIn(96, 1024)
        val cacheKey = "$galleryUuid:$syncUuid:$safeMaxPx"
        cache.get(cacheKey)?.let { return it }

        val media = repository.mediaForThumbnail(galleryUuid, syncUuid) ?: return null
        val uri = Uri.parse(media.first)
        val bitmap = when (media.second) {
            "video" -> loadVideoFrame(uri)
            else -> loadImage(uri, safeMaxPx)
        } ?: return null

        val scaled = scaleDown(bitmap, safeMaxPx)
        val bytes = ByteArrayOutputStream().use { output ->
            scaled.compress(Bitmap.CompressFormat.JPEG, 84, output)
            output.toByteArray()
        }

        if (scaled !== bitmap) scaled.recycle()
        bitmap.recycle()
        if (bytes.isNotEmpty()) cache.put(cacheKey, bytes)
        return bytes.takeIf { it.isNotEmpty() }
    }

    fun clear() {
        cache.evictAll()
    }

    private fun loadImage(uri: Uri, maxPx: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        } ?: return null

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sampleSize = 1
        while (
            bounds.outWidth / sampleSize > maxPx * 2 ||
            bounds.outHeight / sampleSize > maxPx * 2
        ) {
            sampleSize *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        }
    }

    private fun loadVideoFrame(uri: Uri): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.getFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Nessuna azione: il provider mostrerà un placeholder.
            }
        }
    }

    private fun scaleDown(bitmap: Bitmap, maxPx: Int): Bitmap {
        val largestSide = max(bitmap.width, bitmap.height)
        if (largestSide <= maxPx) return bitmap
        val scale = maxPx.toFloat() / largestSide.toFloat()
        val width = max(1, (bitmap.width * scale).toInt())
        val height = max(1, (bitmap.height * scale).toInt())
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }
}
