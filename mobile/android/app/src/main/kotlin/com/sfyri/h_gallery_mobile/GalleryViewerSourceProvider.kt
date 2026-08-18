package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import java.io.File

internal class GalleryViewerSourceProvider(
    private val context: Context,
    private val repository: GalleryMediaRepository,
) {
    companion object {
        private const val CACHE_DIRECTORY = "hgallery-viewer"
        private const val MAX_CACHE_FILES = 48
        private const val MAX_CACHE_BYTES = 256L * 1024L * 1024L
    }

    private val rootDirectory = File(context.cacheDir, CACHE_DIRECTORY)

    @Synchronized
    fun prepare(galleryUuid: String, syncUuid: String): Map<String, String> {
        val media = repository.mediaForViewer(galleryUuid, syncUuid)
            ?: throw IllegalStateException("Media non più disponibile nella galleria.")

        if (media.mediaType == "video") {
            return mapOf(
                "kind" to "videoContentUri",
                "value" to media.documentUri,
            )
        }

        val galleryDirectory = File(rootDirectory, galleryUuid).apply { mkdirs() }
        if (!galleryDirectory.isDirectory) {
            throw IllegalStateException("Impossibile preparare la cache del viewer.")
        }

        val extension = media.extension
            .lowercase()
            .filter { it.isLetterOrDigit() }
            .ifBlank { "img" }
        val hashPart = media.sha256.take(16).ifBlank { "unknown" }
        val target = File(galleryDirectory, "$syncUuid-$hashPart.$extension")

        if (!target.isFile || target.length() <= 0L) {
            galleryDirectory.listFiles()
                ?.filter { it.name.startsWith("$syncUuid-") && it != target }
                ?.forEach { it.delete() }
            copyToCache(Uri.parse(media.documentUri), target)
        }

        target.setLastModified(System.currentTimeMillis())
        trimCache(galleryDirectory, target)
        return mapOf(
            "kind" to "imageFile",
            "value" to target.absolutePath,
        )
    }

    @Synchronized
    fun clearGallery(galleryUuid: String) {
        File(rootDirectory, galleryUuid).deleteRecursively()
    }

    @Synchronized
    fun clearAll() {
        rootDirectory.deleteRecursively()
    }

    private fun copyToCache(source: Uri, target: File) {
        val temp = File(target.parentFile, "${target.name}.part")
        temp.delete()
        try {
            context.contentResolver.openInputStream(source)?.use { input ->
                temp.outputStream().buffered().use { output ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Android non consente di leggere il media.")

            if (temp.length() <= 0L) {
                throw IllegalStateException("Il media letto è vuoto.")
            }
            target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
                temp.delete()
            }
        } catch (error: Exception) {
            temp.delete()
            target.delete()
            throw error
        }
    }

    private fun trimCache(directory: File, keep: File) {
        val files = directory.listFiles()
            ?.filter { it.isFile && !it.name.endsWith(".part") }
            ?.sortedByDescending { it.lastModified() }
            ?.toMutableList()
            ?: return

        var totalBytes = files.sumOf { it.length() }
        var fileCount = files.size
        for (file in files.asReversed()) {
            if (file == keep) continue
            if (fileCount <= MAX_CACHE_FILES && totalBytes <= MAX_CACHE_BYTES) break
            val length = file.length()
            if (file.delete()) {
                totalBytes -= length
                fileCount -= 1
            }
        }
    }
}
