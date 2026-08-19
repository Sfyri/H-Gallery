package com.sfyri.h_gallery_mobile

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLConnection
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

internal class GallerySyncBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.sfyri.h_gallery_mobile/sync"
        private const val PREFS_NAME = "h_gallery_mobile"
        private const val PREFS_GALLERIES = "galleries_v1"
    }

    private data class ConnectionInfo(
        val galleryUuid: String,
        val galleryName: String,
        val treeUri: Uri,
        val address: String,
        val port: Int,
        val deviceId: String,
        val token: String,
        val syncGroupUuid: String,
        val windowsGalleryUuid: String,
    )

    private data class SyncItem(
        val syncUuid: String,
        val relativePath: String,
        val filename: String,
        val extension: String,
        val mediaType: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
        val sha256: String,
        val documentUri: String = "",
        val aiGenerated: Boolean = false,
        val characters: List<Map<String, String>> = emptyList(),
        val tags: List<String> = emptyList(),
        val artists: List<String> = emptyList(),
    )

    private data class SyncTombstone(
        val fileUuid: String,
        val sha256: String,
        val mediaType: String,
        val lastRelativePath: String,
        val deletedAt: String = "",
        val originPeerUuid: String = "",
        val createdLocally: Boolean = false,
        val syncGroupUuid: String = "",
    )

    private data class TombstoneMatch(
        val item: SyncItem? = null,
        val conflict: String? = null,
        val matchKind: String = "",
    )

    private data class DeletionApplyStats(
        val movedToTrash: Int = 0,
        val alreadyAbsent: Int = 0,
        val conflicts: List<Map<String, String>> = emptyList(),
    )

    private data class AndroidDeletionPreflight(
        val resolved: List<Pair<SyncTombstone, TombstoneMatch>>,
        val conflicts: List<Map<String, String>>,
    )

    private data class DownloadedItem(
        val remote: SyncItem,
        val actualRelativePath: String,
    )

    private data class TransferFailure(
        val direction: String,
        val filename: String,
        val message: String,
        val network: Boolean,
    )

    private data class TransferOutcome<T>(
        val value: T? = null,
        val failure: TransferFailure? = null,
    )

    private data class MetadataMergeStats(
        val changedFiles: Int = 0,
        val aiUpdated: Int = 0,
        val tagsAdded: Int = 0,
        val artistsAdded: Int = 0,
        val characterLinksAdded: Int = 0,
        val createdFranchises: Int = 0,
        val createdCharacters: Int = 0,
    )

    private data class TagEnsureResult(
        val id: Long,
        val created: Boolean = false,
        val promoted: Boolean = false,
    )

    private data class CharacterEnsureResult(
        val id: Long?,
        val createdFranchise: Boolean = false,
        val createdCharacter: Boolean = false,
    )

    private class SyncCancelledException : RuntimeException()

    private val repository = GalleryMediaRepository(activity.applicationContext)
    private val trashRepository = GalleryTrashRepository(activity.applicationContext)
    private val metadataBaselineStore = GalleryMetadataBaselineStore(activity.applicationContext)
    private val executor = Executors.newSingleThreadExecutor()
    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(::handleMethodCall)
    }
    @Volatile
    private var cancelRequested = false

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "analyzeSync" -> runAsync(result, "SYNC_ANALYZE_FAILED") {
                val info = connectionInfo(call)
                analyze(info)
            }
            "runSync" -> runAsync(result, "SYNC_RUN_FAILED") {
                val info = connectionInfo(call)
                runSync(info)
            }
            "getSyncGroup" -> runAsync(result, "SYNC_GROUP_READ_FAILED") {
                val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
                require(galleryUuid.isNotEmpty()) { "Galleria Android non valida." }
                readSyncGroup(galleryUuid)
            }
            "setSyncGroup" -> runAsync(result, "SYNC_GROUP_WRITE_FAILED") {
                val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
                val syncGroupUuid = call.argument<String>("syncGroupUuid")?.trim().orEmpty()
                require(galleryUuid.isNotEmpty()) { "Galleria Android non valida." }
                writeSyncGroup(galleryUuid, syncGroupUuid)
                null
            }
            "getSyncStatus" -> runAsync(result, "SYNC_STATUS_READ_FAILED") {
                val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
                require(galleryUuid.isNotEmpty()) { "Galleria Android non valida." }
                readSyncStatus(galleryUuid)
            }
            "cancelSync" -> {
                cancelRequested = true
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connectionInfo(call: MethodCall): ConnectionInfo {
        val galleryUuid = call.argument<String>("galleryUuid")?.trim().orEmpty()
        val galleryName = call.argument<String>("galleryName")?.trim().orEmpty().ifBlank { "H-Gallery Android" }
        val address = call.argument<String>("address")?.trim().orEmpty()
        val port = call.argument<Int>("port") ?: 8000
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        val token = call.argument<String>("token")?.trim().orEmpty()
        val syncGroupUuid = call.argument<String>("syncGroupUuid")?.trim().orEmpty()
        val windowsGalleryUuid = call.argument<String>("windowsGalleryUuid")?.trim().orEmpty()
        if (galleryUuid.isEmpty() || address.isEmpty() || deviceId.isEmpty() || token.isEmpty() ||
            syncGroupUuid.isEmpty() || windowsGalleryUuid.isEmpty()) {
            throw IllegalArgumentException("Dati di collegamento M7 incompleti.")
        }
        val localGroup = readSyncGroup(galleryUuid)
        if (localGroup.isEmpty() || localGroup != syncGroupUuid) {
            throw IllegalStateException("La galleria Android non appartiene al gruppo di sincronizzazione richiesto.")
        }
        return ConnectionInfo(
            galleryUuid = galleryUuid,
            galleryName = galleryName,
            treeUri = resolveTreeUri(galleryUuid),
            address = address,
            port = port,
            deviceId = deviceId,
            token = token,
            syncGroupUuid = syncGroupUuid,
            windowsGalleryUuid = windowsGalleryUuid,
        )
    }

    private fun analyze(info: ConnectionInfo): Map<String, Any> {
        progress("scan", 0, 1, "Indicizzazione galleria Android")
        repository.scanGallery(info.galleryUuid, info.treeUri)
        val local = localItems(info.galleryUuid)
        val localTombstones = localTombstones(info.galleryUuid, info.syncGroupUuid)
        progress("compare", 0, 1, "Confronto con Windows")
        val remoteManifest = fetchManifest(info)
        val remote = parseManifestItems(remoteManifest)
        val remoteTombstones = parseManifestTombstones(remoteManifest, info.syncGroupUuid)
        val localBaselines = metadataBaselineStore.read(
            info.galleryUuid,
            info.syncGroupUuid,
            info.windowsGalleryUuid,
        )
        val remoteBaselines = parseManifestBaselines(remoteManifest, info.galleryUuid)
        return plan(
            local,
            remote,
            localTombstones,
            remoteTombstones,
            localBaselines,
            remoteBaselines,
        ).toMutableMap().apply {
            put("androidCount", local.size)
            put("windowsCount", remote.size)
            put("windowsGalleryUuid", remoteManifest.optString("galleryUuid"))
            put("windowsGalleryName", remoteManifest.optString("galleryName", "H-Gallery"))
        }
    }

    private fun runSync(info: ConnectionInfo): Map<String, Any> {
        val started = System.currentTimeMillis()
        cancelRequested = false
        progress("scan", 0, 1, "Aggiornamento indice Android")
        repository.scanGallery(info.galleryUuid, info.treeUri)
        val initialLocal = localItems(info.galleryUuid)
        val initialLocalTombstones = localTombstones(info.galleryUuid, info.syncGroupUuid)
        var remoteManifest = fetchManifest(info)
        var remote = parseManifestItems(remoteManifest)
        var remoteTombstones = parseManifestTombstones(remoteManifest, info.syncGroupUuid)
        val remoteGalleryUuid = remoteManifest.optString("galleryUuid")
        var localBaselines = metadataBaselineStore.read(
            info.galleryUuid,
            info.syncGroupUuid,
            info.windowsGalleryUuid,
        )
        var remoteBaselines = parseManifestBaselines(remoteManifest, info.galleryUuid)
        val initialPlan = plan(
            initialLocal,
            remote,
            initialLocalTombstones,
            remoteTombstones,
            localBaselines,
            remoteBaselines,
        )
        val initialDeletionConflicts = (initialPlan["deletionConflicts"] as? Int) ?: 0
        val initialMetadataResolutionConflicts =
            (initialPlan["metadataResolutionConflicts"] as? Int) ?: 0
        if (initialDeletionConflicts > 0) {
            throw IllegalStateException(
                "M7.5 ha rilevato $initialDeletionConflicts cancellazioni ambigue. " +
                    "Nessun file è stato modificato: risolvi i conflitti indicati e analizza di nuovo.",
            )
        }
        if (initialMetadataResolutionConflicts > 0) {
            throw IllegalStateException(
                "M7.6 ha rilevato $initialMetadataResolutionConflicts modifiche metadata concorrenti. " +
                    "Nessun merge viene avviato: risolvi manualmente il conflitto indicato e analizza di nuovo.",
            )
        }

        // Preflight incrociato PRIMA di qualsiasi mutazione. Entrambi i lati
        // devono dimostrare che ogni tombstone ha un bersaglio non ambiguo.
        // La validazione viene ripetuta anche durante l'applicazione per
        // proteggere da cambiamenti avvenuti tra preflight e commit.
        progress("deletions", 0, 2, "Verifica eliminazioni su entrambi i dispositivi")
        val windowsPreflightConflicts = validateLocalTombstonesOnWindows(info, initialLocalTombstones)
        val androidPreflightConflicts = preflightRemoteTombstones(info, remoteTombstones).conflicts
        val crossPreflightConflicts = windowsPreflightConflicts + androidPreflightConflicts
        if (crossPreflightConflicts.isNotEmpty()) {
            throw IllegalStateException(
                "M7.5 ha bloccato ${crossPreflightConflicts.size} cancellazioni prima di modificare i file. " +
                    crossPreflightConflicts.first()["message"].orEmpty(),
            )
        }

        // Il backup Windows resta il punto di ingresso della sessione. Le
        // cancellazioni vengono applicate solo dopo preflight completo e backup.
        postJson(info, "/api/mobile/sync/begin", basePayload(info))

        val windowsDeletion = sendLocalTombstonesToWindows(info, initialLocalTombstones)
        if (windowsDeletion.conflicts.isNotEmpty()) {
            throw IllegalStateException(
                "Windows ha bloccato ${windowsDeletion.conflicts.size} cancellazioni per sicurezza. " +
                    windowsDeletion.conflicts.first()["message"].orEmpty(),
            )
        }
        progress("deletions", 1, 2, "Applicazione eliminazioni su Android")
        val androidDeletion = applyRemoteTombstones(info, remoteTombstones)
        if (androidDeletion.conflicts.isNotEmpty()) {
            throw IllegalStateException(
                "Android ha bloccato ${androidDeletion.conflicts.size} cancellazioni per sicurezza. " +
                    androidDeletion.conflicts.first()["message"].orEmpty(),
            )
        }
        progress("deletions", 2, 2, "Eliminazioni allineate")

        // Ricalcola entrambi gli inventari dopo la fase distruttiva. In questo
        // modo nessun media appena eliminato può rientrare nei trasferimenti.
        repository.scanGallery(info.galleryUuid, info.treeUri)
        var localBefore = localItems(info.galleryUuid)
        var localTombstonesNow = localTombstones(info.galleryUuid, info.syncGroupUuid)
        remoteManifest = fetchManifest(info)
        remote = parseManifestItems(remoteManifest)
        remoteTombstones = parseManifestTombstones(remoteManifest, info.syncGroupUuid)
        val blockedHashes = (localTombstonesNow + remoteTombstones)
            .map { it.sha256.lowercase(Locale.ROOT) }
            .filter(String::isNotBlank)
            .toSet()
        val liveLocal = localBefore.filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }
        val liveRemote = remote.filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }
        val localByHash = liveLocal.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = liveRemote.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val downloads = remoteByHash.filterKeys { it !in localByHash }.values.toList()
        val uploads = localByHash.filterKeys { it !in remoteByHash }.values.toList()

        val downloaded = mutableListOf<DownloadedItem>()
        val failures = mutableListOf<TransferFailure>()
        var successfulDownloads = 0
        var successfulUploads = 0
        var failedDownloads = 0
        var failedUploads = 0
        var attemptedDownloads = 0
        var attemptedUploads = 0
        var interrupted = false
        var cancelled = false

        for (item in downloads) {
            if (cancelRequested) {
                cancelled = true
                break
            }
            val outcome = try {
                transferWithRetry(
                    direction = "download",
                    phase = "download",
                    item = item,
                    processed = attemptedDownloads,
                    total = downloads.size,
                    succeeded = successfulDownloads,
                    failed = failedDownloads,
                ) { downloadItem(info, item) }
            } catch (_: SyncCancelledException) {
                cancelled = true
                break
            }
            attemptedDownloads += 1
            if (outcome.value != null) {
                downloaded += outcome.value
                successfulDownloads += 1
            } else if (outcome.failure != null) {
                failures += outcome.failure
                failedDownloads += 1
                if (outcome.failure.network) interrupted = true
            }
            progress(
                "download",
                attemptedDownloads,
                downloads.size,
                item.filename,
                successfulDownloads,
                failedDownloads,
            )
            if (interrupted) break
        }

        if (downloaded.isNotEmpty()) {
            progress("scan", 0, 1, "Aggiornamento file ricevuti")
            repository.scanGallery(info.galleryUuid, info.treeUri)
            remapDownloadedUuids(info.galleryUuid, downloaded)
        }

        // M7.6 calcola lo stato metadata desiderato con un three-way merge.
        // Se il baseline non è condiviso il resolver resta deliberatamente
        // additivo; una rimozione viene applicata solo con baseline verificato.
        val remoteForMetadata = remote.filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }
        val localForMetadata = localItems(info.galleryUuid)
            .filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }
        localBaselines = metadataBaselineStore.read(
            info.galleryUuid,
            info.syncGroupUuid,
            info.windowsGalleryUuid,
        )
        remoteBaselines = parseManifestBaselines(remoteManifest, info.galleryUuid)
        val desiredAndroidMetadata = resolvedMetadataItems(
            localForMetadata,
            remoteForMetadata,
            localBaselines,
            remoteBaselines,
        )
        val androidMetadataTotal = desiredAndroidMetadata.size.coerceAtLeast(1)
        progress("metadata_android", 0, androidMetadataTotal, "Allineamento metadata su Android")
        val androidMetadata = mergeRemoteMetadata(info.galleryUuid, desiredAndroidMetadata)
        progress("metadata_android", androidMetadataTotal, androidMetadataTotal, "Metadata Android aggiornati")

        if (!interrupted && !cancelled) {
            for (item in uploads) {
                if (cancelRequested) {
                    cancelled = true
                    break
                }
                val outcome = try {
                    transferWithRetry(
                        direction = "upload",
                        phase = "upload",
                        item = item,
                        processed = attemptedUploads,
                        total = uploads.size,
                        succeeded = successfulUploads,
                        failed = failedUploads,
                    ) {
                        uploadItem(info, item)
                        true
                    }
                } catch (_: SyncCancelledException) {
                    cancelled = true
                    break
                }
                attemptedUploads += 1
                if (outcome.value == true) {
                    successfulUploads += 1
                } else if (outcome.failure != null) {
                    failures += outcome.failure
                    failedUploads += 1
                    if (outcome.failure.network) interrupted = true
                }
                progress(
                    "upload",
                    attemptedUploads,
                    uploads.size,
                    item.filename,
                    successfulUploads,
                    failedUploads,
                )
                if (interrupted) break
            }
        }

        var metadataMergedWindows = 0
        var metadataChangedWindows = 0
        var windowsCreatedFranchises = 0
        var windowsCreatedCharacters = 0
        var unresolvedWindows = 0
        var windowsCount = remote.size + successfulUploads - windowsDeletion.movedToTrash

        if (cancelRequested) cancelled = true
        if (!interrupted && !cancelled) {
            try {
                progress("finalize_windows", 0, 1, "Aggiornamento indice Windows")
                val finalize = postJson(info, "/api/mobile/sync/finalize", basePayload(info))
                windowsCount = finalize.optInt("count", windowsCount)

                val metadataRemoteManifest = fetchManifest(info)
                val currentTombstoneHashes = (
                    localTombstones(info.galleryUuid, info.syncGroupUuid) +
                        parseManifestTombstones(metadataRemoteManifest, info.syncGroupUuid)
                    )
                    .map { it.sha256.lowercase(Locale.ROOT) }
                    .toSet()
                val localAfterFinalize = localItems(info.galleryUuid)
                    .filter { it.sha256.isNotBlank() && it.sha256.lowercase(Locale.ROOT) !in currentTombstoneHashes }
                val remoteAfterFinalize = parseManifestItems(metadataRemoteManifest)
                    .filter { it.sha256.isNotBlank() && it.sha256.lowercase(Locale.ROOT) !in currentTombstoneHashes }
                localBaselines = metadataBaselineStore.read(
                    info.galleryUuid,
                    info.syncGroupUuid,
                    info.windowsGalleryUuid,
                )
                remoteBaselines = parseManifestBaselines(metadataRemoteManifest, info.galleryUuid)
                val desiredWindowsMetadata = resolvedMetadataItems(
                    localAfterFinalize,
                    remoteAfterFinalize,
                    localBaselines,
                    remoteBaselines,
                )
                val chunks = desiredWindowsMetadata.chunked(100)
                chunks.forEachIndexed { index, chunk ->
                    if (cancelRequested) throw SyncCancelledException()
                    progress(
                        "metadata_windows",
                        index,
                        chunks.size.coerceAtLeast(1),
                        "Allineamento metadata su Windows",
                    )
                    val payload = basePayload(info).apply {
                        put("items", JSONArray().apply {
                            chunk.forEach {
                                put(itemJson(it, includeDocument = false).apply {
                                    put("replaceMetadata", true)
                                })
                            }
                        })
                    }
                    val response = postJson(info, "/api/mobile/sync/metadata", payload)
                    metadataMergedWindows += response.optInt("merged", 0)
                    metadataChangedWindows += response.optInt("changedFiles", 0)
                    windowsCreatedFranchises += response.optInt("createdFranchises", 0)
                    windowsCreatedCharacters += response.optInt("createdCharacters", 0)
                    unresolvedWindows += response.optInt("unresolvedCharacters", 0)
                    if (response.optInt("deletionConflicts", 0) > 0) {
                        throw IllegalStateException("Windows ha rilevato un conflitto di cancellazione durante il merge metadata.")
                    }
                    progress(
                        "metadata_windows",
                        index + 1,
                        chunks.size.coerceAtLeast(1),
                        "Metadata Windows aggiornati",
                    )
                }
            } catch (_: SyncCancelledException) {
                cancelled = true
            } catch (error: Exception) {
                val network = isNetworkFailure(error)
                failures += TransferFailure(
                    direction = "metadata",
                    filename = "Windows",
                    message = readableError(error),
                    network = network,
                )
                if (network) interrupted = true
            }
        }

        var verifiedSynced = false
        var metadataDifferencesAfter = (initialPlan["metadataDifferences"] as? Int) ?: 0
        var metadataBaselinePendingAfter = (initialPlan["metadataBaselinePending"] as? Int) ?: 0
        var metadataResolutionConflictsAfter = initialMetadataResolutionConflicts
        var deletionPendingAfter = ((initialPlan["deletionPendingAndroid"] as? Int) ?: 0) +
            ((initialPlan["deletionPendingWindows"] as? Int) ?: 0)
        var deletionConflictsAfter = initialDeletionConflicts
        var finalAndroidCount = localItems(info.galleryUuid).size

        if (cancelRequested) cancelled = true
        if (!interrupted && !cancelled) {
            try {
                progress("verify", 0, 1, "Verifica finale del gruppo")
                val verifiedLocal = localItems(info.galleryUuid)
                val verifiedLocalTombstones = localTombstones(info.galleryUuid, info.syncGroupUuid)
                val verifiedRemoteManifest = fetchManifest(info)
                val verifiedRemote = parseManifestItems(verifiedRemoteManifest)
                val verifiedRemoteTombstones = parseManifestTombstones(verifiedRemoteManifest, info.syncGroupUuid)
                var verifiedLocalBaselines = metadataBaselineStore.read(
                    info.galleryUuid,
                    info.syncGroupUuid,
                    info.windowsGalleryUuid,
                )
                var verifiedRemoteBaselines = parseManifestBaselines(
                    verifiedRemoteManifest,
                    info.galleryUuid,
                )
                var verifiedPlan = plan(
                    verifiedLocal,
                    verifiedRemote,
                    verifiedLocalTombstones,
                    verifiedRemoteTombstones,
                    verifiedLocalBaselines,
                    verifiedRemoteBaselines,
                )
                finalAndroidCount = verifiedLocal.size
                windowsCount = verifiedRemote.size
                metadataDifferencesAfter = (verifiedPlan["metadataDifferences"] as? Int) ?: 0
                metadataBaselinePendingAfter = (verifiedPlan["metadataBaselinePending"] as? Int) ?: 0
                metadataResolutionConflictsAfter =
                    (verifiedPlan["metadataResolutionConflicts"] as? Int) ?: 0
                deletionPendingAfter = ((verifiedPlan["deletionPendingAndroid"] as? Int) ?: 0) +
                    ((verifiedPlan["deletionPendingWindows"] as? Int) ?: 0)
                deletionConflictsAfter = (verifiedPlan["deletionConflicts"] as? Int) ?: 0
                var remainingFiles = ((verifiedPlan["toAndroid"] as? Int) ?: 0) +
                    ((verifiedPlan["toWindows"] as? Int) ?: 0)

                val contentAligned = remainingFiles == 0 &&
                    metadataDifferencesAfter == 0 &&
                    metadataResolutionConflictsAfter == 0 &&
                    deletionPendingAfter == 0 &&
                    deletionConflictsAfter == 0

                if (contentAligned) {
                    progress("metadata_baseline", 0, 1, "Salvataggio baseline metadata verificato")
                    establishMetadataBaselines(info, verifiedLocal, verifiedRemote)

                    // Verifica anche il baseline dopo averlo scritto su entrambi
                    // i peer. Solo questo secondo controllo rende la sessione
                    // idonea a propagare rimozioni metadata future.
                    val baselineRemoteManifest = fetchManifest(info)
                    val baselineRemote = parseManifestItems(baselineRemoteManifest)
                    verifiedLocalBaselines = metadataBaselineStore.read(
                        info.galleryUuid,
                        info.syncGroupUuid,
                        info.windowsGalleryUuid,
                    )
                    verifiedRemoteBaselines = parseManifestBaselines(
                        baselineRemoteManifest,
                        info.galleryUuid,
                    )
                    verifiedPlan = plan(
                        verifiedLocal,
                        baselineRemote,
                        verifiedLocalTombstones,
                        parseManifestTombstones(baselineRemoteManifest, info.syncGroupUuid),
                        verifiedLocalBaselines,
                        verifiedRemoteBaselines,
                    )
                    windowsCount = baselineRemote.size
                    metadataDifferencesAfter = (verifiedPlan["metadataDifferences"] as? Int) ?: 0
                    metadataBaselinePendingAfter = (verifiedPlan["metadataBaselinePending"] as? Int) ?: 0
                    metadataResolutionConflictsAfter =
                        (verifiedPlan["metadataResolutionConflicts"] as? Int) ?: 0
                    deletionPendingAfter = ((verifiedPlan["deletionPendingAndroid"] as? Int) ?: 0) +
                        ((verifiedPlan["deletionPendingWindows"] as? Int) ?: 0)
                    deletionConflictsAfter = (verifiedPlan["deletionConflicts"] as? Int) ?: 0
                    remainingFiles = ((verifiedPlan["toAndroid"] as? Int) ?: 0) +
                        ((verifiedPlan["toWindows"] as? Int) ?: 0)
                    progress("metadata_baseline", 1, 1, "Baseline metadata verificato")
                }

                verifiedSynced = remainingFiles == 0 &&
                    metadataDifferencesAfter == 0 &&
                    metadataBaselinePendingAfter == 0 &&
                    metadataResolutionConflictsAfter == 0 &&
                    deletionPendingAfter == 0 &&
                    deletionConflictsAfter == 0
                if (!verifiedSynced) {
                    failures += TransferFailure(
                        direction = "verify",
                        filename = "Gruppo",
                        message = "La verifica finale rileva ancora $remainingFiles file, " +
                            "$metadataDifferencesAfter media con metadata differenti, " +
                            "$metadataBaselinePendingAfter baseline metadata da inizializzare, " +
                            "$metadataResolutionConflictsAfter conflitti metadata e " +
                            "$deletionPendingAfter eliminazioni da allineare.",
                        network = false,
                    )
                } else {
                    recordSuccessfulSync(
                        info.galleryUuid,
                        info,
                        finalAndroidCount,
                        windowsCount,
                    )
                }
                progress("verify", 1, 1, if (verifiedSynced) "Gallerie verificate" else "Differenze residue")
            } catch (error: Exception) {
                val network = isNetworkFailure(error)
                failures += TransferFailure(
                    direction = "verify",
                    filename = "Gruppo",
                    message = readableError(error),
                    network = network,
                )
                if (network) interrupted = true
            }
        }

        recordWindowsPeer(
            info.galleryUuid,
            remoteGalleryUuid,
            remoteManifest.optString("galleryName", "H-Gallery Windows"),
        )

        val pendingDownloads = (downloads.size - attemptedDownloads).coerceAtLeast(0)
        val pendingUploads = (uploads.size - attemptedUploads).coerceAtLeast(0)
        val complete = !interrupted && !cancelled && failures.isEmpty() &&
            pendingDownloads == 0 && pendingUploads == 0 && verifiedSynced
        val finalPhase = when {
            cancelled -> "cancelled"
            interrupted -> "interrupted"
            complete -> "done"
            else -> "partial"
        }
        val finalMessage = when {
            cancelled -> "Sincronizzazione interrotta. Le operazioni già confermate restano valide."
            interrupted -> "Connessione interrotta. Riavvia la sincronizzazione quando il PC è raggiungibile."
            complete -> "Sincronizzazione completata e verificata"
            else -> "Sincronizzazione parziale: restano differenze da riallineare."
        }
        progress(finalPhase, 1, 1, finalMessage, successfulDownloads + successfulUploads, failures.size)

        return mutableMapOf<String, Any>(
            "downloaded" to successfulDownloads,
            "uploaded" to successfulUploads,
            "deletedOnAndroid" to androidDeletion.movedToTrash,
            "deletedOnWindows" to windowsDeletion.movedToTrash,
            "deletionAlreadyAbsentAndroid" to androidDeletion.alreadyAbsent,
            "deletionAlreadyAbsentWindows" to windowsDeletion.alreadyAbsent,
            "deletionPendingAfter" to deletionPendingAfter,
            "deletionConflictsBefore" to initialDeletionConflicts,
            "deletionConflictsAfter" to deletionConflictsAfter,
            "alreadyPresent" to (initialPlan["alreadyPresent"] ?: 0),
            "pathConflicts" to (initialPlan["pathConflicts"] ?: 0),
            "metadataDifferencesBefore" to (initialPlan["metadataDifferences"] ?: 0),
            "metadataDifferencesAfter" to metadataDifferencesAfter,
            "metadataBaselinePendingBefore" to (initialPlan["metadataBaselinePending"] ?: 0),
            "metadataBaselinePendingAfter" to metadataBaselinePendingAfter,
            "metadataResolutionConflictsBefore" to initialMetadataResolutionConflicts,
            "metadataResolutionConflictsAfter" to metadataResolutionConflictsAfter,
            "metadataMergedWindows" to metadataMergedWindows,
            "metadataChangedWindows" to metadataChangedWindows,
            "metadataChangedAndroid" to androidMetadata.changedFiles,
            "createdFranchisesAndroid" to androidMetadata.createdFranchises,
            "createdCharactersAndroid" to androidMetadata.createdCharacters,
            "createdFranchisesWindows" to windowsCreatedFranchises,
            "createdCharactersWindows" to windowsCreatedCharacters,
            "unresolvedWindowsCharacters" to unresolvedWindows,
            "verifiedSynced" to verifiedSynced,
            "androidCount" to finalAndroidCount,
            "windowsCount" to windowsCount,
            "elapsedMs" to (System.currentTimeMillis() - started),
            "complete" to complete,
            "interrupted" to interrupted,
            "cancelled" to cancelled,
            "failedDownloads" to failedDownloads,
            "failedUploads" to failedUploads,
            "pendingDownloads" to pendingDownloads,
            "pendingUploads" to pendingUploads,
            "failures" to failures.map { failure ->
                mapOf(
                    "direction" to failure.direction,
                    "filename" to failure.filename,
                    "message" to failure.message,
                    "network" to failure.network,
                )
            },
        )
    }

    private fun <T> transferWithRetry(
        direction: String,
        phase: String,
        item: SyncItem,
        processed: Int,
        total: Int,
        succeeded: Int,
        failed: Int,
        operation: () -> T,
    ): TransferOutcome<T> {
        val maxAttempts = 3
        var lastError: Exception? = null
        for (attempt in 1..maxAttempts) {
            if (cancelRequested) throw SyncCancelledException()
            progress(
                phase,
                processed,
                total,
                item.filename,
                succeeded,
                failed,
                attempt,
                maxAttempts,
            )
            try {
                return TransferOutcome(value = operation())
            } catch (error: Exception) {
                lastError = error
                val network = isNetworkFailure(error)
                if (!network || attempt >= maxAttempts) {
                    return TransferOutcome(
                        failure = TransferFailure(
                            direction = direction,
                            filename = item.filename,
                            message = readableError(error),
                            network = network,
                        ),
                    )
                }
                if (cancelRequested) throw SyncCancelledException()
                progress(
                    "retry",
                    processed,
                    total,
                    "${item.filename} · nuovo tentativo ${attempt + 1}/$maxAttempts",
                    succeeded,
                    failed,
                    attempt + 1,
                    maxAttempts,
                )
                Thread.sleep(700L * attempt)
            }
        }
        val error = lastError ?: IllegalStateException("Trasferimento non riuscito.")
        return TransferOutcome(
            failure = TransferFailure(
                direction = direction,
                filename = item.filename,
                message = readableError(error),
                network = isNetworkFailure(error),
            ),
        )
    }

    private fun isNetworkFailure(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            if (current is SocketTimeoutException || current is ConnectException ||
                current is UnknownHostException || current is NoRouteToHostException ||
                current is SocketException) {
                return true
            }
            current = current.cause
        }
        val message = error.message.orEmpty().lowercase(Locale.ROOT)
        return listOf(
            "failed to connect",
            "connection reset",
            "connection refused",
            "timed out",
            "timeout",
            "unexpected end of stream",
            "software caused connection abort",
            "broken pipe",
            "network is unreachable",
        ).any { it in message }
    }

    private fun readableError(error: Throwable): String {
        val message = error.message?.trim().orEmpty()
        return (message.ifBlank { error.javaClass.simpleName }).take(400)
    }

    private fun normalizeMetadataName(value: String): String =
        value.trim().split(Regex("\\s+")).filter(String::isNotBlank).joinToString(" ").lowercase(Locale.ROOT)

    private fun metadataNames(values: List<String>): Set<String> =
        values.map(::normalizeMetadataName).filter(String::isNotBlank).toSet()

    private fun metadataNameMap(values: List<String>): Map<String, String> {
        val result = linkedMapOf<String, String>()
        for (value in values) {
            val key = normalizeMetadataName(value)
            if (key.isNotBlank()) result.putIfAbsent(key, value.trim())
        }
        return result
    }

    private fun characterKeys(values: List<Map<String, String>>): Set<String> =
        characterNameMap(values).keys

    private fun characterNameMap(values: List<Map<String, String>>): Map<String, String> {
        val result = linkedMapOf<String, String>()
        for (character in values) {
            val franchiseRaw = character["franchiseName"].orEmpty().trim()
            val nameRaw = character["name"].orEmpty().trim()
            val franchise = normalizeMetadataName(franchiseRaw)
            val name = normalizeMetadataName(nameRaw)
            if (franchise.isBlank() || name.isBlank()) continue
            result.putIfAbsent("$franchise\u0000$name", "$franchiseRaw · $nameRaw")
        }
        return result
    }

    private fun metadataDiffers(left: SyncItem, right: SyncItem): Boolean =
        left.aiGenerated != right.aiGenerated ||
            metadataNames(left.tags) != metadataNames(right.tags) ||
            metadataNames(left.artists) != metadataNames(right.artists) ||
            characterKeys(left.characters) != characterKeys(right.characters)

    private fun metadataTypeConflict(left: SyncItem, right: SyncItem): Boolean {
        val leftTags = metadataNames(left.tags)
        val leftArtists = metadataNames(left.artists)
        val rightTags = metadataNames(right.tags)
        val rightArtists = metadataNames(right.artists)
        return leftTags.intersect(rightArtists).isNotEmpty() ||
            leftArtists.intersect(rightTags).isNotEmpty()
    }

    private fun change(
        kind: String,
        value: String,
        action: String,
        note: String = "",
    ): Map<String, String> =
        linkedMapOf<String, String>(
            "kind" to kind,
            "value" to value,
            "action" to action,
        ).apply {
            if (note.isNotBlank()) put("note", note)
        }

    private fun metadataDetail(
        local: SyncItem,
        remote: SyncItem,
        desired: SyncItem,
        baselineReady: Boolean,
    ): Map<String, Any> {
        val toAndroid = mutableListOf<Map<String, String>>()
        val toWindows = mutableListOf<Map<String, String>>()

        fun appendChanges(
            current: SyncMetadataSnapshot,
            target: SyncMetadataSnapshot,
            destination: MutableList<Map<String, String>>,
        ) {
            val allTags = (current.tags.keys + target.tags.keys).toSortedSet()
            for (key in allTags) {
                val before = current.tags[key]
                val after = target.tags[key]
                if (before == after) continue
                val label = after?.name ?: before?.name ?: key
                when {
                    before == null && after != null ->
                        destination += change(
                            if (after.type == "artist") "Artista" else "Tag",
                            label,
                            "add",
                        )
                    before != null && after == null ->
                        destination += change(
                            if (before.type == "artist") "Artista" else "Tag",
                            label,
                            "remove",
                            "Rimozione propagata da una modifica successiva al baseline verificato.",
                        )
                    before != null && after != null ->
                        destination += change(
                            if (after.type == "artist") "Artista" else "Tag",
                            label,
                            "set",
                            "Classificazione aggiornata da ${if (before.type == "artist") "Artista" else "Tag"} a ${if (after.type == "artist") "Artista" else "Tag"}.",
                        )
                }
            }

            val allCharacters = (current.characters.keys + target.characters.keys).toSortedSet()
            for (key in allCharacters) {
                val before = current.characters[key]
                val after = target.characters[key]
                if (before == after) continue
                val item = after ?: before ?: continue
                val label = "${item.franchiseName} · ${item.name}"
                destination += change(
                    "Personaggio",
                    label,
                    if (after == null) "remove" else "add",
                    if (after == null) {
                        "Rimozione propagata da una modifica successiva al baseline verificato."
                    } else {
                        ""
                    },
                )
            }

            if (current.aiGenerated != target.aiGenerated) {
                destination += change(
                    "IA",
                    "Contenuto IA",
                    if (target.aiGenerated) "add" else "remove",
                    if (!target.aiGenerated) {
                        "Il flag IA verrà disattivato perché la modifica è successiva al baseline verificato."
                    } else {
                        ""
                    },
                )
            }
        }

        val desiredSnapshot = metadataSnapshot(desired)
        appendChanges(metadataSnapshot(local), desiredSnapshot, toAndroid)
        appendChanges(metadataSnapshot(remote), desiredSnapshot, toWindows)

        return mapOf(
            "filename" to local.filename.ifBlank { remote.filename },
            "relativePath" to local.relativePath.ifBlank { remote.relativePath },
            "toAndroid" to toAndroid,
            "toWindows" to toWindows,
            "typeConflict" to metadataTypeConflict(local, remote),
            "baselineReady" to baselineReady,
            "changeCount" to (toAndroid.size + toWindows.size),
        )
    }

    private fun matchTombstone(tombstone: SyncTombstone, items: List<SyncItem>): TombstoneMatch {
        val exact = items.firstOrNull { it.syncUuid.equals(tombstone.fileUuid, ignoreCase = true) }
        if (exact != null) {
            return if (exact.sha256.equals(tombstone.sha256, ignoreCase = true)) {
                TombstoneMatch(item = exact, matchKind = "uuid")
            } else {
                TombstoneMatch(conflict = "UUID uguale ma SHA-256 differente: cancellazione bloccata.")
            }
        }
        val byHash = items.filter { it.sha256.equals(tombstone.sha256, ignoreCase = true) }
        if (byHash.isEmpty()) return TombstoneMatch()
        if (byHash.size == 1) return TombstoneMatch(item = byHash.first(), matchKind = "sha256")
        val byPath = byHash.filter { it.relativePath.equals(tombstone.lastRelativePath, ignoreCase = true) }
        if (byPath.size == 1) return TombstoneMatch(item = byPath.first(), matchKind = "sha256+path")
        return TombstoneMatch(
            conflict = "Più media identici corrispondono alla cancellazione: operazione bloccata per sicurezza.",
        )
    }

    private fun plan(
        local: List<SyncItem>,
        remote: List<SyncItem>,
        localTombstones: List<SyncTombstone>,
        remoteTombstones: List<SyncTombstone>,
        localBaselines: Map<String, SyncMetadataSnapshot>,
        remoteBaselines: Map<String, SyncMetadataSnapshot>,
    ): Map<String, Any> {
        val deletionDetails = mutableListOf<Map<String, Any>>()
        val deletionConflictDetails = mutableListOf<Map<String, Any>>()
        val androidTargets = linkedMapOf<String, SyncItem>()
        val windowsTargets = linkedMapOf<String, SyncItem>()
        val pendingAndroid = linkedSetOf<String>()
        val pendingWindows = linkedSetOf<String>()
        val localTombstonesByUuid = localTombstones.associateBy { it.fileUuid.lowercase(Locale.ROOT) }
        val remoteTombstonesByUuid = remoteTombstones.associateBy { it.fileUuid.lowercase(Locale.ROOT) }

        for (tombstone in remoteTombstones) {
            val counterpart = localTombstonesByUuid[tombstone.fileUuid.lowercase(Locale.ROOT)]
            if (counterpart != null && !counterpart.sha256.equals(tombstone.sha256, ignoreCase = true)) {
                deletionConflictDetails += mapOf(
                    "direction" to "android",
                    "relativePath" to tombstone.lastRelativePath,
                    "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                    "message" to "La stessa tombstone ha SHA-256 diversi sui due dispositivi: operazione bloccata.",
                )
                continue
            }
            val needsTombstoneRecord = counterpart == null
            val match = matchTombstone(tombstone, local)
            when {
                match.conflict != null -> deletionConflictDetails += mapOf(
                    "direction" to "android",
                    "relativePath" to tombstone.lastRelativePath,
                    "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                    "message" to match.conflict,
                )
                match.item != null -> {
                    val item = match.item
                    androidTargets.putIfAbsent(item.syncUuid, item)
                    pendingAndroid += tombstone.fileUuid.lowercase(Locale.ROOT)
                    deletionDetails += mapOf(
                        "direction" to "android",
                        "relativePath" to item.relativePath,
                        "filename" to item.filename,
                        "matchKind" to match.matchKind,
                        "action" to "trash",
                    )
                }
                needsTombstoneRecord -> {
                    pendingAndroid += tombstone.fileUuid.lowercase(Locale.ROOT)
                    deletionDetails += mapOf(
                        "direction" to "android",
                        "relativePath" to tombstone.lastRelativePath,
                        "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                        "matchKind" to "absent",
                        "action" to "record",
                    )
                }
            }
        }
        for (tombstone in localTombstones) {
            val counterpart = remoteTombstonesByUuid[tombstone.fileUuid.lowercase(Locale.ROOT)]
            if (counterpart != null && !counterpart.sha256.equals(tombstone.sha256, ignoreCase = true)) {
                deletionConflictDetails += mapOf(
                    "direction" to "windows",
                    "relativePath" to tombstone.lastRelativePath,
                    "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                    "message" to "La stessa tombstone ha SHA-256 diversi sui due dispositivi: operazione bloccata.",
                )
                continue
            }
            val needsTombstoneRecord = counterpart == null
            val match = matchTombstone(tombstone, remote)
            when {
                match.conflict != null -> deletionConflictDetails += mapOf(
                    "direction" to "windows",
                    "relativePath" to tombstone.lastRelativePath,
                    "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                    "message" to match.conflict,
                )
                match.item != null -> {
                    val item = match.item
                    windowsTargets.putIfAbsent(item.syncUuid, item)
                    pendingWindows += tombstone.fileUuid.lowercase(Locale.ROOT)
                    deletionDetails += mapOf(
                        "direction" to "windows",
                        "relativePath" to item.relativePath,
                        "filename" to item.filename,
                        "matchKind" to match.matchKind,
                        "action" to "trash",
                    )
                }
                needsTombstoneRecord -> {
                    pendingWindows += tombstone.fileUuid.lowercase(Locale.ROOT)
                    deletionDetails += mapOf(
                        "direction" to "windows",
                        "relativePath" to tombstone.lastRelativePath,
                        "filename" to tombstone.lastRelativePath.substringAfterLast('/'),
                        "matchKind" to "absent",
                        "action" to "record",
                    )
                }
            }
        }

        // M7.5 usa la regola conservativa "deletion wins": finché una tombstone
        // resta nel gruppo, lo stesso contenuto non viene ricopiato da un peer
        // obsoleto. Una futura funzione esplicita potrà reintrodurre il media.
        val blockedHashes = (localTombstones + remoteTombstones)
            .map { it.sha256.lowercase(Locale.ROOT) }
            .filter(String::isNotBlank)
            .toSet()
        val liveLocal = local.filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }
        val liveRemote = remote.filter { it.sha256.lowercase(Locale.ROOT) !in blockedHashes }

        val localByHash = liveLocal.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = liveRemote.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val toAndroid = remoteByHash.filterKeys { it !in localByHash }.values
        val toWindows = localByHash.filterKeys { it !in remoteByHash }.values
        val commonHashes = localByHash.keys.intersect(remoteByHash.keys)
        val localPaths = liveLocal.associateBy { it.relativePath.lowercase(Locale.ROOT) }
        val pathConflicts = liveRemote.count { remoteItem ->
            val localItem = localPaths[remoteItem.relativePath.lowercase(Locale.ROOT)]
            localItem != null && !localItem.sha256.equals(remoteItem.sha256, ignoreCase = true)
        }
        var metadataDifferences = 0
        var metadataTypeConflicts = 0
        var metadataChangeCount = 0
        var metadataBaselinePending = 0
        var metadataResolutionConflicts = 0
        val metadataDetails = mutableListOf<Map<String, Any>>()
        val metadataResolutionConflictDetails = mutableListOf<Map<String, Any>>()
        val metadataDetailLimit = 200
        for (hash in commonHashes.sorted()) {
            val localItem = localByHash[hash] ?: continue
            val remoteItem = remoteByHash[hash] ?: continue
            val localSnapshot = metadataSnapshot(localItem)
            val remoteSnapshot = metadataSnapshot(remoteItem)
            val resolution = SyncMetadataResolver.resolve(
                localSnapshot,
                remoteSnapshot,
                localBaselines[hash],
                remoteBaselines[hash],
            )
            if (!resolution.baselineReady) metadataBaselinePending += 1
            if (resolution.conflicts.isNotEmpty()) {
                metadataResolutionConflicts += resolution.conflicts.size
                if (metadataResolutionConflictDetails.size < 100) {
                    resolution.conflicts.forEach { message ->
                        if (metadataResolutionConflictDetails.size < 100) {
                            metadataResolutionConflictDetails += mapOf(
                                "filename" to localItem.filename.ifBlank { remoteItem.filename },
                                "relativePath" to localItem.relativePath.ifBlank { remoteItem.relativePath },
                                "message" to message,
                            )
                        }
                    }
                }
                continue
            }
            val desiredItem = itemWithMetadata(localItem, resolution.snapshot)
            if (localSnapshot.sameState(resolution.snapshot) && remoteSnapshot.sameState(resolution.snapshot)) continue
            metadataDifferences += 1
            if (metadataTypeConflict(localItem, remoteItem)) metadataTypeConflicts += 1
            val detail = metadataDetail(
                localItem,
                remoteItem,
                desiredItem,
                resolution.baselineReady,
            )
            metadataChangeCount += (detail["changeCount"] as? Int) ?: 0
            if (metadataDetails.size < metadataDetailLimit) metadataDetails += detail
        }
        return mapOf(
            "toAndroid" to toAndroid.size,
            "toWindows" to toWindows.size,
            "alreadyPresent" to commonHashes.size,
            "pathConflicts" to pathConflicts,
            "metadataDifferences" to metadataDifferences,
            "metadataTypeConflicts" to metadataTypeConflicts,
            "metadataChangeCount" to metadataChangeCount,
            "metadataDetails" to metadataDetails,
            "metadataDetailsTruncated" to (metadataDifferences > metadataDetails.size),
            "metadataBaselinePending" to metadataBaselinePending,
            "metadataResolutionConflicts" to metadataResolutionConflicts,
            "metadataResolutionConflictDetails" to metadataResolutionConflictDetails,
            "deleteOnAndroid" to androidTargets.size,
            "deleteOnWindows" to windowsTargets.size,
            "deletionPendingAndroid" to pendingAndroid.size,
            "deletionPendingWindows" to pendingWindows.size,
            "deletionConflicts" to deletionConflictDetails.size,
            "deletionDetails" to deletionDetails.take(200),
            "deletionDetailsTruncated" to (deletionDetails.size > 200),
            "deletionConflictDetails" to deletionConflictDetails.take(100),
            "bytesToAndroid" to toAndroid.sumOf { it.sizeBytes.coerceAtLeast(0L) },
            "bytesToWindows" to toWindows.sumOf { it.sizeBytes.coerceAtLeast(0L) },
        )
    }

    private fun fetchManifest(info: ConnectionInfo): JSONObject =
        postJson(info, "/api/mobile/sync/manifest", basePayload(info))

    private fun basePayload(info: ConnectionInfo): JSONObject = JSONObject().apply {
        put("device_id", info.deviceId)
        put("token", info.token)
        put("android_gallery_uuid", info.galleryUuid)
        put("android_gallery_name", info.galleryName)
        put("sync_group_uuid", info.syncGroupUuid)
        put("windows_gallery_uuid", info.windowsGalleryUuid)
    }

    private fun parseManifestItems(manifest: JSONObject): List<SyncItem> {
        val array = manifest.optJSONArray("files") ?: JSONArray()
        val values = mutableListOf<SyncItem>()
        for (index in 0 until array.length()) {
            val value = array.optJSONObject(index) ?: continue
            values += syncItemFromJson(value)
        }
        return values
    }

    private fun metadataSnapshot(item: SyncItem): SyncMetadataSnapshot =
        SyncMetadataResolver.fromValues(
            tags = item.tags,
            artists = item.artists,
            characters = item.characters,
            aiGenerated = item.aiGenerated,
        )

    private fun parseManifestBaselines(
        manifest: JSONObject,
        peerGalleryUuid: String,
    ): Map<String, SyncMetadataSnapshot> {
        if (peerGalleryUuid.isBlank()) return emptyMap()
        val array = manifest.optJSONArray("metadataBaselines") ?: JSONArray()
        val values = linkedMapOf<String, SyncMetadataSnapshot>()
        for (index in 0 until array.length()) {
            val value = array.optJSONObject(index) ?: continue
            if (value.optString("peerGalleryUuid").trim() != peerGalleryUuid) continue
            val sha = value.optString("sha256").trim().lowercase(Locale.ROOT)
            if (sha.length != 64) continue
            val snapshot = SyncMetadataSnapshot.fromJson(value.optJSONObject("snapshot")) ?: continue
            values[sha] = snapshot
        }
        return values
    }

    private fun itemWithMetadata(item: SyncItem, snapshot: SyncMetadataSnapshot): SyncItem = item.copy(
        aiGenerated = snapshot.aiGenerated,
        tags = snapshot.tags.values.filter { it.type == "general" }.map { it.name }.sortedBy { it.lowercase(Locale.ROOT) },
        artists = snapshot.tags.values.filter { it.type == "artist" }.map { it.name }.sortedBy { it.lowercase(Locale.ROOT) },
        characters = snapshot.characters.values.map { it.asMap() }.sortedWith(
            compareBy<Map<String, String>>(
                { it["franchiseName"].orEmpty().lowercase(Locale.ROOT) },
                { it["name"].orEmpty().lowercase(Locale.ROOT) },
            ),
        ),
    )

    private fun resolvedMetadataItems(
        local: List<SyncItem>,
        remote: List<SyncItem>,
        localBaselines: Map<String, SyncMetadataSnapshot>,
        remoteBaselines: Map<String, SyncMetadataSnapshot>,
    ): List<SyncItem> {
        val localByHash = local.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = remote.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        return localByHash.keys.intersect(remoteByHash.keys).sorted().mapNotNull { hash ->
            val localItem = localByHash[hash] ?: return@mapNotNull null
            val remoteItem = remoteByHash[hash] ?: return@mapNotNull null
            val resolution = SyncMetadataResolver.resolve(
                metadataSnapshot(localItem),
                metadataSnapshot(remoteItem),
                localBaselines[hash],
                remoteBaselines[hash],
            )
            if (resolution.conflicts.isNotEmpty()) return@mapNotNull null
            val localSnapshot = metadataSnapshot(localItem)
            val remoteSnapshot = metadataSnapshot(remoteItem)
            if (localSnapshot.sameState(resolution.snapshot) && remoteSnapshot.sameState(resolution.snapshot)) {
                return@mapNotNull null
            }
            itemWithMetadata(localItem, resolution.snapshot)
        }
    }

    private fun baselineControlJson(
        sha256: String,
        snapshot: SyncMetadataSnapshot?,
        info: ConnectionInfo,
        reset: Boolean = false,
    ): JSONObject = JSONObject().apply {
        put("baselineSnapshot", true)
        put("baselineSyncGroupUuid", info.syncGroupUuid)
        put("baselinePeerGalleryUuid", info.galleryUuid)
        if (reset) put("baselineReset", true)
        if (sha256.isNotBlank() && snapshot != null) {
            put("sha256", sha256)
            put("snapshot", snapshot.toJson())
        }
    }

    private fun establishMetadataBaselines(
        info: ConnectionInfo,
        local: List<SyncItem>,
        remote: List<SyncItem>,
    ) {
        val localByHash = local.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val remoteByHash = remote.filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val common = localByHash.keys.intersect(remoteByHash.keys).sorted()
        val snapshots = linkedMapOf<String, SyncMetadataSnapshot>()
        for (hash in common) {
            val localItem = localByHash[hash] ?: continue
            val remoteItem = remoteByHash[hash] ?: continue
            val left = metadataSnapshot(localItem)
            val right = metadataSnapshot(remoteItem)
            if (!left.sameState(right)) {
                throw IllegalStateException("Baseline metadata non creato: i peer non sono ancora allineati.")
            }
            snapshots[hash] = left
        }

        // Windows viene aggiornato per primo. Se la rete cade durante i chunk,
        // Android conserva il vecchio baseline: al giro successivo i due lati
        // non combaceranno e il resolver tornerà automaticamente in modalità
        // additiva, senza inferire rimozioni.
        val entries = snapshots.entries.toList()
        val chunks = if (entries.isEmpty()) listOf(emptyList()) else entries.chunked(90)
        chunks.forEachIndexed { index, chunk ->
            val payload = basePayload(info).apply {
                put("items", JSONArray().apply {
                    if (index == 0) put(baselineControlJson("", null, info, reset = true))
                    for ((sha, snapshot) in chunk) put(baselineControlJson(sha, snapshot, info))
                })
            }
            val response = postJson(info, "/api/mobile/sync/metadata", payload)
            if (response.optInt("deletionConflicts", 0) > 0) {
                throw IllegalStateException("Windows ha rifiutato l'aggiornamento del baseline metadata.")
            }
        }
        metadataBaselineStore.replace(
            info.galleryUuid,
            info.syncGroupUuid,
            info.windowsGalleryUuid,
            snapshots,
        )
    }

    private fun parseManifestTombstones(
        manifest: JSONObject,
        expectedGroupUuid: String,
    ): List<SyncTombstone> {
        if (expectedGroupUuid.isBlank()) return emptyList()
        val array = manifest.optJSONArray("tombstones") ?: JSONArray()
        val values = mutableListOf<SyncTombstone>()
        for (index in 0 until array.length()) {
            val value = array.optJSONObject(index) ?: continue
            val fileUuid = value.optString("fileUuid").trim()
            val sha256 = value.optString("sha256").trim().lowercase(Locale.ROOT)
            val relativePath = value.optString("lastRelativePath").trim()
            val syncGroupUuid = value.optString("syncGroupUuid").trim()
            // Le tombstone senza gruppo (pre-M7.5) non vengono mai adottate
            // automaticamente: potrebbe trattarsi di una cancellazione fatta
            // prima che la galleria appartenesse al gruppo corrente.
            if (fileUuid.isBlank() || sha256.length != 64 || relativePath.isBlank() ||
                syncGroupUuid != expectedGroupUuid
            ) {
                continue
            }
            values += SyncTombstone(
                fileUuid = fileUuid,
                sha256 = sha256,
                mediaType = value.optString("mediaType", "image"),
                lastRelativePath = relativePath,
                deletedAt = value.optString("deletedAt"),
                originPeerUuid = value.optString("originPeerUuid"),
                createdLocally = value.optBoolean("createdLocally", false),
                syncGroupUuid = syncGroupUuid,
            )
        }
        return values
    }

    private fun tombstoneJson(
        tombstone: SyncTombstone,
        originFallback: String,
        validateOnly: Boolean = false,
    ): JSONObject = JSONObject().apply {
        put("deleted", true)
        put("fileUuid", tombstone.fileUuid)
        put("sha256", tombstone.sha256)
        put("mediaType", tombstone.mediaType)
        put("lastRelativePath", tombstone.lastRelativePath)
        if (tombstone.deletedAt.isNotBlank()) put("deletedAt", tombstone.deletedAt)
        put("originPeerUuid", tombstone.originPeerUuid.ifBlank { originFallback })
        put("syncGroupUuid", tombstone.syncGroupUuid)
        if (validateOnly) put("validateOnly", true)
    }

    private fun syncItemFromJson(value: JSONObject): SyncItem {
        fun strings(key: String): List<String> {
            val array = value.optJSONArray(key) ?: JSONArray()
            return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }
        }
        val charactersArray = value.optJSONArray("characters") ?: JSONArray()
        val characters = (0 until charactersArray.length()).mapNotNull { index ->
            val item = charactersArray.optJSONObject(index) ?: return@mapNotNull null
            mapOf(
                "name" to item.optString("name"),
                "relativePath" to item.optString("relativePath"),
                "franchiseName" to item.optString("franchiseName"),
                "franchiseCode" to item.optString("franchiseCode"),
                "franchiseRelativePath" to item.optString("franchiseRelativePath"),
            )
        }
        return SyncItem(
            syncUuid = value.optString("syncUuid"),
            relativePath = value.optString("relativePath"),
            filename = value.optString("filename"),
            extension = value.optString("extension"),
            mediaType = value.optString("mediaType", "image"),
            mimeType = value.optString("mimeType"),
            sizeBytes = value.optLong("sizeBytes", 0L),
            modifiedEpochMs = value.optLong("modifiedEpochMs", 0L),
            sha256 = value.optString("sha256"),
            aiGenerated = value.optBoolean("aiGenerated", false),
            characters = characters,
            tags = strings("tags"),
            artists = strings("artists"),
        )
    }

    private fun localTombstones(
        galleryUuid: String,
        syncGroupUuid: String,
    ): List<SyncTombstone> {
        if (syncGroupUuid.isBlank()) return emptyList()
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val values = mutableListOf<SyncTombstone>()
            database.readableDatabase.rawQuery(
                """
                SELECT file_uuid, sha256, media_type, last_relative_path,
                       deleted_at, origin_peer_uuid, created_locally, sync_group_uuid
                FROM sync_tombstones
                WHERE sync_group_uuid = ?
                ORDER BY deleted_at, file_uuid
                """.trimIndent(),
                arrayOf(syncGroupUuid),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    values += SyncTombstone(
                        fileUuid = cursor.getString(0),
                        sha256 = cursor.getString(1).lowercase(Locale.ROOT),
                        mediaType = cursor.getString(2),
                        lastRelativePath = cursor.getString(3),
                        deletedAt = cursor.getString(4).orEmpty(),
                        originPeerUuid = if (cursor.isNull(5)) "" else cursor.getString(5),
                        createdLocally = cursor.getInt(6) != 0,
                        syncGroupUuid = cursor.getString(7),
                    )
                }
            }
            return values
        } finally {
            database.close()
        }
    }

    private fun storeRemoteTombstone(
        galleryUuid: String,
        tombstone: SyncTombstone,
        originFallback: String,
        syncGroupUuid: String,
    ) {
        if (syncGroupUuid.isBlank() || tombstone.syncGroupUuid != syncGroupUuid) {
            throw IllegalStateException("Tombstone non appartenente al gruppo Android attivo.")
        }
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            db.rawQuery(
                "SELECT sync_group_uuid FROM sync_tombstones WHERE file_uuid = ? LIMIT 1",
                arrayOf(tombstone.fileUuid),
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    val existingGroup = cursor.getString(0).orEmpty().trim()
                    if (existingGroup.isNotBlank() && existingGroup != syncGroupUuid) {
                        throw IllegalStateException(
                            "La stessa identità media appartiene a una tombstone di un altro gruppo.",
                        )
                    }
                }
            }
            val values = ContentValues().apply {
                put("file_uuid", tombstone.fileUuid)
                put("sha256", tombstone.sha256.lowercase(Locale.ROOT))
                put("media_type", tombstone.mediaType)
                put("last_relative_path", tombstone.lastRelativePath)
                if (tombstone.deletedAt.isNotBlank()) put("deleted_at", tombstone.deletedAt)
                put("origin_peer_uuid", tombstone.originPeerUuid.ifBlank { originFallback })
                put("created_locally", 0)
                put("sync_group_uuid", syncGroupUuid)
            }
            val updated = db.update(
                "sync_tombstones",
                values,
                "file_uuid = ? AND (sync_group_uuid = ? OR sync_group_uuid = '')",
                arrayOf(tombstone.fileUuid, syncGroupUuid),
            )
            if (updated == 0) {
                db.insertWithOnConflict(
                    "sync_tombstones",
                    null,
                    values,
                    SQLiteDatabase.CONFLICT_IGNORE,
                )
            }
        } finally {
            database.close()
        }
    }

    private fun preflightRemoteTombstones(
        info: ConnectionInfo,
        tombstones: List<SyncTombstone>,
    ): AndroidDeletionPreflight {
        if (tombstones.isEmpty()) {
            return AndroidDeletionPreflight(emptyList(), emptyList())
        }
        val active = localItems(info.galleryUuid)
        val conflicts = mutableListOf<Map<String, String>>()
        val resolved = mutableListOf<Pair<SyncTombstone, TombstoneMatch>>()
        val database = GalleryIndexDatabase(activity.applicationContext, info.galleryUuid)
        try {
            val db = database.readableDatabase
            for (tombstone in tombstones.distinctBy { it.fileUuid.lowercase(Locale.ROOT) }) {
                if (tombstone.syncGroupUuid != info.syncGroupUuid) {
                    conflicts += mapOf(
                        "direction" to "android",
                        "relativePath" to tombstone.lastRelativePath,
                        "message" to "Tombstone appartenente a un gruppo differente: cancellazione bloccata.",
                    )
                    continue
                }
                var storedConflict: String? = null
                db.rawQuery(
                    "SELECT sync_group_uuid, sha256 FROM sync_tombstones WHERE file_uuid = ? LIMIT 1",
                    arrayOf(tombstone.fileUuid),
                ).use { cursor ->
                    if (cursor.moveToFirst()) {
                        val existingGroup = cursor.getString(0).orEmpty().trim()
                        val existingSha = cursor.getString(1).orEmpty().lowercase(Locale.ROOT)
                        storedConflict = when {
                            existingGroup.isNotBlank() && existingGroup != info.syncGroupUuid ->
                                "La stessa identità media appartiene a una tombstone di un altro gruppo: cancellazione bloccata."
                            existingGroup == info.syncGroupUuid && existingSha.isNotBlank() &&
                                existingSha != tombstone.sha256.lowercase(Locale.ROOT) ->
                                "La stessa tombstone ha SHA-256 differente: cancellazione bloccata."
                            else -> null
                        }
                    }
                }
                if (storedConflict != null) {
                    conflicts += mapOf(
                        "direction" to "android",
                        "relativePath" to tombstone.lastRelativePath,
                        "message" to storedConflict.orEmpty(),
                    )
                    continue
                }
                val match = matchTombstone(tombstone, active)
                if (match.conflict != null) {
                    conflicts += mapOf(
                        "direction" to "android",
                        "relativePath" to tombstone.lastRelativePath,
                        "message" to match.conflict,
                    )
                    continue
                }
                resolved += tombstone to match
            }
        } finally {
            database.close()
        }
        return AndroidDeletionPreflight(resolved, conflicts)
    }

    private fun applyRemoteTombstones(
        info: ConnectionInfo,
        tombstones: List<SyncTombstone>,
    ): DeletionApplyStats {
        val preflight = preflightRemoteTombstones(info, tombstones)
        if (preflight.conflicts.isNotEmpty()) {
            return DeletionApplyStats(conflicts = preflight.conflicts)
        }
        if (preflight.resolved.isEmpty()) return DeletionApplyStats()

        // Persisti tutte le tombstone prima di toccare il filesystem. Se la
        // persistenza fallisce, nessun file viene spostato nel cestino.
        try {
            for ((tombstone, _) in preflight.resolved) {
                storeRemoteTombstone(
                    info.galleryUuid,
                    tombstone,
                    info.windowsGalleryUuid,
                    info.syncGroupUuid,
                )
            }
        } catch (error: Exception) {
            return DeletionApplyStats(
                conflicts = listOf(
                    mapOf(
                        "direction" to "android",
                        "relativePath" to "",
                        "message" to "Impossibile registrare in sicurezza le eliminazioni Android: ${readableError(error)}",
                    ),
                ),
            )
        }

        var moved = 0
        var absent = 0
        val conflicts = mutableListOf<Map<String, String>>()
        val handledTargets = hashSetOf<String>()
        for ((_, match) in preflight.resolved) {
            val item = match.item
            if (item != null && handledTargets.add(item.syncUuid)) {
                try {
                    trashRepository.moveToTrash(info.galleryUuid, info.treeUri, item.syncUuid)
                    moved += 1
                } catch (error: Exception) {
                    conflicts += mapOf(
                        "direction" to "android",
                        "relativePath" to item.relativePath,
                        "message" to "Tombstone registrata, ma impossibile spostare il media nel cestino Android: ${readableError(error)}",
                    )
                }
            } else if (item == null) {
                absent += 1
            }
        }
        return DeletionApplyStats(movedToTrash = moved, alreadyAbsent = absent, conflicts = conflicts)
    }

    private fun validateLocalTombstonesOnWindows(
        info: ConnectionInfo,
        tombstones: List<SyncTombstone>,
    ): List<Map<String, String>> {
        val scoped = tombstones
            .filter { it.syncGroupUuid == info.syncGroupUuid }
            .distinctBy { it.fileUuid.lowercase(Locale.ROOT) }
        if (scoped.isEmpty()) return emptyList()

        val conflicts = mutableListOf<Map<String, String>>()
        val chunks = scoped.chunked(100)
        for ((index, chunk) in chunks.withIndex()) {
            if (cancelRequested) throw SyncCancelledException()
            progress(
                "deletions_windows",
                index,
                chunks.size.coerceAtLeast(1),
                "Verifica eliminazioni su Windows",
            )
            val payload = basePayload(info).apply {
                put("items", JSONArray().apply {
                    chunk.forEach { put(tombstoneJson(it, info.galleryUuid, validateOnly = true)) }
                })
            }
            val response = postJson(info, "/api/mobile/sync/metadata", payload)
            val details = response.optJSONArray("deletionConflictDetails") ?: JSONArray()
            for (detailIndex in 0 until details.length()) {
                val detail = details.optJSONObject(detailIndex) ?: continue
                conflicts += mapOf(
                    "direction" to "windows",
                    "relativePath" to detail.optString("relativePath"),
                    "message" to detail.optString("message", "Cancellazione Windows bloccata."),
                )
            }
            if (response.optInt("deletionConflicts", 0) > 0 && details.length() == 0) {
                conflicts += mapOf(
                    "direction" to "windows",
                    "relativePath" to "",
                    "message" to "Windows ha rilevato una cancellazione ambigua e l'ha bloccata.",
                )
            }
            if (conflicts.isNotEmpty()) break
        }
        return conflicts
    }

    private fun sendLocalTombstonesToWindows(
        info: ConnectionInfo,
        tombstones: List<SyncTombstone>,
    ): DeletionApplyStats {
        val scoped = tombstones
            .filter { it.syncGroupUuid == info.syncGroupUuid }
            .distinctBy { it.fileUuid.lowercase(Locale.ROOT) }
        if (scoped.isEmpty()) return DeletionApplyStats()
        var moved = 0
        var absent = 0
        val conflicts = validateLocalTombstonesOnWindows(info, scoped).toMutableList()
        if (conflicts.isNotEmpty()) return DeletionApplyStats(conflicts = conflicts)
        val chunks = scoped.chunked(100)

        for ((index, chunk) in chunks.withIndex()) {
            if (cancelRequested) throw SyncCancelledException()
            progress(
                "deletions_windows",
                index,
                chunks.size.coerceAtLeast(1),
                "Propagazione eliminazioni su Windows",
            )
            val payload = basePayload(info).apply {
                put("items", JSONArray().apply {
                    chunk.forEach { put(tombstoneJson(it, info.galleryUuid)) }
                })
            }
            val response = postJson(info, "/api/mobile/sync/metadata", payload)
            moved += response.optInt("deletedMovedToTrash", 0)
            absent += response.optInt("deletionAlreadyAbsent", 0)
            val details = response.optJSONArray("deletionConflictDetails") ?: JSONArray()
            for (detailIndex in 0 until details.length()) {
                val detail = details.optJSONObject(detailIndex) ?: continue
                conflicts += mapOf(
                    "direction" to "windows",
                    "relativePath" to detail.optString("relativePath"),
                    "message" to detail.optString("message", "Cancellazione Windows bloccata."),
                )
            }
            progress(
                "deletions_windows",
                index + 1,
                chunks.size.coerceAtLeast(1),
                "Eliminazioni Windows elaborate",
            )
            if (conflicts.isNotEmpty()) break
        }
        return DeletionApplyStats(movedToTrash = moved, alreadyAbsent = absent, conflicts = conflicts)
    }

    private fun localItems(galleryUuid: String): List<SyncItem> {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.readableDatabase
            val items = mutableListOf<SyncItem>()
            db.rawQuery(
                """
                SELECT sync_uuid, relative_path, filename, extension, media_type,
                       mime_type, size_bytes, modified_epoch_ms, sha256,
                       document_uri, ai_generated, metadata_updated_epoch_ms
                FROM media
                WHERE is_present = 1
                ORDER BY relative_path COLLATE NOCASE
                """.trimIndent(),
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val syncUuid = cursor.getString(0)
                    val relativePath = cursor.getString(1)
                    val metadataExplicit = cursor.getLong(11) > 0L
                    val metadata = localMetadata(db, syncUuid, relativePath, metadataExplicit)
                    val pathAi = !metadataExplicit && relativePath.split('/').any { it.equals(".AI", ignoreCase = true) }
                    items += SyncItem(
                        syncUuid = syncUuid,
                        relativePath = relativePath,
                        filename = cursor.getString(2),
                        extension = cursor.getString(3),
                        mediaType = cursor.getString(4),
                        mimeType = cursor.getString(5),
                        sizeBytes = cursor.getLong(6),
                        modifiedEpochMs = cursor.getLong(7),
                        sha256 = cursor.getString(8),
                        documentUri = cursor.getString(9),
                        aiGenerated = cursor.getInt(10) != 0 || pathAi,
                        characters = metadata.first,
                        tags = metadata.second,
                        artists = metadata.third,
                    )
                }
            }
            return items
        } finally {
            database.close()
        }
    }

    private fun localMetadata(
        db: SQLiteDatabase,
        syncUuid: String,
        relativePath: String,
        metadataExplicit: Boolean,
    ): Triple<List<Map<String, String>>, List<String>, List<String>> {
        val characters = mutableListOf<Map<String, String>>()
        db.rawQuery(
            """
            SELECT c.name, c.relative_path, f.name, f.code, f.relative_path
            FROM media_characters mc
            JOIN characters c ON c.id = mc.character_id
            JOIN franchises f ON f.id = c.franchise_id
            WHERE mc.media_sync_uuid = ?
            ORDER BY f.name COLLATE NOCASE, c.name COLLATE NOCASE
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                characters += mapOf(
                    "name" to cursor.getString(0),
                    "relativePath" to cursor.getString(1),
                    "franchiseName" to cursor.getString(2),
                    "franchiseCode" to cursor.getString(3),
                    "franchiseRelativePath" to cursor.getString(4),
                )
            }
        }
        if (!metadataExplicit && characters.isEmpty()) {
            inferLegacyCharacter(relativePath)?.let { characters += it }
        }

        val tags = mutableListOf<String>()
        val artists = mutableListOf<String>()
        db.rawQuery(
            """
            SELECT t.name, t.type
            FROM media_tags mt JOIN tags t ON t.id = mt.tag_id
            WHERE mt.media_sync_uuid = ?
            ORDER BY t.name COLLATE NOCASE
            """.trimIndent(),
            arrayOf(syncUuid),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                when (cursor.getString(1)) {
                    "artist" -> artists += cursor.getString(0)
                    "general" -> if (!cursor.getString(0).equals("AI", true)) tags += cursor.getString(0)
                }
            }
        }
        return Triple(characters, tags, artists)
    }

    private fun inferLegacyCharacter(relativePath: String): Map<String, String>? {
        val segments = relativePath.split('/').filter { it.isNotBlank() }
        if (segments.size < 3) return null
        val franchise = segments[0]
        val character = segments[1]
        if (franchise.startsWith('!') || franchise.startsWith('.') ||
            character.startsWith('!') || character.startsWith('.')
        ) {
            return null
        }
        return mapOf(
            "name" to character,
            "relativePath" to "$franchise/$character",
            "franchiseName" to franchise,
            "franchiseCode" to "",
            "franchiseRelativePath" to franchise,
        )
    }

    private fun downloadItem(info: ConnectionInfo, item: SyncItem): DownloadedItem {
        val target = chooseDestination(info.treeUri, item.relativePath, item.syncUuid)
        val parent = ensureDirectoryPath(info.treeUri, target.substringBeforeLast('/', ""))
        val finalName = target.substringAfterLast('/')
        cleanupStalePartFiles(parent, finalName)
        val tempName = ".${finalName}.hgsync-${UUID.randomUUID().toString().take(8)}.part"
        val tempUri = DocumentsContract.createDocument(
            activity.contentResolver,
            parent,
            "application/octet-stream",
            tempName,
        ) ?: throw IllegalStateException("Impossibile creare il file temporaneo Android.")

        var connection: HttpURLConnection? = null
        try {
            connection = openConnection(info, "/api/mobile/sync/file/${item.syncUuid}", "GET")
            connection.setRequestProperty("X-HGallery-Device", info.deviceId)
            connection.setRequestProperty("X-HGallery-Token", info.token)
            connection.setRequestProperty("X-HGallery-Group", info.syncGroupUuid)
            connection.setRequestProperty("X-HGallery-Windows-Gallery", info.windowsGalleryUuid)
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            val digest = MessageDigest.getInstance("SHA-256")
            activity.contentResolver.openOutputStream(tempUri, "w")?.use { rawOut ->
                BufferedOutputStream(rawOut).use { output ->
                    BufferedInputStream(connection.inputStream).use { input ->
                        val buffer = ByteArray(256 * 1024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count > 0) {
                                output.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                            }
                        }
                        output.flush()
                    }
                }
            } ?: throw IllegalStateException("Android non consente di scrivere nella galleria.")
            val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
            if (!actualHash.equals(item.sha256, ignoreCase = true)) {
                throw IllegalStateException("Hash non valido durante il download di ${item.filename}.")
            }
            val renamed = DocumentsContract.renameDocument(activity.contentResolver, tempUri, finalName)
            if (renamed == null) {
                val finalUri = DocumentsContract.createDocument(
                    activity.contentResolver,
                    parent,
                    mimeFor(item),
                    finalName,
                ) ?: throw IllegalStateException("Impossibile creare ${item.filename} su Android.")
                activity.contentResolver.openInputStream(tempUri)?.use { input ->
                    activity.contentResolver.openOutputStream(finalUri, "w")?.use { output ->
                        input.copyTo(output, 256 * 1024)
                    } ?: throw IllegalStateException("Impossibile completare il file su Android.")
                } ?: throw IllegalStateException("Impossibile rileggere il file temporaneo Android.")
                DocumentsContract.deleteDocument(activity.contentResolver, tempUri)
            }
            return DownloadedItem(item, target)
        } catch (error: Exception) {
            try { DocumentsContract.deleteDocument(activity.contentResolver, tempUri) } catch (_: Exception) { }
            throw error
        } finally {
            connection?.disconnect()
        }
    }

    private fun uploadItem(info: ConnectionInfo, item: SyncItem) {
        // Keep the HTTP header deliberately small. Rich metadata is merged later
        // through /metadata as JSON, so the streaming upload only needs the
        // fields required to place and verify the binary safely.
        val mediaHeader = Base64.encodeToString(
            transferJson(item).toString().toByteArray(Charsets.UTF_8),
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
        val connection = openConnection(info, "/api/mobile/sync/upload", "POST")
        try {
            connection.doOutput = true
            connection.setChunkedStreamingMode(256 * 1024)
            connection.setRequestProperty("Content-Type", "application/octet-stream")
            connection.setRequestProperty("X-HGallery-Device", info.deviceId)
            connection.setRequestProperty("X-HGallery-Token", info.token)
            connection.setRequestProperty("X-HGallery-Group", info.syncGroupUuid)
            connection.setRequestProperty("X-HGallery-Windows-Gallery", info.windowsGalleryUuid)
            connection.setRequestProperty("X-HGallery-Media", mediaHeader)
            activity.contentResolver.openInputStream(Uri.parse(item.documentUri))?.use { rawInput ->
                BufferedInputStream(rawInput).use { input ->
                    BufferedOutputStream(connection.outputStream).use { output ->
                        input.copyTo(output, 256 * 1024)
                        output.flush()
                    }
                }
            } ?: throw IllegalStateException("Impossibile leggere ${item.filename} dal telefono.")
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            connection.inputStream.close()
        } finally {
            connection.disconnect()
        }
    }

    private fun transferJson(item: SyncItem): JSONObject = JSONObject().apply {
        put("syncUuid", item.syncUuid)
        put("relativePath", item.relativePath)
        put("filename", item.filename)
        put("mediaType", item.mediaType)
        put("sizeBytes", item.sizeBytes)
        put("modifiedEpochMs", item.modifiedEpochMs)
        put("sha256", item.sha256)
    }

    private fun itemJson(item: SyncItem, includeDocument: Boolean): JSONObject = JSONObject().apply {
        put("syncUuid", item.syncUuid)
        put("relativePath", item.relativePath)
        put("filename", item.filename)
        put("extension", item.extension)
        put("mediaType", item.mediaType)
        put("mimeType", item.mimeType)
        put("sizeBytes", item.sizeBytes)
        put("modifiedEpochMs", item.modifiedEpochMs)
        put("sha256", item.sha256)
        put("aiGenerated", item.aiGenerated)
        put("tags", JSONArray(item.tags))
        put("artists", JSONArray(item.artists))
        put("characters", JSONArray().apply {
            item.characters.forEach { character ->
                put(JSONObject().apply { character.forEach { (key, value) -> put(key, value) } })
            }
        })
        if (includeDocument) put("documentUri", item.documentUri)
    }

    private fun remapDownloadedUuids(galleryUuid: String, downloaded: List<DownloadedItem>) {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            for (entry in downloaded) {
                val remoteUuid = entry.remote.syncUuid
                if (remoteUuid.isBlank()) continue
                val uuidUsed = db.rawQuery(
                    "SELECT sha256 FROM media WHERE sync_uuid = ? LIMIT 1",
                    arrayOf(remoteUuid),
                ).use { cursor -> cursor.moveToFirst() && !cursor.getString(0).equals(entry.remote.sha256, true) }
                if (uuidUsed) continue
                val currentUuid = db.rawQuery(
                    "SELECT sync_uuid FROM media WHERE relative_path = ? AND sha256 = ? AND is_present = 1 LIMIT 1",
                    arrayOf(entry.actualRelativePath, entry.remote.sha256),
                ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
                if (currentUuid == null || currentUuid == remoteUuid) continue
                // A freshly downloaded row has no metadata relations yet.
                try {
                    db.execSQL("UPDATE media SET sync_uuid = ? WHERE sync_uuid = ?", arrayOf(remoteUuid, currentUuid))
                } catch (_: Exception) {
                    // Hash-based matching still prevents duplicates if UUID reconciliation is impossible.
                }
            }
        } finally {
            database.close()
        }
    }

    private fun mergeRemoteMetadata(galleryUuid: String, remote: List<SyncItem>): MetadataMergeStats {
        if (remote.isEmpty()) return MetadataMergeStats()
        val beforeByHash = localItems(galleryUuid)
            .filter { it.sha256.isNotBlank() }
            .associateBy { it.sha256.lowercase(Locale.ROOT) }
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        var changedFiles = 0
        var aiUpdated = 0
        var tagsAdded = 0
        var artistsAdded = 0
        var characterLinksAdded = 0
        var createdFranchises = 0
        var createdCharacters = 0
        try {
            val db = database.writableDatabase
            db.beginTransaction()
            try {
                for (item in remote) {
                    if (item.sha256.isBlank()) continue
                    val hash = item.sha256.lowercase(Locale.ROOT)
                    val before = beforeByHash[hash] ?: continue
                    val desiredSnapshot = metadataSnapshot(item)
                    val beforeSnapshot = metadataSnapshot(before)
                    if (beforeSnapshot == desiredSnapshot) continue

                    val localUuid = db.rawQuery(
                        "SELECT sync_uuid FROM media WHERE sha256 = ? AND is_present = 1 LIMIT 1",
                        arrayOf(item.sha256),
                    ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null } ?: continue

                    // Risolvi e crea prima tutte le entità necessarie. Solo
                    // dopo che ogni personaggio desiderato è risolvibile si
                    // passa alla sostituzione distruttiva delle associazioni.
                    val characterIds = mutableListOf<Long>()
                    var unresolvedCharacter = false
                    for (character in item.characters) {
                        val ensured = ensureCharacter(db, character)
                        if (ensured.createdFranchise) createdFranchises += 1
                        if (ensured.createdCharacter) createdCharacters += 1
                        val id = ensured.id
                        if (id == null) {
                            unresolvedCharacter = true
                            break
                        }
                        characterIds += id
                    }
                    if (unresolvedCharacter) continue

                    val desiredTags = mutableListOf<Long>()
                    for (tag in item.tags) {
                        if (tag.isBlank() || tag.equals("AI", true)) continue
                        val ensured = ensureTag(db, tag, "general")
                        desiredTags += ensured.id
                    }
                    val desiredArtists = mutableListOf<Long>()
                    for (artist in item.artists) {
                        if (artist.isBlank() || artist.equals("AI", true)) continue
                        val ensured = ensureTag(db, artist, "artist")
                        desiredArtists += ensured.id
                    }
                    val aiTagId = if (item.aiGenerated) ensureTag(db, "AI", "system").id else null

                    val values = ContentValues().apply {
                        put("ai_generated", if (item.aiGenerated) 1 else 0)
                        put("metadata_updated_epoch_ms", System.currentTimeMillis())
                    }
                    db.update("media", values, "sync_uuid = ?", arrayOf(localUuid))

                    db.delete("media_characters", "media_sync_uuid = ?", arrayOf(localUuid))
                    for (characterId in characterIds.distinct()) {
                        val link = ContentValues().apply {
                            put("media_sync_uuid", localUuid)
                            put("character_id", characterId)
                        }
                        db.insertWithOnConflict(
                            "media_characters",
                            null,
                            link,
                            SQLiteDatabase.CONFLICT_IGNORE,
                        )
                    }

                    // Rimuovi soltanto le associazioni che M7 gestisce. Tag di
                    // sistema futuri/non riconosciuti restano intatti.
                    db.execSQL(
                        """
                        DELETE FROM media_tags
                        WHERE media_sync_uuid = ?
                          AND tag_id IN (
                              SELECT id FROM tags
                              WHERE type IN ('general', 'artist')
                                 OR name = 'AI' COLLATE NOCASE
                          )
                        """.trimIndent(),
                        arrayOf(localUuid),
                    )
                    for (tagId in desiredTags.distinct()) linkTag(db, localUuid, tagId)
                    for (tagId in desiredArtists.distinct()) linkTag(db, localUuid, tagId)
                    if (aiTagId != null) linkTag(db, localUuid, aiTagId)

                    if (before.aiGenerated != item.aiGenerated) aiUpdated += 1
                    tagsAdded += item.tags.size
                    artistsAdded += item.artists.size
                    characterLinksAdded += characterIds.distinct().size
                    changedFiles += 1
                }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }
        return MetadataMergeStats(
            changedFiles = changedFiles,
            aiUpdated = aiUpdated,
            tagsAdded = tagsAdded,
            artistsAdded = artistsAdded,
            characterLinksAdded = characterLinksAdded,
            createdFranchises = createdFranchises,
            createdCharacters = createdCharacters,
        )
    }

    private fun ensureTag(db: SQLiteDatabase, rawName: String, requestedType: String): TagEnsureResult {
        val name = rawName.trim().split(Regex("\\s+")).filter(String::isNotBlank).joinToString(" ")
        require(name.isNotBlank()) { "Tag non valido." }
        db.rawQuery("SELECT id, type FROM tags WHERE name = ? COLLATE NOCASE LIMIT 1", arrayOf(name)).use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                val current = cursor.getString(1)
                if (current == "general" && requestedType == "artist") {
                    val values = ContentValues().apply {
                        put("type", "artist")
                        put("updated_at_epoch_ms", System.currentTimeMillis())
                    }
                    db.update("tags", values, "id = ?", arrayOf(id.toString()))
                    return TagEnsureResult(id = id, promoted = true)
                }
                return TagEnsureResult(id = id)
            }
        }
        val now = System.currentTimeMillis()
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString())
            put("name", name)
            put("type", if (name.equals("AI", true)) "system" else requestedType)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        return TagEnsureResult(id = db.insertOrThrow("tags", null, values), created = true)
    }

    private fun linkTag(db: SQLiteDatabase, mediaUuid: String, tagId: Long): Boolean {
        val values = ContentValues().apply { put("media_sync_uuid", mediaUuid); put("tag_id", tagId) }
        return db.insertWithOnConflict("media_tags", null, values, SQLiteDatabase.CONFLICT_IGNORE) != -1L
    }

    private fun ensureCharacter(db: SQLiteDatabase, value: Map<String, String>): CharacterEnsureResult {
        val name = value["name"].orEmpty().trim()
        val franchiseName = value["franchiseName"].orEmpty().trim()
        if (name.isEmpty() || franchiseName.isEmpty()) return CharacterEnsureResult(id = null)
        var createdFranchise = false
        var franchiseId = db.rawQuery(
            "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(franchiseName),
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getLong(0) else null }
        if (franchiseId == null) {
            val now = System.currentTimeMillis()
            var code = value["franchiseCode"].orEmpty().trim().filter(Char::isLetterOrDigit).uppercase(Locale.ROOT).take(10).ifBlank {
                franchiseName.filter(Char::isLetterOrDigit).uppercase(Locale.ROOT).take(8).ifBlank { "SERIE" }
            }
            val baseCode = code
            var suffix = 1
            while (db.rawQuery("SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE LIMIT 1", arrayOf(code)).use { it.moveToFirst() }) {
                val tail = suffix.toString()
                code = (baseCode.take((10 - tail.length).coerceAtLeast(1)) + tail).take(10)
                suffix += 1
            }
            var path = value["franchiseRelativePath"].orEmpty().trim().ifBlank { franchiseName }
            var pathSuffix = 1
            val basePath = path
            while (db.rawQuery("SELECT 1 FROM franchises WHERE relative_path = ? COLLATE NOCASE LIMIT 1", arrayOf(path)).use { it.moveToFirst() }) {
                path = "${basePath}_sync_$pathSuffix"
                pathSuffix += 1
            }
            val values = ContentValues().apply {
                put("sync_uuid", UUID.randomUUID().toString())
                put("name", franchiseName)
                put("code", code)
                put("relative_path", path)
                put("is_active", 1)
                put("created_at_epoch_ms", now)
                put("updated_at_epoch_ms", now)
            }
            franchiseId = db.insertOrThrow("franchises", null, values)
            createdFranchise = true
        }
        db.rawQuery(
            "SELECT id FROM characters WHERE franchise_id = ? AND name = ? COLLATE NOCASE LIMIT 1",
            arrayOf(franchiseId.toString(), name),
        ).use { cursor ->
            if (cursor.moveToFirst()) return CharacterEnsureResult(cursor.getLong(0), createdFranchise = createdFranchise)
        }
        val now = System.currentTimeMillis()
        val franchisePath = db.rawQuery(
            "SELECT relative_path FROM franchises WHERE id = ? LIMIT 1",
            arrayOf(franchiseId.toString()),
        ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else franchiseName }
        var characterPath = value["relativePath"].orEmpty().trim().ifBlank { "$franchisePath/$name" }
        var pathSuffix = 1
        val basePath = characterPath
        while (db.rawQuery("SELECT 1 FROM characters WHERE relative_path = ? COLLATE NOCASE LIMIT 1", arrayOf(characterPath)).use { it.moveToFirst() }) {
            characterPath = "${basePath}_sync_$pathSuffix"
            pathSuffix += 1
        }
        val values = ContentValues().apply {
            put("sync_uuid", UUID.randomUUID().toString())
            put("franchise_id", franchiseId)
            put("name", name)
            put("relative_path", characterPath)
            put("is_active", 1)
            put("created_at_epoch_ms", now)
            put("updated_at_epoch_ms", now)
        }
        return try {
            CharacterEnsureResult(
                id = db.insertOrThrow("characters", null, values),
                createdFranchise = createdFranchise,
                createdCharacter = true,
            )
        } catch (_: Exception) {
            CharacterEnsureResult(id = null, createdFranchise = createdFranchise)
        }
    }

    private fun readSyncGroup(galleryUuid: String): String {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.readableDatabase
            return db.rawQuery(
                "SELECT value FROM sync_state WHERE key = ? LIMIT 1",
                arrayOf("sync_group_uuid"),
            ).use { cursor -> if (cursor.moveToFirst()) cursor.getString(0)?.trim().orEmpty() else "" }
        } finally {
            database.close()
        }
    }

    private fun readSyncStatus(galleryUuid: String): Map<String, Any> {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.readableDatabase
            val values = mutableMapOf<String, String>()
            db.rawQuery(
                "SELECT key, value FROM sync_state WHERE key LIKE 'last_sync_%'",
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) values[cursor.getString(0)] = cursor.getString(1)
            }
            return mapOf(
                "lastSyncEpochMs" to (values["last_sync_epoch_ms"]?.toLongOrNull() ?: 0L),
                "androidCount" to (values["last_sync_android_count"]?.toIntOrNull() ?: 0),
                "windowsCount" to (values["last_sync_windows_count"]?.toIntOrNull() ?: 0),
                "windowsGalleryUuid" to values["last_sync_windows_gallery_uuid"].orEmpty(),
                "syncGroupUuid" to values["last_sync_group_uuid"].orEmpty(),
                "verified" to (values["last_sync_verified"] == "1"),
            )
        } finally {
            database.close()
        }
    }

    private fun putSyncState(db: SQLiteDatabase, key: String, value: String) {
        db.execSQL(
            """
            INSERT INTO sync_state(key, value, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = CURRENT_TIMESTAMP
            """.trimIndent(),
            arrayOf(key, value),
        )
    }

    private fun recordSuccessfulSync(
        galleryUuid: String,
        info: ConnectionInfo,
        androidCount: Int,
        windowsCount: Int,
    ) {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            val now = System.currentTimeMillis().toString()
            db.beginTransaction()
            try {
                putSyncState(db, "last_sync_epoch_ms", now)
                putSyncState(db, "last_sync_android_count", androidCount.toString())
                putSyncState(db, "last_sync_windows_count", windowsCount.toString())
                putSyncState(db, "last_sync_windows_gallery_uuid", info.windowsGalleryUuid)
                putSyncState(db, "last_sync_group_uuid", info.syncGroupUuid)
                putSyncState(db, "last_sync_verified", "1")
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
        } finally {
            database.close()
        }
    }

    private fun writeSyncGroup(galleryUuid: String, syncGroupUuid: String) {
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            if (syncGroupUuid.isBlank()) {
                db.delete("sync_state", "key = ?", arrayOf("sync_group_uuid"))
                db.delete("sync_state", "key LIKE ?", arrayOf("last_sync_%"))
            } else {
                putSyncState(db, "sync_group_uuid", syncGroupUuid.trim())
            }
        } finally {
            database.close()
        }
    }

    private fun recordWindowsPeer(galleryUuid: String, windowsGalleryUuid: String, name: String) {
        if (windowsGalleryUuid.isBlank()) return
        val database = GalleryIndexDatabase(activity.applicationContext, galleryUuid)
        try {
            val db = database.writableDatabase
            db.delete("sync_peers", "peer_gallery_uuid = ? AND peer_uuid <> ?", arrayOf(windowsGalleryUuid, windowsGalleryUuid))
            db.execSQL(
                """
                INSERT OR REPLACE INTO sync_peers(
                    peer_uuid, peer_gallery_uuid, display_name, platform,
                    paired_at, last_seen_at, is_active
                ) VALUES (?, ?, ?, 'windows', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
                """.trimIndent(),
                arrayOf(windowsGalleryUuid, windowsGalleryUuid, name),
            )
        } finally {
            database.close()
        }
    }

    private fun chooseDestination(treeUri: Uri, requested: String, syncUuid: String): String {
        val clean = safeRelative(requested)
        val parentPath = clean.substringBeforeLast('/', "")
        val originalName = clean.substringAfterLast('/')
        val parent = ensureDirectoryPath(treeUri, parentPath)
        if (findChild(parent, originalName) == null) return clean
        val dot = originalName.lastIndexOf('.')
        val stem = if (dot > 0) originalName.substring(0, dot) else originalName
        val extension = if (dot > 0) originalName.substring(dot) else ""
        val suffix = syncUuid.filter(Char::isLetterOrDigit).take(8).ifBlank { UUID.randomUUID().toString().take(8) }
        for (index in 0 until 10000) {
            val extra = if (index == 0) "_sync_$suffix" else "_sync_${suffix}_$index"
            val name = "$stem$extra$extension"
            if (findChild(parent, name) == null) return if (parentPath.isBlank()) name else "$parentPath/$name"
        }
        throw IllegalStateException("Impossibile trovare un nome libero nella galleria Android.")
    }

    private fun safeRelative(value: String): String {
        val parts = value.replace('\\', '/').trim('/').split('/').filter(String::isNotBlank)
        if (parts.isEmpty() || parts.any { it == "." || it == ".." }) throw IllegalArgumentException("Percorso media non valido.")
        if (parts.first().lowercase(Locale.ROOT) in setOf(".user", ".todo", ".trash", ".script")) {
            throw IllegalArgumentException("Percorso interno non sincronizzabile.")
        }
        return parts.joinToString("/")
    }

    private fun ensureDirectoryPath(treeUri: Uri, relativeDirectory: String): Uri {
        var current = treeDocumentUri(treeUri)
        if (relativeDirectory.isBlank()) return current
        for (segment in safeRelative(relativeDirectory).split('/')) {
            val existing = findChild(current, segment)
            current = when {
                existing == null -> DocumentsContract.createDocument(
                    activity.contentResolver,
                    current,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ) ?: throw IllegalStateException("Impossibile creare la cartella $segment.")
                existing.second != DocumentsContract.Document.MIME_TYPE_DIR -> throw IllegalStateException("$segment esiste ma non è una cartella.")
                else -> existing.first
            }
        }
        return current
    }

    private fun cleanupStalePartFiles(parent: Uri, finalName: String) {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        )
        val prefix = ".$finalName.hgsync-"
        try {
            activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(1).orEmpty()
                    if (!name.startsWith(prefix) || !name.endsWith(".part")) continue
                    val uri = DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0))
                    try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { }
                }
            }
        } catch (_: Exception) {
            // La pulizia è best-effort: un provider SAF può non consentire l'elenco/eliminazione.
        }
    }

    private fun findChild(parent: Uri, name: String): Pair<Uri, String>? {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        activity.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(parent, cursor.getString(0)) to cursor.getString(2)
                }
            }
        }
        return null
    }

    private fun treeDocumentUri(treeUri: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        treeUri,
        DocumentsContract.getTreeDocumentId(treeUri),
    )

    private fun resolveTreeUri(galleryUuid: String): Uri {
        val raw = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(PREFS_GALLERIES, "[]") ?: "[]"
        val profiles = try { JSONArray(raw) } catch (_: Exception) { JSONArray() }
        for (index in 0 until profiles.length()) {
            val profile = profiles.optJSONObject(index) ?: continue
            if (profile.optString("galleryUuid") != galleryUuid) continue
            val uri = Uri.parse(profile.optString("treeUri"))
            val access = activity.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission && it.isWritePermission }
            if (!access) throw IllegalStateException("H-Gallery non ha più accesso in lettura/scrittura alla galleria Android.")
            return uri
        }
        throw IllegalArgumentException("Galleria Android non trovata.")
    }

    private fun mimeFor(item: SyncItem): String {
        if (item.mimeType.isNotBlank()) return item.mimeType
        return URLConnection.guessContentTypeFromName(item.filename)
            ?: if (item.mediaType == "video") "video/*" else "image/*"
    }

    private fun postJson(info: ConnectionInfo, path: String, payload: JSONObject): JSONObject {
        val connection = openConnection(info, path, "POST")
        try {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            val bytes = payload.toString().toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(bytes.size)
            connection.outputStream.use { it.write(bytes); it.flush() }
            val code = connection.responseCode
            if (code !in 200..299) throw IllegalStateException(httpError(connection, code))
            val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return if (text.isBlank()) JSONObject() else JSONObject(text)
        } finally {
            connection.disconnect()
        }
    }

    private fun openConnection(info: ConnectionInfo, path: String, method: String): HttpURLConnection {
        val url = URL("http://${info.address}:${info.port}$path")
        return (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 8000
            readTimeout = 20000
            useCaches = false
            setRequestProperty("Accept", "application/json, application/octet-stream")
        }
    }

    private fun httpError(connection: HttpURLConnection, code: Int): String {
        val text = try { connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty() } catch (_: Exception) { "" }
        return try {
            JSONObject(text).optString("detail").ifBlank { "Errore HTTP $code." }
        } catch (_: Exception) {
            text.takeIf(String::isNotBlank) ?: "Errore HTTP $code."
        }
    }

    private fun progress(
        phase: String,
        processed: Int,
        total: Int,
        current: String,
        succeeded: Int = 0,
        failed: Int = 0,
        attempt: Int = 1,
        maxAttempts: Int = 1,
    ) {
        activity.runOnUiThread {
            channel.invokeMethod(
                "syncProgress",
                mapOf(
                    "phase" to phase,
                    "processed" to processed,
                    "total" to total,
                    "current" to current,
                    "succeeded" to succeeded,
                    "failed" to failed,
                    "attempt" to attempt,
                    "maxAttempts" to maxAttempts,
                ),
            )
        }
    }

    private fun runAsync(result: MethodChannel.Result, errorCode: String, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                val message = error.message?.takeIf(String::isNotBlank) ?: "Operazione non riuscita (${error.javaClass.simpleName})."
                activity.runOnUiThread { result.error(errorCode, message, null) }
            }
        }
    }
}
