package com.sfyri.h_gallery_mobile

import android.content.Context
import java.io.File
import java.security.MessageDigest

internal class GalleryTodoViewerSourceProvider(
    private val context: Context,
) {
    companion object {
        private const val CACHE_DIRECTORY = "hgallery-todo-viewer"
        private const val MAX_CACHE_FILES = 36
        private const val MAX_CACHE_BYTES = 192L * 1024L * 1024L
    }

    private val rootDirectory = File(context.cacheDir, CACHE_DIRECTORY)

    @Synchronized
    fun prepare(galleryUuid: String, token: String): Map<String, String> {
        val data = TodoMediaToken.decode(token)
        if (data.mediaType == "video") {
            return mapOf(
                "kind" to "videoContentUri",
                "value" to data.uri.toString(),
            )
        }

        val galleryDirectory = File(rootDirectory, galleryUuid).apply { mkdirs() }
        if (!galleryDirectory.isDirectory) {
            throw IllegalStateException("Impossibile preparare la cache del viewer .toDo.")
        }

        val tokenHash = sha256(token).take(24)
        val extension = data.extension.ifBlank { "img" }
        val target = File(galleryDirectory, "$tokenHash.$extension")
        if (!target.isFile || target.length() <= 0L) {
            copyToCache(data.uri, target)
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

    private fun copyToCache(source: android.net.Uri, target: File) {
        val temp = File(target.parentFile, "${target.name}.part")
        temp.delete()
        try {
            context.contentResolver.openInputStream(source)?.use { input ->
                temp.outputStream().buffered().use { output ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Android non consente di leggere il media in .toDo.")
            if (temp.length() <= 0L) {
                throw IllegalStateException("Il media letto da .toDo è vuoto.")
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

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
    }
}
