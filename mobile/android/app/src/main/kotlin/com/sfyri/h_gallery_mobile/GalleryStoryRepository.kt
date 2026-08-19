package com.sfyri.h_gallery_mobile

import android.content.Context
import org.json.JSONObject

internal class GalleryStoryRepository(private val context: Context) {
    fun replaceFromManifest(galleryUuid: String, manifest: JSONObject) {
        if (!manifest.has("stories")) return
        val rawStories = manifest.optJSONArray("stories") ?: return
        val stories = mutableListOf<SyncedStoryRecord>()
        for (index in 0 until rawStories.length()) {
            val raw = rawStories.optJSONObject(index) ?: continue
            val relativePath = raw.optString("relativePath").trim().trim('/')
            if (relativePath.isEmpty()) continue
            val pagesArray = raw.optJSONArray("pages") ?: continue
            val pages = mutableListOf<SyncedStoryPageRecord>()
            for (pageIndex in 0 until pagesArray.length()) {
                val page = pagesArray.optJSONObject(pageIndex) ?: continue
                val pageNumber = page.optInt("pageNumber", pageIndex + 1)
                if (pageNumber < 1) continue
                val identity = readIdentity(page, pageNumber) ?: continue
                pages += identity
            }
            if (pages.isEmpty()) continue
            val cover = readIdentity(raw.optJSONObject("cover"), 0)
            val direction = raw.optString("readingDirection", "rtl").trim().lowercase()
            stories += SyncedStoryRecord(
                title = raw.optString("title").trim().ifBlank {
                    relativePath.substringAfterLast('/')
                },
                relativePath = relativePath,
                readingDirection = if (direction == "ltr") "ltr" else "rtl",
                aiGenerated = raw.optBoolean("aiGenerated", false),
                cover = cover,
                pages = pages.sortedBy { it.pageNumber },
            )
        }
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            database.replaceSyncedStories(stories)
        } finally {
            database.close()
        }
    }

    private fun readIdentity(raw: JSONObject?, pageNumber: Int): SyncedStoryPageRecord? {
        if (raw == null) return null
        val syncUuid = raw.optString("syncUuid").trim()
        val sha256 = raw.optString("sha256").trim().lowercase()
        val relativePath = raw.optString("relativePath").trim().trim('/')
        if (syncUuid.isEmpty() && sha256.isEmpty() && relativePath.isEmpty()) return null
        return SyncedStoryPageRecord(
            syncUuid = syncUuid,
            sha256 = sha256,
            relativePath = relativePath,
            pageNumber = pageNumber,
        )
    }
}
