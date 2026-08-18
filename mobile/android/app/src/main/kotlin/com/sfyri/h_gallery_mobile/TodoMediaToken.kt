package com.sfyri.h_gallery_mobile

import android.net.Uri
import android.util.Base64

internal data class TodoMediaTokenData(
    val mediaType: String,
    val extension: String,
    val modifiedEpochMs: Long,
    val uri: Uri,
    val parentUri: Uri?,
    val relativePath: String,
)

internal object TodoMediaToken {
    private const val PREFIX_V1 = "todo"
    private const val PREFIX_V2 = "todo2"

    fun encode(
        mediaType: String,
        extension: String,
        modifiedEpochMs: Long,
        uri: Uri,
        parentUri: Uri,
        relativePath: String,
    ): String {
        val safeType = mediaType.takeIf { it == "image" || it == "video" }
            ?: throw IllegalArgumentException("Tipo media .toDo non valido.")
        val safeExtension = extension
            .lowercase()
            .filter { it.isLetterOrDigit() }
            .ifBlank { "bin" }
        return listOf(
            PREFIX_V2,
            safeType,
            safeExtension,
            modifiedEpochMs.coerceAtLeast(0L).toString(),
            encodeText(uri.toString()),
            encodeText(parentUri.toString()),
            encodeText(relativePath),
        ).joinToString(":")
    }

    fun decode(token: String): TodoMediaTokenData {
        return when {
            token.startsWith("$PREFIX_V2:") -> decodeV2(token)
            token.startsWith("$PREFIX_V1:") -> decodeV1(token)
            else -> throw IllegalArgumentException("Identità media .toDo non valida.")
        }
    }

    private fun decodeV2(token: String): TodoMediaTokenData {
        val parts = token.split(':', limit = 7)
        if (parts.size != 7 || parts[0] != PREFIX_V2) {
            throw IllegalArgumentException("Identità media .toDo non valida.")
        }
        val mediaType = validateMediaType(parts[1])
        val extension = sanitizeExtension(parts[2])
        val modifiedEpochMs = parts[3].toLongOrNull()?.coerceAtLeast(0L) ?: 0L
        val uri = decodeContentUri(parts[4])
        val parentUri = decodeContentUri(parts[5])
        val relativePath = decodeText(parts[6]).trim().ifBlank { ".toDo" }
        return TodoMediaTokenData(
            mediaType = mediaType,
            extension = extension,
            modifiedEpochMs = modifiedEpochMs,
            uri = uri,
            parentUri = parentUri,
            relativePath = relativePath,
        )
    }

    private fun decodeV1(token: String): TodoMediaTokenData {
        val parts = token.split(':', limit = 5)
        if (parts.size != 5 || parts[0] != PREFIX_V1) {
            throw IllegalArgumentException("Identità media .toDo non valida.")
        }
        val mediaType = validateMediaType(parts[1])
        val extension = sanitizeExtension(parts[2])
        val modifiedEpochMs = parts[3].toLongOrNull()?.coerceAtLeast(0L) ?: 0L
        val uriText = try {
            String(
                Base64.decode(parts[4], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),
                Charsets.UTF_8,
            )
        } catch (error: IllegalArgumentException) {
            throw IllegalArgumentException("Identità media .toDo non valida.", error)
        }
        val uri = Uri.parse(uriText)
        if (uri.scheme != "content") {
            throw IllegalArgumentException("URI media .toDo non valido.")
        }
        return TodoMediaTokenData(
            mediaType = mediaType,
            extension = extension,
            modifiedEpochMs = modifiedEpochMs,
            uri = uri,
            parentUri = null,
            relativePath = ".toDo/${uri.lastPathSegment.orEmpty()}",
        )
    }

    private fun validateMediaType(value: String): String {
        if (value != "image" && value != "video") {
            throw IllegalArgumentException("Tipo media .toDo non valido.")
        }
        return value
    }

    private fun sanitizeExtension(value: String): String {
        return value.lowercase().filter { it.isLetterOrDigit() }.ifBlank { "bin" }
    }

    private fun encodeText(value: String): String {
        return Base64.encodeToString(
            value.toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
    }

    private fun decodeText(value: String): String {
        return try {
            String(
                Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING),
                Charsets.UTF_8,
            )
        } catch (error: IllegalArgumentException) {
            throw IllegalArgumentException("Identità media .toDo non valida.", error)
        }
    }

    private fun decodeContentUri(value: String): Uri {
        val uri = Uri.parse(decodeText(value))
        if (uri.scheme != "content") {
            throw IllegalArgumentException("URI media .toDo non valido.")
        }
        return uri
    }
}
