package com.sfyri.h_gallery_mobile

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import java.util.regex.Pattern

internal class GalleryOrganizationRepository(private val context: Context) {
    companion object {
        private const val MULTIPLE_FOLDER = "!Multiple"
        private const val CROSSOVERS_FOLDER = "!Crossovers"
        private const val AI_FOLDER = ".AI"
        private const val STORIES_FOLDER = "!Stories"
        private const val TODO_FOLDER = ".toDo"
        private const val TRASH_FOLDER = ".trash"
        private const val USER_FOLDER = ".user"
        private const val MAX_BATCH = 500

        private val WINDOWS_RESERVED_NAMES = buildSet {
            addAll(listOf("CON", "PRN", "AUX", "NUL"))
            for (number in 1..9) {
                add("COM$number")
                add("LPT$number")
            }
        }
        private val INVALID_WINDOWS_CHARS = Regex("[<>:\"/\\\\|?*\\u0000-\\u001F]")
    }

    private data class ChildEntry(
        val uri: Uri,
        val documentId: String,
        val displayName: String,
        val mimeType: String,
        val sizeBytes: Long,
        val modifiedEpochMs: Long,
    )

    private data class DestinationSpec(
        val category: String,
        val folderRelativePath: String,
        val logicalRootRelativePath: String,
        val prefix: String,
    )

    private data class PlannedTodoItem(
        val token: String,
        val tokenData: TodoMediaTokenData,
        val sha256: String,
        val filename: String,
        val destinationFolder: String,
        val destinationRelativePath: String,
        val duplicate: DuplicateMediaRecord?,
    )

    @Synchronized
    fun getCatalog(galleryUuid: String, treeUri: Uri): Map<String, Any> {
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            discoverEntities(treeUri, database)
            mapOf(
                "franchises" to database.listFranchises().map(::franchiseToMap),
                "characters" to database.listCharacters().map(::characterToMap),
                "tags" to database.listTagNames("general"),
                "artists" to database.listTagNames("artist"),
            )
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun createFranchise(
        galleryUuid: String,
        treeUri: Uri,
        rawName: String,
        rawCode: String,
    ): Map<String, Any> {
        val name = validateFolderName(rawName, "serie")
        if (name.equals(TODO_FOLDER, true) ||
            name.equals(TRASH_FOLDER, true) ||
            name.equals(USER_FOLDER, true) ||
            name.equals(CROSSOVERS_FOLDER, true)
        ) {
            throw IllegalArgumentException("Questo nome è riservato dal programma.")
        }
        val requestedCode = rawCode.trim().ifBlank { deriveFranchiseCode(name) }
        val code = validateFranchiseCode(requestedCode)
        val root = rootDocumentUri(treeUri)
        ensureDirectory(root, name)

        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            franchiseToMap(database.createFranchise(name, code, name))
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun createCharacter(
        galleryUuid: String,
        treeUri: Uri,
        franchiseId: Long,
        rawName: String,
    ): Map<String, Any> {
        val name = validateFolderName(rawName, "personaggio")
        if (name.equals(MULTIPLE_FOLDER, true) ||
            name.equals(AI_FOLDER, true) ||
            name.equals(STORIES_FOLDER, true)
        ) {
            throw IllegalArgumentException("Questo nome è riservato dal programma.")
        }

        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            val franchise = database.listFranchises().firstOrNull { it.id == franchiseId }
                ?: throw IllegalArgumentException("Serie non trovata.")
            val root = rootDocumentUri(treeUri)
            val franchiseDirectory = ensurePath(root, franchise.relativePath)
            ensureDirectory(franchiseDirectory, name)
            val relativePath = joinRelative(franchise.relativePath, name)
            return characterToMap(database.createCharacter(franchiseId, name, relativePath))
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun preview(
        galleryUuid: String,
        treeUri: Uri,
        tokens: List<String>,
        characterIds: List<Long>,
        aiGenerated: Boolean,
    ): Map<String, Any> {
        validateBatch(tokens, characterIds)
        val database = GalleryIndexDatabase(context, galleryUuid)
        return try {
            discoverEntities(treeUri, database)
            val characters = requireCharacters(database, characterIds)
            val destination = determineDestination(characters, aiGenerated)
            val plans = buildPlans(
                treeUri,
                tokens,
                destination,
                database,
                includeDuplicatesInNumbering = false,
            )
            mapOf(
                "category" to destination.category,
                "destinationFolder" to destination.folderRelativePath,
                "requested" to plans.size,
                "duplicateCount" to plans.count { it.duplicate != null },
                "totalBytes" to plans.sumOf { tokenSize(it.tokenData.uri) },
                "items" to plans.map { plan ->
                    mapOf(
                        "token" to plan.token,
                        "sourceRelativePath" to plan.tokenData.relativePath,
                        "filename" to plan.filename,
                        "destinationRelativePath" to plan.destinationRelativePath,
                        "duplicate" to (plan.duplicate != null),
                        "duplicateRelativePath" to plan.duplicate?.relativePath.orEmpty(),
                    )
                },
            )
        } finally {
            database.close()
        }
    }

    @Synchronized
    fun organizeBatch(
        galleryUuid: String,
        treeUri: Uri,
        tokens: List<String>,
        characterIds: List<Long>,
        tags: List<String>,
        artists: List<String>,
        aiGenerated: Boolean,
        allowDuplicates: Boolean,
    ): Map<String, Any> {
        validateBatch(tokens, characterIds)
        val database = GalleryIndexDatabase(context, galleryUuid)
        try {
            discoverEntities(treeUri, database)
            val characters = requireCharacters(database, characterIds)
            val destinationSpec = determineDestination(characters, aiGenerated)
            val plans = buildPlans(
                treeUri,
                tokens,
                destinationSpec,
                database,
                includeDuplicatesInNumbering = allowDuplicates,
            )
            val root = rootDocumentUri(treeUri)
            val destinationDirectory = ensurePath(root, destinationSpec.folderRelativePath)

            val organized = mutableListOf<Map<String, Any>>()
            val duplicates = mutableListOf<Map<String, Any>>()
            val errors = mutableListOf<Map<String, String>>()

            for (plan in plans) {
                if (plan.duplicate != null && !allowDuplicates) {
                    duplicates += mapOf(
                        "sourceRelativePath" to plan.tokenData.relativePath,
                        "duplicateRelativePath" to plan.duplicate.relativePath,
                    )
                    continue
                }

                try {
                    val result = organizeOne(
                        database = database,
                        destinationDirectory = destinationDirectory,
                        plan = plan,
                        characterIds = characterIds,
                        tags = tags,
                        artists = artists,
                        aiGenerated = aiGenerated,
                    )
                    organized += result
                } catch (error: Exception) {
                    errors += mapOf(
                        "sourceRelativePath" to plan.tokenData.relativePath,
                        "message" to safeMessage(error),
                    )
                }
            }

            return mapOf(
                "requested" to plans.size,
                "organizedCount" to organized.size,
                "duplicateCount" to duplicates.size,
                "errorCount" to errors.size,
                "organized" to organized,
                "duplicates" to duplicates,
                "errors" to errors,
                "allowDuplicates" to allowDuplicates,
            )
        } finally {
            database.close()
        }
    }

    private fun organizeOne(
        database: GalleryIndexDatabase,
        destinationDirectory: Uri,
        plan: PlannedTodoItem,
        characterIds: List<Long>,
        tags: List<String>,
        artists: List<String>,
        aiGenerated: Boolean,
    ): Map<String, Any> {
        val source = plan.tokenData.uri
        val sourceParent = plan.tokenData.parentUri
            ?: throw IllegalStateException(
                "Il media usa un'identità .toDo precedente. Rileggi .toDo e riprova.",
            )
        val sourceName = queryDisplayName(source).ifBlank {
            plan.tokenData.relativePath.substringAfterLast('/')
        }
        val mimeType = context.contentResolver.getType(source)
            ?.takeIf { it.isNotBlank() && it != "application/octet-stream" }
            ?: mimeTypeForExtension(plan.tokenData.extension)
        if (findChild(destinationDirectory, plan.filename) != null) {
            throw IllegalStateException("Esiste già un file chiamato ${plan.filename}.")
        }

        var destination: Uri? = null
        var sourceDeleted = false
        var recordedSyncUuid: String? = null
        try {
            destination = DocumentsContract.createDocument(
                context.contentResolver,
                destinationDirectory,
                mimeType,
                plan.filename,
            ) ?: throw IllegalStateException("Android non ha creato il file di destinazione.")

            copyDocument(source, destination)
            val copiedSha256 = calculateSha256(destination)
            if (!copiedSha256.equals(plan.sha256, ignoreCase = true)) {
                throw IllegalStateException("La verifica SHA-256 della copia non è riuscita.")
            }

            val destinationMetadata = queryDocument(destination)
            val syncUuid = UUID.randomUUID().toString()
            val record = OrganizedMediaRecord(
                syncUuid = syncUuid,
                relativePath = plan.destinationRelativePath,
                filename = plan.filename,
                extension = plan.tokenData.extension.lowercase(Locale.ROOT),
                mediaType = plan.tokenData.mediaType,
                isAnimated = plan.tokenData.mediaType == "image" &&
                    plan.tokenData.extension.equals("gif", ignoreCase = true),
                mimeType = destinationMetadata?.mimeType.orEmpty().ifBlank { mimeType },
                sizeBytes = destinationMetadata?.sizeBytes?.coerceAtLeast(0L)
                    ?: tokenSize(source),
                modifiedEpochMs = destinationMetadata?.modifiedEpochMs?.coerceAtLeast(0L)
                    ?: System.currentTimeMillis(),
                documentUri = destination.toString(),
                documentId = DocumentsContract.getDocumentId(destination),
                sha256 = plan.sha256,
                aiGenerated = aiGenerated,
            )

            database.recordOrganizedMedia(
                media = record,
                characterIds = characterIds,
                tags = tags,
                artists = artists,
                sourceRelativePath = plan.tokenData.relativePath,
            )
            recordedSyncUuid = syncUuid

            if (!DocumentsContract.deleteDocument(context.contentResolver, source)) {
                throw IllegalStateException("Android non ha rimosso il file originale da .toDo.")
            }
            sourceDeleted = true

            return mapOf(
                "syncUuid" to syncUuid,
                "sourceRelativePath" to plan.tokenData.relativePath,
                "relativePath" to plan.destinationRelativePath,
                "filename" to plan.filename,
            )
        } catch (error: Exception) {
            val recorded = recordedSyncUuid
            if (recorded != null) {
                try {
                    database.rollbackOrganizedMedia(recorded, plan.destinationRelativePath)
                } catch (_: Exception) {
                    // Continua il rollback dei file: la prossima scansione potrà
                    // comunque riconciliare un eventuale record residuo.
                }
            }
            var sourceRestored = false
            if (sourceDeleted && destination != null) {
                try {
                    restoreSource(destination, sourceParent, sourceName, mimeType)
                    sourceRestored = true
                } catch (_: Exception) {
                    // Il file di destinazione viene lasciato intatto se il ripristino
                    // non è possibile: è preferibile conservare una copia dei dati.
                    throw IllegalStateException(
                        "${safeMessage(error)} Il ripristino automatico in .toDo non è riuscito; " +
                            "il file copiato è stato conservato nella destinazione.",
                        error,
                    )
                }
            }
            if (destination != null && (!sourceDeleted || sourceRestored)) {
                try {
                    DocumentsContract.deleteDocument(context.contentResolver, destination)
                } catch (_: Exception) {
                    // Non nascondere l'errore originale.
                }
            }
            throw error
        }
    }

    private fun buildPlans(
        treeUri: Uri,
        tokens: List<String>,
        destination: DestinationSpec,
        database: GalleryIndexDatabase,
        includeDuplicatesInNumbering: Boolean,
    ): List<PlannedTodoItem> {
        val root = rootDocumentUri(treeUri)
        val logicalRoot = findPath(root, destination.logicalRootRelativePath)
        var nextNumber = findMaximumCounter(logicalRoot, destination.prefix) + 1
        val plans = mutableListOf<PlannedTodoItem>()

        for (token in tokens.distinct()) {
            val data = TodoMediaToken.decode(token)
            if (data.parentUri == null) {
                throw IllegalStateException(
                    "Rileggi .toDo prima di organizzare: alcuni media usano ancora l'identità M4A.",
                )
            }
            if (!documentExists(data.uri)) {
                throw IllegalStateException("File non più disponibile: ${data.relativePath}")
            }
            val sha256 = calculateSha256(data.uri)
            val duplicate = database.findDuplicate(sha256)
            val extension = data.extension.lowercase(Locale.ROOT).filter(::isAsciiAlphanumeric)
            if (extension.isEmpty()) {
                throw IllegalStateException("Estensione non valida: ${data.relativePath}")
            }
            val filename = "${destination.prefix}_${nextNumber.toString().padStart(6, '0')}.$extension"
            if (duplicate == null || includeDuplicatesInNumbering) {
                nextNumber += 1
            }
            plans += PlannedTodoItem(
                token = token,
                tokenData = data,
                sha256 = sha256,
                filename = filename,
                destinationFolder = destination.folderRelativePath,
                destinationRelativePath = joinRelative(destination.folderRelativePath, filename),
                duplicate = duplicate,
            )
        }
        return plans
    }

    private fun determineDestination(
        characters: List<CharacterRecord>,
        aiGenerated: Boolean,
    ): DestinationSpec {
        val franchiseIds = characters.map { it.franchiseId }.toSet()
        val base = when {
            characters.size == 1 -> {
                val character = characters.single()
                DestinationSpec(
                    category = "single",
                    folderRelativePath = character.relativePath,
                    logicalRootRelativePath = character.relativePath,
                    prefix = character.franchiseCode + normalizeFilenameComponent(character.name),
                )
            }
            franchiseIds.size == 1 -> {
                val character = characters.first()
                val folder = joinRelative(character.franchiseRelativePath, MULTIPLE_FOLDER)
                DestinationSpec(
                    category = "multiple",
                    folderRelativePath = folder,
                    logicalRootRelativePath = folder,
                    prefix = character.franchiseCode + "Multiple",
                )
            }
            else -> DestinationSpec(
                category = "crossover",
                folderRelativePath = CROSSOVERS_FOLDER,
                logicalRootRelativePath = CROSSOVERS_FOLDER,
                prefix = "Crossover",
            )
        }
        return if (aiGenerated) {
            base.copy(folderRelativePath = joinRelative(base.folderRelativePath, AI_FOLDER))
        } else {
            base
        }
    }

    private fun requireCharacters(
        database: GalleryIndexDatabase,
        characterIds: List<Long>,
    ): List<CharacterRecord> {
        val uniqueIds = characterIds.distinct()
        val characters = database.charactersByIds(uniqueIds)
        if (characters.size != uniqueIds.size) {
            throw IllegalArgumentException("Uno o più personaggi non sono più disponibili.")
        }
        return characters
    }

    private fun validateBatch(tokens: List<String>, characterIds: List<Long>) {
        if (tokens.isEmpty()) throw IllegalArgumentException("Seleziona almeno un file da organizzare.")
        if (tokens.distinct().size > MAX_BATCH) {
            throw IllegalArgumentException("Puoi organizzare al massimo $MAX_BATCH file per operazione.")
        }
        if (characterIds.isEmpty()) {
            throw IllegalArgumentException("Seleziona almeno un personaggio.")
        }
    }

    private fun discoverEntities(treeUri: Uri, database: GalleryIndexDatabase) {
        val root = rootDocumentUri(treeUri)
        val rootChildren = queryChildren(root)
        for (franchiseDirectory in rootChildren) {
            if (franchiseDirectory.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) continue
            val name = franchiseDirectory.displayName
            if (name.startsWith('.') || name.startsWith('!')) continue
            val franchise = database.ensureDiscoveredFranchise(
                name = name,
                relativePath = name,
                derivedCode = inferFranchiseCode(franchiseDirectory.uri, name),
            )
            for (characterDirectory in queryChildren(franchiseDirectory.uri)) {
                if (characterDirectory.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) continue
                val characterName = characterDirectory.displayName
                if (characterName.startsWith('.') || characterName.startsWith('!')) continue
                if (characterName.equals(MULTIPLE_FOLDER, true) ||
                    characterName.equals(AI_FOLDER, true) ||
                    characterName.equals(STORIES_FOLDER, true)
                ) {
                    continue
                }
                database.ensureDiscoveredCharacter(
                    franchiseId = franchise.id,
                    name = characterName,
                    relativePath = joinRelative(name, characterName),
                )
            }
        }
    }

    private fun inferFranchiseCode(franchiseDirectory: Uri, franchiseName: String): String {
        val characterDirectories = queryChildren(franchiseDirectory)
            .filter { it.mimeType == DocumentsContract.Document.MIME_TYPE_DIR }

        for (characterDirectory in characterDirectories) {
            val characterName = characterDirectory.displayName
            if (characterName.startsWith('.') || characterName.startsWith('!')) continue
            val normalizedCharacter = normalizeFilenameComponent(characterName)
            val pattern = Pattern.compile(
                "^([A-Za-z0-9]{1,10})${Pattern.quote(normalizedCharacter)}_\\d{6}$",
                Pattern.CASE_INSENSITIVE,
            )
            val inferred = findPrefixInMediaTree(characterDirectory.uri, pattern)
            if (!inferred.isNullOrBlank()) return inferred.uppercase(Locale.ROOT)
        }

        val multipleDirectory = characterDirectories.firstOrNull {
            it.displayName.equals(MULTIPLE_FOLDER, ignoreCase = true)
        }
        if (multipleDirectory != null) {
            val pattern = Pattern.compile(
                "^([A-Za-z0-9]{1,10})Multiple_\\d{6}$",
                Pattern.CASE_INSENSITIVE,
            )
            val inferred = findPrefixInMediaTree(multipleDirectory.uri, pattern)
            if (!inferred.isNullOrBlank()) return inferred.uppercase(Locale.ROOT)
        }

        return deriveFranchiseCode(franchiseName)
    }

    private fun findPrefixInMediaTree(directory: Uri, pattern: Pattern): String? {
        val stack = ArrayDeque<Uri>()
        stack.add(directory)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            for (child in queryChildren(current)) {
                if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    stack.add(child.uri)
                    continue
                }
                val stem = child.displayName.substringBeforeLast('.', child.displayName)
                val match = pattern.matcher(stem)
                if (match.matches()) return match.group(1)
            }
        }
        return null
    }

    private fun findMaximumCounter(directory: Uri?, prefix: String): Int {
        if (directory == null) return 0
        val pattern = Pattern.compile("^${Pattern.quote(prefix)}_(\\d{6})$", Pattern.CASE_INSENSITIVE)
        var maximum = 0
        val stack = ArrayDeque<Uri>()
        stack.add(directory)
        while (stack.isNotEmpty()) {
            val current = stack.removeLast()
            for (child in queryChildren(current)) {
                if (child.mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    stack.add(child.uri)
                    continue
                }
                val stem = child.displayName.substringBeforeLast('.', child.displayName)
                val match = pattern.matcher(stem)
                if (match.matches()) {
                    maximum = maxOf(maximum, match.group(1)?.toIntOrNull() ?: 0)
                }
            }
        }
        return maximum
    }

    private fun rootDocumentUri(treeUri: Uri): Uri {
        val documentId = DocumentsContract.getTreeDocumentId(treeUri)
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun findPath(root: Uri, relativePath: String): Uri? {
        if (relativePath.isBlank()) return root
        var current = root
        for (component in relativePath.split('/').filter { it.isNotBlank() }) {
            val child = findChild(current, component) ?: return null
            if (child.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) return null
            current = child.uri
        }
        return current
    }

    private fun ensurePath(root: Uri, relativePath: String): Uri {
        if (relativePath.isBlank()) return root
        var current = root
        for (component in relativePath.split('/').filter { it.isNotBlank() }) {
            current = ensureDirectory(current, component)
        }
        return current
    }

    private fun ensureDirectory(parent: Uri, name: String): Uri {
        val existing = findChild(parent, name)
        if (existing != null) {
            if (existing.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
                throw IllegalStateException("Esiste già un file chiamato $name.")
            }
            return existing.uri
        }
        return DocumentsContract.createDocument(
            context.contentResolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name,
        ) ?: throw IllegalStateException("Android non ha creato la cartella $name.")
    }

    private fun findChild(parent: Uri, name: String): ChildEntry? {
        return queryChildren(parent).firstOrNull { it.displayName.equals(name, ignoreCase = true) }
    }

    private fun queryChildren(parent: Uri): List<ChildEntry> {
        val parentDocumentId = DocumentsContract.getDocumentId(parent)
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(parent, parentDocumentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val children = mutableListOf<ChildEntry>()
        context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(idColumn) ?: continue
                val displayName = cursor.getString(nameColumn)?.trim().orEmpty()
                if (displayName.isEmpty()) continue
                children += ChildEntry(
                    uri = DocumentsContract.buildDocumentUriUsingTree(parent, documentId),
                    documentId = documentId,
                    displayName = displayName,
                    mimeType = cursor.getString(mimeColumn).orEmpty(),
                    sizeBytes = if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) cursor.getLong(sizeColumn) else 0L,
                    modifiedEpochMs = if (modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)) cursor.getLong(modifiedColumn) else 0L,
                )
            }
        } ?: throw IllegalStateException("Android non consente di leggere una cartella della galleria.")
        return children
    }

    private fun queryDocument(uri: Uri): ChildEntry? {
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedColumn = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            return ChildEntry(
                uri = uri,
                documentId = cursor.getString(idColumn).orEmpty(),
                displayName = cursor.getString(nameColumn).orEmpty(),
                mimeType = cursor.getString(mimeColumn).orEmpty(),
                sizeBytes = if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) cursor.getLong(sizeColumn) else 0L,
                modifiedEpochMs = if (modifiedColumn >= 0 && !cursor.isNull(modifiedColumn)) cursor.getLong(modifiedColumn) else 0L,
            )
        }
        return null
    }

    private fun queryDisplayName(uri: Uri): String = queryDocument(uri)?.displayName.orEmpty()

    private fun tokenSize(uri: Uri): Long = queryDocument(uri)?.sizeBytes?.coerceAtLeast(0L) ?: 0L

    private fun copyDocument(source: Uri, destination: Uri) {
        context.contentResolver.openInputStream(source)?.use { input ->
            context.contentResolver.openOutputStream(destination, "wt")?.use { output ->
                input.copyTo(output, DEFAULT_BUFFER_SIZE)
                output.flush()
            } ?: throw IllegalStateException("Android non consente di scrivere il file di destinazione.")
        } ?: throw IllegalStateException("Android non consente di leggere il file in .toDo.")
    }

    private fun restoreSource(destination: Uri, sourceParent: Uri, sourceName: String, mimeType: String) {
        val existing = findChild(sourceParent, sourceName)
        if (existing != null) return
        val restored = DocumentsContract.createDocument(
            context.contentResolver,
            sourceParent,
            mimeType,
            sourceName,
        ) ?: throw IllegalStateException("Impossibile ricreare il file originale in .toDo.")
        try {
            copyDocument(destination, restored)
            if (calculateSha256(destination) != calculateSha256(restored)) {
                throw IllegalStateException("La verifica del file ripristinato non è riuscita.")
            }
        } catch (error: Exception) {
            try {
                DocumentsContract.deleteDocument(context.contentResolver, restored)
            } catch (_: Exception) {
                // Conserva l'errore originale.
            }
            throw error
        }
    }

    private fun documentExists(uri: Uri): Boolean {
        return try {
            queryDocument(uri) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun calculateSha256(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(1024 * 1024)
        context.contentResolver.openInputStream(uri)?.use { input ->
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) digest.update(buffer, 0, count)
            }
        } ?: throw IllegalStateException("Android non consente di leggere il file.")
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun mimeTypeForExtension(extension: String): String {
        return MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension.lowercase(Locale.ROOT))
            ?: "application/octet-stream"
    }

    private fun validateFolderName(raw: String, kind: String): String {
        val cleaned = raw.trim()
        if (cleaned.isEmpty()) throw IllegalArgumentException("Il nome della $kind non può essere vuoto.")
        if (cleaned == "." || cleaned == "..") throw IllegalArgumentException("Nome della $kind non valido.")
        if (cleaned.startsWith('.') || cleaned.startsWith('!')) {
            throw IllegalArgumentException("Il nome della $kind non può iniziare con '.' oppure '!'.")
        }
        if (INVALID_WINDOWS_CHARS.containsMatchIn(cleaned)) {
            throw IllegalArgumentException("Il nome della $kind contiene caratteri non validi per Windows.")
        }
        if (cleaned.endsWith(' ') || cleaned.endsWith('.')) {
            throw IllegalArgumentException("Il nome della $kind non può terminare con uno spazio o un punto.")
        }
        if (cleaned.uppercase(Locale.ROOT) in WINDOWS_RESERVED_NAMES) {
            throw IllegalArgumentException("Il nome '$cleaned' è riservato da Windows.")
        }
        return cleaned
    }

    private fun validateFranchiseCode(raw: String): String {
        val cleaned = raw.filter(::isAsciiAlphanumeric).uppercase(Locale.ROOT)
        if (cleaned.length !in 1..10) {
            throw IllegalArgumentException("Il codice della serie deve contenere da 1 a 10 lettere o numeri ASCII.")
        }
        return cleaned
    }

    private fun deriveFranchiseCode(name: String): String {
        val ascii = toAscii(name)
        val words = ascii.trim()
            .split(Regex("[\\s_-]+"))
            .map { word -> word.filter(::isAsciiAlphanumeric) }
            .filter { it.isNotEmpty() }
        if (words.isEmpty()) return "FR"
        if (words.size > 1) {
            return words.joinToString("") { it.first().toString() }
                .take(10)
                .uppercase(Locale.ROOT)
                .ifBlank { "FR" }
        }
        val word = words.single()
        val consonants = word.filter {
            it.isAsciiLetter() && it.lowercaseChar() !in setOf('a', 'e', 'i', 'o', 'u')
        }
        return (consonants.take(4).ifBlank { word.take(4) })
            .uppercase(Locale.ROOT)
            .ifBlank { "FR" }
    }

    private fun normalizeFilenameComponent(value: String): String {
        return toAscii(value).filter(::isAsciiAlphanumeric).ifBlank { "Unknown" }
    }

    private fun toAscii(value: String): String {
        return Normalizer.normalize(value, Normalizer.Form.NFKD)
            .filter { it.code < 128 && !Character.isISOControl(it) }
    }

    private fun isAsciiAlphanumeric(value: Char): Boolean {
        return value in 'A'..'Z' || value in 'a'..'z' || value in '0'..'9'
    }

    private fun Char.isAsciiLetter(): Boolean {
        return this in 'A'..'Z' || this in 'a'..'z'
    }

    private fun franchiseToMap(record: FranchiseRecord): Map<String, Any> = mapOf(
        "id" to record.id,
        "syncUuid" to record.syncUuid,
        "name" to record.name,
        "code" to record.code,
        "relativePath" to record.relativePath,
    )

    private fun characterToMap(record: CharacterRecord): Map<String, Any> = mapOf(
        "id" to record.id,
        "syncUuid" to record.syncUuid,
        "franchiseId" to record.franchiseId,
        "name" to record.name,
        "relativePath" to record.relativePath,
        "franchiseName" to record.franchiseName,
        "franchiseCode" to record.franchiseCode,
        "label" to "${record.franchiseName} / ${record.name}",
    )

    private fun joinRelative(prefix: String, name: String): String {
        return if (prefix.isBlank()) name else "$prefix/$name"
    }

    private fun safeMessage(error: Exception): String {
        return error.message?.takeIf { it.isNotBlank() }
            ?: "Operazione non riuscita (${error.javaClass.simpleName})."
    }
}
