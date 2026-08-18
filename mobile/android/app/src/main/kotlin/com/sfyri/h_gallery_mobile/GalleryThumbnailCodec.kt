package com.sfyri.h_gallery_mobile

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.util.Size
import java.io.ByteArrayOutputStream
import kotlin.math.max

internal object GalleryThumbnailCodec {
    fun loadImage(context: Context, uri: Uri, maxPx: Int): Bitmap? {
        val safeMaxPx = maxPx.coerceIn(96, 1024)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val bitmap = context.contentResolver.loadThumbnail(
                    uri,
                    Size(safeMaxPx, safeMaxPx),
                    null,
                )
                if (bitmap.width > 0 && bitmap.height > 0) return bitmap
                bitmap.recycle()
            } catch (_: Exception) {
                // Alcuni DocumentsProvider non implementano thumbnail native.
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val width = info.size.width
                    val height = info.size.height
                    val largest = max(width, height)
                    if (largest > safeMaxPx * 2) {
                        val scale = (safeMaxPx * 2).toFloat() / largest.toFloat()
                        decoder.setTargetSize(
                            max(1, (width * scale).toInt()),
                            max(1, (height * scale).toInt()),
                        )
                    }
                }
            } catch (_: Exception) {
                // Fallback BitmapFactory per provider/formati meno recenti.
            }
        }

        return loadImageWithBitmapFactory(context, uri, safeMaxPx)
    }

    fun loadVideoFrame(context: Context, uri: Uri): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                return context.contentResolver.loadThumbnail(uri, Size(512, 512), null)
            } catch (_: Exception) {
                // Mantiene il percorso MediaMetadataRetriever già funzionante.
            }
        }

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
                // Il chiamante mostrerà il placeholder.
            }
        }
    }

    fun scaleDown(bitmap: Bitmap, maxPx: Int): Bitmap {
        val largestSide = max(bitmap.width, bitmap.height)
        if (largestSide <= maxPx) return bitmap
        val scale = maxPx.toFloat() / largestSide.toFloat()
        val width = max(1, (bitmap.width * scale).toInt())
        val height = max(1, (bitmap.height * scale).toInt())
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }

    fun encodeJpeg(bitmap: Bitmap, quality: Int = 86): ByteArray {
        var softwareCopy: Bitmap? = null
        val encodable = if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            bitmap.config == Bitmap.Config.HARDWARE
        ) {
            bitmap.copy(Bitmap.Config.ARGB_8888, false)?.also { softwareCopy = it } ?: bitmap
        } else {
            bitmap
        }
        return try {
            ByteArrayOutputStream().use { output ->
                if (!encodable.compress(Bitmap.CompressFormat.JPEG, quality, output)) {
                    return ByteArray(0)
                }
                output.toByteArray()
            }
        } finally {
            softwareCopy?.recycle()
        }
    }

    private fun loadImageWithBitmapFactory(context: Context, uri: Uri, maxPx: Int): Bitmap? {
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
}
