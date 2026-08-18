package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import java.io.File

internal class GalleryTrashViewerSourceProvider(
    private val context: Context,
    private val repository: GalleryTrashRepository,
) {
    companion object {
        private const val CACHE_DIRECTORY = "hgallery-trash-viewer"
        private const val MAX_CACHE_FILES = 32
        private const val MAX_CACHE_BYTES = 192L * 1024L * 1024L
    }

    private val rootDirectory = File(context.cacheDir, CACHE_DIRECTORY)

    @Synchronized
    fun prepare(galleryUuid: String, syncUuid: String): Map<String, String> {
        val media = repository.mediaForViewer(galleryUuid, syncUuid)
            ?: throw IllegalStateException("Media non più disponibile nel cestino.")
        if (media.mediaType == "video") {
            return mapOf("kind" to "videoContentUri", "value" to media.documentUri)
        }
        val galleryDirectory = File(rootDirectory, galleryUuid).apply { mkdirs() }
        val extension = media.extension.lowercase().filter { it.isLetterOrDigit() }.ifBlank { "img" }
        val target = File(
            galleryDirectory,
            "$syncUuid-${media.sha256.take(16).ifBlank { "unknown" }}.$extension",
        )
        if (!target.isFile || target.length() <= 0L) copyToCache(Uri.parse(media.documentUri), target)
        target.setLastModified(System.currentTimeMillis())
        trimCache(galleryDirectory, target)
        return mapOf("kind" to "imageFile", "value" to target.absolutePath)
    }

    @Synchronized
    fun clearGallery(galleryUuid: String) {
        File(rootDirectory, galleryUuid).deleteRecursively()
    }

    @Synchronized
    fun clearAll() = rootDirectory.deleteRecursively()

    private fun copyToCache(source: Uri, target: File) {
        val temp = File(target.parentFile, "${target.name}.part")
        temp.delete()
        try {
            context.contentResolver.openInputStream(source)?.use { input ->
                temp.outputStream().buffered().use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("Android non consente di leggere il media.")
            if (temp.length() <= 0L) throw IllegalStateException("Il media letto è vuoto.")
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
            ?.toMutableList() ?: return
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
