"use strict";

const byId = id => document.getElementById(id);

const dom = {
    globalStatus: byId("global-status"),
    navButtons: [...document.querySelectorAll(".nav-button")],
    galleryView: byId("gallery-view"),
    todoView: byId("todo-view"),
    trashView: byId("trash-view"),
    rankingView: byId("ranking-view"),
    settingsView: byId("settings-view"),
    todoBadge: byId("todo-badge"),
    trashBadge: byId("trash-badge"),
    archiveSyncButton: byId("archive-sync-button"),
    folderSyncButton: byId("folder-sync-button"),

    manualBackupCount: byId("manual-backup-count"),
    automaticBackupCount: byId("automatic-backup-count"),
    automaticBackupLimit: byId("automatic-backup-limit"),
    latestBackupDate: byId("latest-backup-date"),
    backupStatus: byId("backup-status"),
    backupList: byId("backup-list"),
    refreshBackupsButton: byId("refresh-backups-button"),
    createBackupButton: byId("create-backup-button"),
    exportMetadataButton: byId("export-metadata-button"),
    openBackupsFolderButton: byId("open-backups-folder-button"),

    breadcrumb: byId("breadcrumb"),
    globalSearch: byId("global-search"),
    globalSearchResults: byId("global-search-results"),
    overviewPanel: byId("overview-panel"),
    overviewSummary: byId("overview-summary"),
    franchiseGrid: byId("franchise-grid"),
    franchisePanel: byId("franchise-panel"),
    franchiseTitle: byId("franchise-title"),
    franchiseSubtitle: byId("franchise-subtitle"),
    characterGrid: byId("character-grid"),
    backToOverview: byId("back-to-overview"),
    mediaPanel: byId("media-panel"),
    mediaTitle: byId("media-title"),
    mediaSubtitle: byId("media-subtitle"),
    characterScoreBox: byId("character-score-box"),
    characterScoreMinus: byId("character-score-minus"),
    characterScorePlus: byId("character-score-plus"),
    characterScoreValue: byId("character-score-value"),
    mediaFilterForm: byId("media-filter-form"),
    mediaSearch: byId("media-search"),
    mediaTypeFilter: byId("media-type-filter"),
    mediaAiFilter: byId("media-ai-filter"),
    mediaTagFilter: byId("media-tag-filter"),
    mediaSort: byId("media-sort"),
    clearMediaFilters: byId("clear-media-filters"),
    mediaResultSummary: byId("media-result-summary"),
    galleryMediaGrid: byId("gallery-media-grid"),
    pagination: byId("pagination"),

    todoFolderPath: byId("todo-folder-path"),
    todoFileCount: byId("todo-file-count"),
    todoMediaGrid: byId("todo-media-grid"),
    refreshTodoButton: byId("refresh-todo-button"),

    trashSummary: byId("trash-summary"),
    trashMediaGrid: byId("trash-media-grid"),
    trashPagination: byId("trash-pagination"),
    refreshTrashButton: byId("refresh-trash-button"),
    emptyTrashButton: byId("empty-trash-button"),

    rankingFilter: byId("ranking-franchise-filter"),
    rankingList: byId("ranking-list"),

    cacheSize: byId("cache-size"),
    cacheFiles: byId("cache-files"),
    cacheStaticCount: byId("cache-static-count"),
    cachePreviewCount: byId("cache-preview-count"),
    ffmpegStatus: byId("ffmpeg-status"),
    cacheStatus: byId("cache-status"),
    refreshCacheStatsButton: byId("refresh-cache-stats-button"),
    cleanCacheButton: byId("clean-cache-button"),
    regenerateThumbnailsButton: byId("regenerate-thumbnails-button"),
    clearCacheButton: byId("clear-cache-button"),

    organizeDialog: byId("organize-dialog"),
    organizeForm: byId("organize-form"),
    closeOrganizeDialog: byId("close-organize-dialog"),
    cancelOrganize: byId("cancel-organize"),
    submitOrganize: byId("submit-organize"),
    dialogFilename: byId("dialog-filename"),
    dialogPreview: byId("dialog-preview"),
    organizeStatus: byId("organize-status"),
    organizeCharacterSearch: byId("organize-character-search"),
    organizeSearchResults: byId("organize-search-results"),
    organizeSelectedCharacters: byId("organize-selected-characters"),
    organizeTagsInput: byId("organize-tags-input"),
    organizeAiCheckbox: byId("organize-ai-checkbox"),
    destinationPreview: byId("destination-preview"),
    openCreateCharacter: byId("open-create-character"),

    createCharacterDialog: byId("create-character-dialog"),
    createCharacterForm: byId("create-character-form"),
    closeCreateCharacter: byId("close-create-character"),
    cancelCreateCharacter: byId("cancel-create-character"),
    submitCreateCharacter: byId("submit-create-character"),
    newCharacterName: byId("new-character-name"),
    franchiseSelect: byId("franchise-select"),
    newFranchiseFields: byId("new-franchise-fields"),
    newFranchiseName: byId("new-franchise-name"),
    newFranchiseCode: byId("new-franchise-code"),
    createCharacterStatus: byId("create-character-status"),

    fileDialog: byId("file-dialog"),
    fileEditForm: byId("file-edit-form"),
    fileDialogTitle: byId("file-dialog-title"),
    fileDialogPath: byId("file-dialog-path"),
    fileDialogPreview: byId("file-dialog-preview"),
    fileProperties: byId("file-properties"),
    editCharacterSearch: byId("edit-character-search"),
    editSearchResults: byId("edit-search-results"),
    editSelectedCharacters: byId("edit-selected-characters"),
    editTagsInput: byId("edit-tags-input"),
    editAiCheckbox: byId("edit-ai-checkbox"),
    fileDialogStatus: byId("file-dialog-status"),
    closeFileDialog: byId("close-file-dialog"),
    cancelFileEdit: byId("cancel-file-edit"),
    saveFileEdit: byId("save-file-edit"),
    revealFileButton: byId("reveal-file-button"),
    trashFileButton: byId("trash-file-button")
};

const NEW_FRANCHISE_VALUE = "__new__";

const state = {
    overview: null,
    franchises: [],
    currentFranchise: null,
    mediaContext: null,
    mediaPage: 1,
    trashPage: 1,
    activeTodoFile: null,
    organizeCharacters: [],
    activeGalleryFile: null,
    editCharacters: [],
    creationTarget: "organize",
    franchiseList: [],
    codeEditedManually: false,
    timers: {}
};

function setStatus(element, message, success = false) {
    element.textContent = message || "";
    element.classList.toggle("success", Boolean(success));
}

async function readJson(response) {
    const data = await response.json();
    if (!response.ok) {
        const detail = data.detail;
        const message = typeof detail === "string"
            ? detail
            : detail?.message || `Errore HTTP ${response.status}`;
        const error = new Error(message);
        error.status = response.status;
        error.detail = detail;
        throw error;
    }
    return data;
}

function formatFileSize(bytes) {
    if (!bytes) return "0 B";
    const units = ["B", "KB", "MB", "GB", "TB"];
    const unitIndex = Math.min(
        Math.floor(Math.log(bytes) / Math.log(1024)),
        units.length - 1
    );
    const value = bytes / Math.pow(1024, unitIndex);
    return `${value.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function formatDate(timestamp) {
    if (!timestamp) return "Data sconosciuta";
    return new Intl.DateTimeFormat("it-IT", {
        dateStyle: "medium",
        timeStyle: "short"
    }).format(new Date(timestamp * 1000));
}

function formatIsoDate(value) {
    if (!value) return "Data sconosciuta";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return new Intl.DateTimeFormat("it-IT", {
        dateStyle: "medium",
        timeStyle: "short"
    }).format(date);
}

function deriveFranchiseCode(name) {
    const normalized = name
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");
    const words = normalized
        .trim()
        .split(/[\s\-_]+/)
        .map(word => word.replace(/[^a-z0-9]/gi, ""))
        .filter(Boolean);

    if (words.length === 0) return "";

    if (words.length === 1) {
        const consonants = words[0]
            .replace(/[^a-z]/gi, "")
            .split("")
            .filter(character => !"AEIOU".includes(character.toUpperCase()))
            .join("");
        return (consonants.slice(0, 4) || words[0].slice(0, 4)).toUpperCase();
    }

    return words.map(word => word[0]).join("").slice(0, 10).toUpperCase();
}

function parseTags(value) {
    const result = [];
    const seen = new Set();
    for (const raw of value.split(",")) {
        const tag = raw.trim();
        const key = tag.toLocaleLowerCase("it-IT");
        if (tag && !seen.has(key)) {
            result.push(tag);
            seen.add(key);
        }
    }
    return result;
}

function createMediaElement(file, controls = false) {
    if (controls) {
        if (file.media_type === "image") {
            const image = document.createElement("img");
            image.src = file.media_url;
            image.alt = file.filename || file.name;
            image.loading = "eager";
            return image;
        }

        const video = document.createElement("video");
        video.src = file.media_url;
        video.controls = true;
        video.preload = "metadata";
        return video;
    }

    const image = document.createElement("img");
    const staticUrl = file.thumbnail_url || file.media_url;
    const animatedUrl = file.animated_preview_url || null;
    image.src = staticUrl;
    image.alt = file.filename || file.name;
    image.loading = "lazy";
    image.decoding = "async";
    image.className = "thumbnail-image";

    if (animatedUrl) {
        let previewLoaded = false;
        let previewFailed = false;

        const showPreview = () => {
            if (previewFailed) return;
            previewLoaded = true;
            image.src = animatedUrl;
        };
        const showStatic = () => {
            image.src = staticUrl;
        };

        image.addEventListener("mouseenter", showPreview);
        image.addEventListener("mouseleave", showStatic);
        image.addEventListener("focus", showPreview);
        image.addEventListener("blur", showStatic);
        image.addEventListener("error", () => {
            if (previewLoaded && image.src.includes(animatedUrl.split("?")[0])) {
                previewFailed = true;
                image.src = staticUrl;
            }
        });
        image.dataset.animatedPreview = "true";
    }

    return image;
}

function debounce(key, callback, delay = 180) {
    window.clearTimeout(state.timers[key]);
    state.timers[key] = window.setTimeout(callback, delay);
}

function showView(viewName) {
    dom.galleryView.hidden = viewName !== "gallery";
    dom.todoView.hidden = viewName !== "todo";
    dom.trashView.hidden = viewName !== "trash";
    dom.rankingView.hidden = viewName !== "ranking";
    dom.settingsView.hidden = viewName !== "settings";
    dom.navButtons.forEach(button => {
        button.classList.toggle("active", button.dataset.view === viewName);
    });

    if (viewName === "gallery") loadOverview(false);
    if (viewName === "todo") loadTodoFiles();
    if (viewName === "trash") loadTrashItems();
    if (viewName === "ranking") loadRanking();
    if (viewName === "settings") {
        loadCacheStats();
        loadBackups();
    }
}

function renderBreadcrumb(items) {
    dom.breadcrumb.replaceChildren();
    items.forEach((item, index) => {
        if (index > 0) {
            const separator = document.createElement("span");
            separator.textContent = "/";
            dom.breadcrumb.appendChild(separator);
        }
        if (item.action) {
            const button = document.createElement("button");
            button.type = "button";
            button.textContent = item.label;
            button.addEventListener("click", item.action);
            dom.breadcrumb.appendChild(button);
        } else {
            const strong = document.createElement("strong");
            strong.textContent = item.label;
            dom.breadcrumb.appendChild(strong);
        }
    });
}

function createCover(coverUrl, label) {
    const cover = document.createElement("div");
    cover.className = "collection-cover";
    if (coverUrl) {
        const image = document.createElement("img");
        image.src = coverUrl;
        image.alt = label;
        image.loading = "lazy";
        cover.appendChild(image);
    } else {
        const placeholder = document.createElement("span");
        placeholder.textContent = label.slice(0, 2).toUpperCase();
        cover.appendChild(placeholder);
    }
    return cover;
}

function createCollectionCard({ title, subtitle, coverUrl, badges = [], onClick, scoreControls = null }) {
    const card = document.createElement("article");
    card.className = "collection-card";
    card.tabIndex = 0;
    card.appendChild(createCover(coverUrl, title));

    const body = document.createElement("div");
    body.className = "collection-card-body";
    const heading = document.createElement("h3");
    heading.textContent = title;
    const description = document.createElement("p");
    description.textContent = subtitle;
    const badgeRow = document.createElement("div");
    badgeRow.className = "badge-row";
    badges.forEach(text => {
        const badge = document.createElement("span");
        badge.className = "meta-badge";
        badge.textContent = text;
        badgeRow.appendChild(badge);
    });
    body.append(heading, description, badgeRow);

    if (scoreControls) {
        const score = createInlineScore(scoreControls.character);
        body.appendChild(score);
    }

    card.appendChild(body);
    card.addEventListener("click", onClick);
    card.addEventListener("keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            onClick();
        }
    });
    return card;
}

function createInlineScore(character) {
    const row = document.createElement("div");
    row.className = "inline-score";

    const minus = document.createElement("button");
    minus.type = "button";
    minus.textContent = "−";
    minus.setAttribute("aria-label", `Diminuisci punteggio di ${character.name}`);

    const value = document.createElement("strong");
    value.textContent = character.score;

    const plus = document.createElement("button");
    plus.type = "button";
    plus.textContent = "+";
    plus.setAttribute("aria-label", `Aumenta punteggio di ${character.name}`);

    for (const [button, delta] of [[minus, -1], [plus, 1]]) {
        button.addEventListener("click", async event => {
            event.stopPropagation();
            try {
                const updated = await changeCharacterScore(character.id, delta);
                character.score = updated.score;
                value.textContent = updated.score;
                if (state.mediaContext?.kind === "character" && state.mediaContext.character.id === character.id) {
                    dom.characterScoreValue.textContent = updated.score;
                    state.mediaContext.character.score = updated.score;
                }
            } catch (error) {
                setStatus(dom.globalStatus, error.message);
            }
        });
    }

    row.append(minus, value, plus);
    return row;
}

async function loadOverview(force = true, render = true) {
    if (!force && state.overview) {
        if (render && !state.currentFranchise && !state.mediaContext) renderOverview();
        return;
    }
    setStatus(dom.globalStatus, "Caricamento galleria...");
    try {
        state.overview = await readJson(await fetch("/api/gallery/overview"));
        state.franchises = state.overview.franchises;
        dom.todoBadge.textContent = state.overview.todo_count;
        dom.trashBadge.textContent = state.overview.trash_count || 0;
        if (render) renderOverview();
        populateRankingFranchiseFilter();
        setStatus(dom.globalStatus, "");
    } catch (error) {
        console.error(error);
        setStatus(dom.globalStatus, `Impossibile caricare la galleria: ${error.message}`);
    }
}

function renderOverview() {
    state.currentFranchise = null;
    state.mediaContext = null;
    dom.overviewPanel.hidden = false;
    dom.franchisePanel.hidden = true;
    dom.mediaPanel.hidden = true;
    renderBreadcrumb([{ label: "Galleria" }]);

    const summary = state.overview.summary;
    const stats = [
        [summary.franchises, "serie"],
        [summary.total_files, "file"],
        [summary.images, "immagini"],
        [summary.videos, "video"],
        [summary.ai_files, "IA"]
    ];
    dom.overviewSummary.replaceChildren(...stats.map(([value, label]) => {
        const card = document.createElement("div");
        card.className = "stat-card";
        const strong = document.createElement("strong");
        strong.textContent = value;
        const span = document.createElement("span");
        span.textContent = label;
        card.append(strong, span);
        return card;
    }));

    dom.franchiseGrid.replaceChildren();
    const fragment = document.createDocumentFragment();
    state.overview.franchises.forEach(franchise => {
        fragment.appendChild(createCollectionCard({
            title: franchise.name,
            subtitle: `${franchise.character_count} personaggi · ${franchise.total_files} file`,
            coverUrl: franchise.cover_url,
            badges: [`${franchise.images} immagini`, `${franchise.videos} video`, `${franchise.ai_files} IA`],
            onClick: () => openFranchise(franchise.id)
        }));
    });

    const crossovers = state.overview.crossovers;
    fragment.appendChild(createCollectionCard({
        title: crossovers.name,
        subtitle: `${crossovers.total_files} file con serie differenti`,
        coverUrl: crossovers.cover_url,
        badges: [`${crossovers.images} immagini`, `${crossovers.videos} video`, `${crossovers.ai_files} IA`],
        onClick: () => openMediaContext({ kind: "crossovers", title: crossovers.name })
    }));
    dom.franchiseGrid.appendChild(fragment);
}

async function openFranchise(franchiseId) {
    setStatus(dom.globalStatus, "Caricamento personaggi...");
    try {
        const data = await readJson(await fetch(`/api/gallery/franchises/${franchiseId}/characters`));
        state.currentFranchise = data;
        state.mediaContext = null;
        dom.overviewPanel.hidden = true;
        dom.mediaPanel.hidden = true;
        dom.franchisePanel.hidden = false;
        dom.franchiseTitle.textContent = data.franchise.name;
        dom.franchiseSubtitle.textContent = `${data.characters.length} personaggi`;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: data.franchise.name }
        ]);
        renderCharacterGrid(data);
        setStatus(dom.globalStatus, "");
    } catch (error) {
        console.error(error);
        setStatus(dom.globalStatus, error.message);
    }
}

function renderCharacterGrid(data) {
    dom.characterGrid.replaceChildren();
    const fragment = document.createDocumentFragment();

    data.characters.forEach(character => {
        fragment.appendChild(createCollectionCard({
            title: character.name,
            subtitle: `${character.total_files} file associati`,
            coverUrl: character.cover_url,
            badges: [`${character.images} immagini`, `${character.videos} video`, `${character.ai_files} IA`],
            scoreControls: { character },
            onClick: () => openMediaContext({
                kind: "character",
                title: character.name,
                character,
                franchise: data.franchise
            })
        }));
    });

    fragment.appendChild(createCollectionCard({
        title: data.multiple.name,
        subtitle: `${data.multiple.total_files} file con più personaggi`,
        coverUrl: data.multiple.cover_url,
        badges: [`${data.multiple.images} immagini`, `${data.multiple.videos} video`, `${data.multiple.ai_files} IA`],
        onClick: () => openMediaContext({
            kind: "multiple",
            title: `${data.franchise.name} / ${data.multiple.name}`,
            franchise: data.franchise
        })
    }));

    dom.characterGrid.appendChild(fragment);
}

function openMediaContext(context) {
    state.mediaContext = context;
    resetMediaFilters();
    dom.overviewPanel.hidden = true;
    dom.franchisePanel.hidden = true;
    dom.mediaPanel.hidden = false;
    dom.mediaTitle.textContent = context.title;

    if (context.kind === "character") {
        dom.mediaSubtitle.textContent = `${context.franchise.name} · tutti i file associati, inclusi !Multiple e crossover`;
        dom.characterScoreBox.hidden = false;
        dom.characterScoreValue.textContent = context.character.score;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: context.franchise.name, action: () => openFranchise(context.franchise.id) },
            { label: context.character.name }
        ]);
    } else if (context.kind === "multiple") {
        dom.mediaSubtitle.textContent = "File conservati fisicamente nella cartella !Multiple";
        dom.characterScoreBox.hidden = true;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: context.franchise.name, action: () => openFranchise(context.franchise.id) },
            { label: "!Multiple" }
        ]);
    } else if (context.kind === "crossovers") {
        dom.mediaSubtitle.textContent = "File con personaggi appartenenti a serie differenti";
        dom.characterScoreBox.hidden = true;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: "!Crossovers" }
        ]);
    } else if (context.kind === "tag") {
        dom.mediaSubtitle.textContent = `Ricerca per il tag “${context.tag}”`;
        dom.characterScoreBox.hidden = true;
        dom.mediaTagFilter.value = context.tag;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: `Tag: ${context.tag}` }
        ]);
    }

    loadGalleryFiles();
}

function buildGalleryFileQuery() {
    const params = new URLSearchParams();
    const context = state.mediaContext;
    if (context.kind === "character") params.set("character_id", context.character.id);
    if (context.kind === "multiple") {
        params.set("franchise_id", context.franchise.id);
        params.set("collection", "multiple");
    }
    if (context.kind === "crossovers") params.set("collection", "crossovers");

    if (dom.mediaTypeFilter.value) params.set("media_type", dom.mediaTypeFilter.value);
    if (dom.mediaAiFilter.value) params.set("ai_generated", dom.mediaAiFilter.value);
    if (dom.mediaSearch.value.trim()) params.set("q", dom.mediaSearch.value.trim());
    const tags = parseTags(dom.mediaTagFilter.value);
    if (context.kind === "tag" && !tags.some(tag => tag.toLocaleLowerCase("it-IT") === context.tag.toLocaleLowerCase("it-IT"))) {
        tags.unshift(context.tag);
    }
    tags.forEach(tag => params.append("tags", tag));
    params.set("sort", dom.mediaSort.value);
    params.set("page", state.mediaPage);
    params.set("limit", "60");
    return params;
}

async function loadGalleryFiles() {
    if (!state.mediaContext) return;
    dom.galleryMediaGrid.replaceChildren();
    dom.pagination.replaceChildren();
    dom.mediaResultSummary.textContent = "Caricamento...";
    try {
        const data = await readJson(await fetch(`/api/gallery/files?${buildGalleryFileQuery()}`));
        dom.mediaResultSummary.textContent = `${data.total} file · pagina ${data.page} di ${data.pages}`;
        renderGalleryMediaCards(data.files);
        renderPagination(data.page, data.pages);
    } catch (error) {
        console.error(error);
        dom.mediaResultSummary.textContent = "Errore";
        setStatus(dom.globalStatus, error.message);
    }
}

function createGalleryMediaCard(file) {
    const card = document.createElement("article");
    card.className = "media-card gallery-file-card";

    const previewButton = document.createElement("button");
    previewButton.type = "button";
    previewButton.className = "preview-container preview-button";
    previewButton.classList.toggle("has-animated-preview", Boolean(file.animated_preview_url));
    previewButton.classList.toggle("video-thumbnail", file.media_type === "video");
    previewButton.appendChild(createMediaElement(file));
    previewButton.addEventListener("click", () => openFileDialog(file.id));

    const info = document.createElement("div");
    info.className = "media-info";
    const name = document.createElement("p");
    name.className = "media-name";
    name.textContent = file.filename;
    name.title = file.relative_path;

    const details = document.createElement("p");
    details.className = "media-details";
    details.innerHTML = `<span>${file.media_type === "image" ? "Immagine" : "Video"}</span><span>${formatFileSize(file.size)}</span>`;

    const tags = document.createElement("div");
    tags.className = "card-tags";
    file.tags.slice(0, 4).forEach(tag => {
        const chip = document.createElement("span");
        chip.textContent = tag.name;
        tags.appendChild(chip);
    });

    const characters = document.createElement("p");
    characters.className = "card-characters";
    characters.textContent = file.characters.length
        ? file.characters.map(character => character.name).join(", ")
        : "Nessun personaggio associato";

    info.append(name, details, characters, tags);
    card.append(previewButton, info);
    return card;
}

function renderGalleryMediaCards(files) {
    dom.galleryMediaGrid.replaceChildren();
    if (files.length === 0) {
        const empty = document.createElement("p");
        empty.className = "empty-message";
        empty.textContent = "Nessun file corrisponde ai filtri selezionati.";
        dom.galleryMediaGrid.appendChild(empty);
        return;
    }
    const fragment = document.createDocumentFragment();
    files.forEach(file => fragment.appendChild(createGalleryMediaCard(file)));
    dom.galleryMediaGrid.appendChild(fragment);
}

function renderPagination(page, pages) {
    dom.pagination.replaceChildren();
    if (pages <= 1) return;

    const previous = document.createElement("button");
    previous.type = "button";
    previous.textContent = "← Precedente";
    previous.disabled = page <= 1;
    previous.addEventListener("click", () => {
        state.mediaPage = page - 1;
        loadGalleryFiles();
        window.scrollTo({ top: 0, behavior: "smooth" });
    });

    const label = document.createElement("span");
    label.textContent = `${page} / ${pages}`;

    const next = document.createElement("button");
    next.type = "button";
    next.textContent = "Successiva →";
    next.disabled = page >= pages;
    next.addEventListener("click", () => {
        state.mediaPage = page + 1;
        loadGalleryFiles();
        window.scrollTo({ top: 0, behavior: "smooth" });
    });

    dom.pagination.append(previous, label, next);
}

async function runGlobalSearch() {
    const query = dom.globalSearch.value.trim();
    dom.globalSearchResults.replaceChildren();
    if (!query) return;

    try {
        const data = await readJson(await fetch(`/api/gallery/search?q=${encodeURIComponent(query)}`));
        const fragment = document.createDocumentFragment();

        data.characters.forEach(character => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "floating-result";
            button.innerHTML = `<strong>${escapeHtml(character.name)}</strong><small>${escapeHtml(character.franchise_name)}</small>`;
            button.addEventListener("click", async () => {
                dom.globalSearchResults.replaceChildren();
                const franchiseData = await readJson(await fetch(`/api/gallery/franchises/${character.franchise_id}/characters`));
                const fullCharacter = franchiseData.characters.find(item => item.id === character.id) || character;
                openMediaContext({
                    kind: "character",
                    title: character.name,
                    character: fullCharacter,
                    franchise: franchiseData.franchise
                });
            });
            fragment.appendChild(button);
        });

        data.tags.forEach(tag => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "floating-result";
            button.innerHTML = `<strong>#${escapeHtml(tag.name)}</strong><small>${tag.file_count} file</small>`;
            button.addEventListener("click", () => {
                dom.globalSearchResults.replaceChildren();
                resetMediaFilters();
                openMediaContext({ kind: "tag", title: `Tag: ${tag.name}`, tag: tag.name });
            });
            fragment.appendChild(button);
        });

        if (!fragment.childNodes.length) {
            const empty = document.createElement("p");
            empty.className = "floating-empty";
            empty.textContent = "Nessun risultato.";
            fragment.appendChild(empty);
        }
        dom.globalSearchResults.appendChild(fragment);
    } catch (error) {
        console.error(error);
    }
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function resetMediaFilters() {
    dom.mediaSearch.value = "";
    dom.mediaTypeFilter.value = "";
    dom.mediaAiFilter.value = "";
    dom.mediaTagFilter.value = "";
    dom.mediaSort.value = "newest";
    state.mediaPage = 1;
}

async function loadTodoFiles() {
    dom.todoFileCount.textContent = "Caricamento...";
    dom.todoMediaGrid.replaceChildren();
    try {
        const data = await readJson(await fetch("/api/todo/files"));
        dom.todoFileCount.textContent = `${data.total_files} file da sistemare`;
        dom.todoFolderPath.textContent = "File in attesa di organizzazione";
        dom.todoBadge.textContent = data.total_files;

        if (data.files.length === 0) {
            const empty = document.createElement("p");
            empty.className = "empty-message";
            empty.textContent = "New non contiene immagini o video.";
            dom.todoMediaGrid.appendChild(empty);
            return;
        }

        const fragment = document.createDocumentFragment();
        data.files.forEach(file => {
            const card = document.createElement("article");
            card.className = "media-card";
            const preview = document.createElement("div");
            preview.className = "preview-container";
            preview.classList.toggle("has-animated-preview", Boolean(file.animated_preview_url));
            preview.classList.toggle("video-thumbnail", file.media_type === "video");
            preview.appendChild(createMediaElement(file));
            const info = document.createElement("div");
            info.className = "media-info";
            const name = document.createElement("p");
            name.className = "media-name";
            name.textContent = file.name;
            name.title = file.relative_path;
            const details = document.createElement("p");
            details.className = "media-details";
            details.innerHTML = `<span>${file.media_type === "image" ? "Immagine" : "Video"}</span><span>${formatFileSize(file.size)}</span>`;
            const actions = document.createElement("div");
            actions.className = "card-actions";
            const button = document.createElement("button");
            button.type = "button";
            button.className = "organize-button";
            button.textContent = "Organizza";
            button.addEventListener("click", () => openOrganizer(file));
            const trashButton = document.createElement("button");
            trashButton.type = "button";
            trashButton.className = "danger-button compact-button";
            trashButton.textContent = "Cestino";
            trashButton.addEventListener("click", () => trashTodoFile(file));
            actions.append(button, trashButton);
            info.append(name, details, actions);
            card.append(preview, info);
            fragment.appendChild(card);
        });
        dom.todoMediaGrid.appendChild(fragment);
    } catch (error) {
        console.error(error);
        dom.todoFileCount.textContent = "Errore";
        setStatus(dom.globalStatus, error.message);
    }
}

async function trashTodoFile(file) {
    const confirmed = window.confirm(`Spostare "${file.name}" nel cestino?`);
    if (!confirmed) return;
    try {
        await readJson(await fetch("/api/todo/trash", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ relative_path: file.relative_path })
        }));
        await Promise.all([loadTodoFiles(), loadOverview(true, false)]);
        setStatus(dom.globalStatus, "File spostato nel cestino.", true);
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

async function loadTrashItems(page = state.trashPage) {
    state.trashPage = Math.max(1, page);
    dom.trashSummary.textContent = "Caricamento...";
    dom.trashMediaGrid.replaceChildren();
    dom.trashPagination.replaceChildren();
    try {
        const data = await readJson(await fetch(`/api/trash?page=${state.trashPage}&limit=60`));
        state.trashPage = data.page;
        dom.trashBadge.textContent = data.total;
        dom.trashSummary.textContent = `${data.total} file · ${formatFileSize(data.total_size)}`;
        dom.emptyTrashButton.disabled = data.total === 0;

        if (!data.items.length && data.total > 0 && state.trashPage > data.pages) {
            return loadTrashItems(data.pages);
        }

        if (!data.items.length) {
            const empty = document.createElement("p");
            empty.className = "empty-message";
            empty.textContent = "Il cestino è vuoto.";
            dom.trashMediaGrid.appendChild(empty);
            return;
        }

        const fragment = document.createDocumentFragment();
        data.items.forEach(item => fragment.appendChild(createTrashCard(item)));
        dom.trashMediaGrid.appendChild(fragment);
        renderTrashPagination(data.page, data.pages);
    } catch (error) {
        dom.trashSummary.textContent = "Errore";
        setStatus(dom.globalStatus, error.message);
    }
}

function createTrashCard(item) {
    const card = document.createElement("article");
    card.className = "media-card trash-card";

    const preview = document.createElement("div");
    preview.className = "preview-container";
    preview.classList.toggle("has-animated-preview", Boolean(item.animated_preview_url));
    preview.classList.toggle("video-thumbnail", item.media_type === "video");
    preview.appendChild(createMediaElement(item));

    const info = document.createElement("div");
    info.className = "media-info";
    const name = document.createElement("p");
    name.className = "media-name";
    name.textContent = item.filename;

    const details = document.createElement("p");
    details.className = "media-details";
    details.innerHTML = `<span>${item.media_type === "image" ? "Immagine" : "Video"}</span><span>${formatFileSize(item.size)}</span>`;

    const source = document.createElement("p");
    source.className = "trash-source";
    source.textContent = item.source_kind === "todo"
        ? `Origine: New / ${item.original_relative_path}`
        : `Origine: ${item.original_relative_path}`;
    source.title = source.textContent;

    const deleted = document.createElement("p");
    deleted.className = "trash-date";
    deleted.textContent = `Eliminato: ${formatDatabaseDate(item.deleted_at)}`;

    const metadata = document.createElement("p");
    metadata.className = "card-characters";
    metadata.textContent = item.characters.length
        ? item.characters.map(character => character.name).join(", ")
        : item.source_kind === "todo" ? "Non ancora organizzato" : "Nessun personaggio associato";

    const tags = document.createElement("div");
    tags.className = "card-tags";
    item.tags.slice(0, 4).forEach(tag => {
        const chip = document.createElement("span");
        chip.textContent = tag.name;
        tags.appendChild(chip);
    });

    const actions = document.createElement("div");
    actions.className = "card-actions";
    const restore = document.createElement("button");
    restore.type = "button";
    restore.textContent = "Ripristina";
    restore.addEventListener("click", () => restoreTrashItem(item, false));
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "danger-button";
    remove.textContent = "Elimina definitivamente";
    remove.addEventListener("click", () => deleteTrashItem(item));
    actions.append(restore, remove);

    info.append(name, details, source, deleted, metadata, tags, actions);
    card.append(preview, info);
    return card;
}

function formatDatabaseDate(value) {
    if (!value) return "Data sconosciuta";
    const normalized = value.includes("T") ? value : value.replace(" ", "T") + "Z";
    const date = new Date(normalized);
    if (Number.isNaN(date.getTime())) return value;
    return new Intl.DateTimeFormat("it-IT", {
        dateStyle: "medium",
        timeStyle: "short"
    }).format(date);
}

async function restoreTrashItem(item, autoRename) {
    try {
        const response = await fetch(`/api/trash/${item.id}/restore`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ auto_rename: autoRename })
        });
        if (response.status === 409) {
            const data = await response.json();
            const message = data.detail?.message || "La destinazione è già occupata.";
            const confirmed = window.confirm(`${message}\n\nRinominare automaticamente e ripristinare?`);
            if (confirmed) return restoreTrashItem(item, true);
            return;
        }
        const result = await readJson(response);
        setStatus(
            dom.globalStatus,
            result.renamed ? "File ripristinato con un nuovo nome." : "File ripristinato.",
            true
        );
        await Promise.all([loadTrashItems(), loadOverview(true, false)]);
        if (result.source_kind === "todo" && !dom.todoView.hidden) await loadTodoFiles();
        if (!dom.galleryView.hidden && state.mediaContext) await loadGalleryFiles();
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

async function deleteTrashItem(item) {
    const confirmed = window.confirm(
        `Eliminare definitivamente "${item.filename}"?\n\nQuesta operazione non può essere annullata.`
    );
    if (!confirmed) return;
    try {
        await readJson(await fetch(`/api/trash/${item.id}`, { method: "DELETE" }));
        setStatus(dom.globalStatus, "File eliminato definitivamente.", true);
        await Promise.all([loadTrashItems(), loadOverview(true, false)]);
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

async function emptyTrashFromUi() {
    const confirmation = window.prompt(
        "Tutti i file nel cestino saranno eliminati definitivamente.\n\nScrivi ELIMINA per confermare."
    );
    if (confirmation === null) return;
    if (confirmation !== "ELIMINA") {
        setStatus(dom.globalStatus, "Conferma non valida: il cestino non è stato svuotato.");
        return;
    }
    dom.emptyTrashButton.disabled = true;
    try {
        const result = await readJson(await fetch("/api/trash/empty", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ confirmation })
        }));
        const suffix = result.errors.length ? ` ${result.errors.length} elementi non eliminati.` : "";
        setStatus(dom.globalStatus, `Cestino svuotato: ${result.deleted} file eliminati.${suffix} Backup metadati: ${result.automatic_backup}.`, result.errors.length === 0);
        state.trashPage = 1;
        await Promise.all([loadTrashItems(), loadOverview(true, false)]);
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    } finally {
        dom.emptyTrashButton.disabled = Number(dom.trashBadge.textContent || 0) === 0;
    }
}

function renderTrashPagination(page, pages) {
    dom.trashPagination.replaceChildren();
    if (pages <= 1) return;
    const previous = document.createElement("button");
    previous.type = "button";
    previous.textContent = "← Precedente";
    previous.disabled = page <= 1;
    previous.addEventListener("click", () => loadTrashItems(page - 1));
    const label = document.createElement("span");
    label.textContent = `${page} / ${pages}`;
    const next = document.createElement("button");
    next.type = "button";
    next.textContent = "Successiva →";
    next.disabled = page >= pages;
    next.addEventListener("click", () => loadTrashItems(page + 1));
    dom.trashPagination.append(previous, label, next);
}

function renderSelectedCharacters(container, selected, onRemove) {
    container.replaceChildren();
    if (!selected.length) {
        const empty = document.createElement("span");
        empty.className = "selection-placeholder";
        empty.textContent = "Nessun personaggio selezionato.";
        container.appendChild(empty);
        return;
    }
    selected.forEach(character => {
        const chip = document.createElement("span");
        chip.className = "character-chip";
        const label = document.createElement("span");
        label.textContent = character.label || `${character.franchise_name} / ${character.name}`;
        const remove = document.createElement("button");
        remove.type = "button";
        remove.textContent = "×";
        remove.setAttribute("aria-label", `Rimuovi ${character.name}`);
        remove.addEventListener("click", () => onRemove(character.id));
        chip.append(label, remove);
        container.appendChild(chip);
    });
}

async function searchCharacterNames(query, resultsContainer, selected, addCallback, createCallback = null) {
    resultsContainer.replaceChildren();
    const cleaned = query.trim();
    if (!cleaned) return;
    try {
        const data = await readJson(await fetch(`/api/characters/search?q=${encodeURIComponent(cleaned)}`));
        const selectedIds = new Set(selected.map(character => character.id));
        data.results.filter(character => !selectedIds.has(character.id)).forEach(character => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "search-result";
            const name = document.createElement("strong");
            name.textContent = character.name;
            const franchise = document.createElement("small");
            franchise.textContent = character.franchise_name;
            button.append(name, franchise);
            button.addEventListener("click", () => addCallback(character));
            resultsContainer.appendChild(button);
        });

        if (data.results.length === 0 && createCallback) {
            const box = document.createElement("div");
            box.className = "no-search-results";
            const text = document.createElement("span");
            text.textContent = `Nessun personaggio trovato per “${cleaned}”.`;
            const create = document.createElement("button");
            create.type = "button";
            create.className = "text-button";
            create.textContent = "+ Crea questo personaggio";
            create.addEventListener("click", () => createCallback(cleaned));
            box.append(text, create);
            resultsContainer.appendChild(box);
        }
    } catch (error) {
        console.error(error);
    }
}

function openOrganizer(file) {
    state.activeTodoFile = file;
    state.organizeCharacters = [];
    dom.dialogFilename.textContent = file.relative_path;
    dom.dialogPreview.replaceChildren(createMediaElement(file, true));
    dom.organizeCharacterSearch.value = "";
    dom.organizeSearchResults.replaceChildren();
    dom.organizeTagsInput.value = "";
    dom.organizeAiCheckbox.checked = false;
    dom.destinationPreview.textContent = "Seleziona almeno un personaggio.";
    setStatus(dom.organizeStatus, "");
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
    dom.organizeDialog.showModal();
    dom.organizeCharacterSearch.focus();
}

function closeOrganizer() {
    dom.organizeDialog.close();
    state.activeTodoFile = null;
}

function addOrganizeCharacter(character) {
    if (!state.organizeCharacters.some(item => item.id === character.id)) {
        state.organizeCharacters.push(character);
    }
    dom.organizeCharacterSearch.value = "";
    dom.organizeSearchResults.replaceChildren();
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
    updateDestinationPreview();
}

function removeOrganizeCharacter(characterId) {
    state.organizeCharacters = state.organizeCharacters.filter(item => item.id !== characterId);
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
    updateDestinationPreview();
}

async function updateDestinationPreview() {
    if (!state.activeTodoFile || !state.organizeCharacters.length) {
        dom.destinationPreview.textContent = "Seleziona almeno un personaggio.";
        return;
    }
    try {
        const response = await fetch("/api/organize/preview", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                character_ids: state.organizeCharacters.map(character => character.id),
                ai_generated: dom.organizeAiCheckbox.checked,
                extension: state.activeTodoFile.extension
            })
        });
        const data = await readJson(response);
        dom.destinationPreview.textContent = data.destination_relative_path;
    } catch (error) {
        dom.destinationPreview.textContent = error.message;
    }
}

async function submitOrganization(allowDuplicate = false) {
    if (!state.activeTodoFile) return;
    if (!state.organizeCharacters.length) {
        setStatus(dom.organizeStatus, "Seleziona almeno un personaggio.");
        return;
    }

    dom.submitOrganize.disabled = true;
    setStatus(dom.organizeStatus, "Spostamento in corso...");
    try {
        const response = await fetch("/api/organize", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                relative_path: state.activeTodoFile.relative_path,
                character_ids: state.organizeCharacters.map(character => character.id),
                tags: parseTags(dom.organizeTagsInput.value),
                ai_generated: dom.organizeAiCheckbox.checked,
                allow_duplicate: allowDuplicate
            })
        });

        if (response.status === 409) {
            const data = await response.json();
            const duplicate = data.detail?.duplicate;
            const keep = window.confirm(
                `Duplicato identico trovato:\n${duplicate?.relative_path || "percorso sconosciuto"}\n\nConservare comunque entrambi?`
            );
            if (keep) await submitOrganization(true);
            else setStatus(dom.organizeStatus, "Operazione annullata.");
            return;
        }

        const result = await readJson(response);
        setStatus(dom.globalStatus, `File organizzato: ${result.relative_path}`, true);
        closeOrganizer();
        await Promise.all([loadTodoFiles(), loadOverview(true, false)]);
    } catch (error) {
        console.error(error);
        setStatus(dom.organizeStatus, error.message);
    } finally {
        dom.submitOrganize.disabled = false;
    }
}

async function loadFranchises() {
    const data = await readJson(await fetch("/api/franchises"));
    state.franchiseList = data.results;
    return state.franchiseList;
}

function populateFranchiseSelect() {
    dom.franchiseSelect.replaceChildren();
    state.franchiseList.forEach(franchise => {
        const option = document.createElement("option");
        option.value = franchise.id;
        option.textContent = `${franchise.name} (${franchise.code})`;
        dom.franchiseSelect.appendChild(option);
    });
    const newOption = document.createElement("option");
    newOption.value = NEW_FRANCHISE_VALUE;
    newOption.textContent = "+ Crea nuova serie";
    dom.franchiseSelect.appendChild(newOption);
}

async function openCreateCharacterDialog(initialName = "", target = "organize") {
    state.creationTarget = target;
    setStatus(dom.createCharacterStatus, "");
    dom.createCharacterForm.reset();
    dom.newCharacterName.value = initialName.trim();
    dom.newFranchiseFields.hidden = true;
    state.codeEditedManually = false;
    try {
        await loadFranchises();
        populateFranchiseSelect();
        if (!state.franchiseList.length) {
            dom.franchiseSelect.value = NEW_FRANCHISE_VALUE;
            updateNewFranchiseVisibility();
        }
        dom.createCharacterDialog.showModal();
        dom.newCharacterName.focus();
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

function updateNewFranchiseVisibility() {
    const isNew = dom.franchiseSelect.value === NEW_FRANCHISE_VALUE;
    dom.newFranchiseFields.hidden = !isNew;
    dom.newFranchiseName.required = isNew;
    dom.newFranchiseCode.required = false;
    if (isNew && !dom.newFranchiseCode.value) {
        dom.newFranchiseCode.value = deriveFranchiseCode(dom.newFranchiseName.value);
    }
}

async function createCharacterFromForm() {
    dom.submitCreateCharacter.disabled = true;
    setStatus(dom.createCharacterStatus, "");
    try {
        let franchiseId;
        if (dom.franchiseSelect.value === NEW_FRANCHISE_VALUE) {
            const franchise = await readJson(await fetch("/api/franchises", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    name: dom.newFranchiseName.value.trim(),
                    code: dom.newFranchiseCode.value.trim()
                })
            }));
            franchiseId = franchise.id;
        } else {
            franchiseId = Number(dom.franchiseSelect.value);
        }

        const character = await readJson(await fetch("/api/characters", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                franchise_id: franchiseId,
                name: dom.newCharacterName.value.trim()
            })
        }));

        dom.createCharacterDialog.close();
        if (state.creationTarget === "edit") addEditCharacter(character);
        else addOrganizeCharacter(character);
        await loadOverview(true, false);
        setStatus(dom.globalStatus, `Creato: ${character.label}`, true);
    } catch (error) {
        setStatus(dom.createCharacterStatus, error.message);
    } finally {
        dom.submitCreateCharacter.disabled = false;
    }
}

async function openFileDialog(fileId) {
    setStatus(dom.fileDialogStatus, "Caricamento...");
    dom.fileDialog.showModal();
    try {
        const file = await readJson(await fetch(`/api/gallery/files/${fileId}`));
        state.activeGalleryFile = file;
        state.editCharacters = [...file.characters];
        dom.fileDialogTitle.textContent = file.filename;
        dom.fileDialogPath.textContent = file.relative_path;
        dom.fileDialogPreview.replaceChildren(createMediaElement(file, true));
        dom.editCharacterSearch.value = "";
        dom.editSearchResults.replaceChildren();
        dom.editTagsInput.value = file.tags
            .filter(tag => tag.name.toLocaleLowerCase("it-IT") !== "ai")
            .map(tag => tag.name)
            .join(", ");
        dom.editAiCheckbox.checked = file.ai_generated;
        renderSelectedCharacters(dom.editSelectedCharacters, state.editCharacters, removeEditCharacter);
        renderFileProperties(file);
        setStatus(dom.fileDialogStatus, file.characters.length ? "" : "Questo file non ha personaggi associati.");
    } catch (error) {
        setStatus(dom.fileDialogStatus, error.message);
    }
}

function renderFileProperties(file) {
    const properties = [
        ["Tipo", file.media_type === "image" ? "Immagine" : "Video"],
        ["Dimensione", formatFileSize(file.size)],
        ["Modificato", formatDate(file.modified_at)],
        ["Hash", file.sha256.slice(0, 16) + "…"]
    ];
    dom.fileProperties.replaceChildren();
    properties.forEach(([term, value]) => {
        const dt = document.createElement("dt");
        dt.textContent = term;
        const dd = document.createElement("dd");
        dd.textContent = value;
        dom.fileProperties.append(dt, dd);
    });
}

function closeFileDialog() {
    dom.fileDialog.close();
    state.activeGalleryFile = null;
    state.editCharacters = [];
}

function addEditCharacter(character) {
    if (!state.editCharacters.some(item => item.id === character.id)) {
        state.editCharacters.push(character);
    }
    dom.editCharacterSearch.value = "";
    dom.editSearchResults.replaceChildren();
    renderSelectedCharacters(dom.editSelectedCharacters, state.editCharacters, removeEditCharacter);
}

function removeEditCharacter(characterId) {
    state.editCharacters = state.editCharacters.filter(item => item.id !== characterId);
    renderSelectedCharacters(dom.editSelectedCharacters, state.editCharacters, removeEditCharacter);
}

async function saveFileMetadata() {
    if (!state.activeGalleryFile) return;
    if (!state.editCharacters.length) {
        setStatus(dom.fileDialogStatus, "Seleziona almeno un personaggio.");
        return;
    }
    dom.saveFileEdit.disabled = true;
    setStatus(dom.fileDialogStatus, "Salvataggio...");
    try {
        const result = await readJson(await fetch(`/api/gallery/files/${state.activeGalleryFile.id}`, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                character_ids: state.editCharacters.map(character => character.id),
                tags: parseTags(dom.editTagsInput.value),
                ai_generated: dom.editAiCheckbox.checked
            })
        }));
        state.activeGalleryFile = result;
        dom.fileDialogTitle.textContent = result.filename;
        dom.fileDialogPath.textContent = result.relative_path;
        setStatus(dom.fileDialogStatus, result.moved ? "Salvato e file spostato." : "Modifiche salvate.", true);
        await Promise.all([loadGalleryFiles(), loadOverview(true, false)]);
    } catch (error) {
        setStatus(dom.fileDialogStatus, error.message);
    } finally {
        dom.saveFileEdit.disabled = false;
    }
}

async function revealActiveFile() {
    if (!state.activeGalleryFile) return;
    try {
        await readJson(await fetch(`/api/gallery/files/${state.activeGalleryFile.id}/reveal`, { method: "POST" }));
        setStatus(dom.fileDialogStatus, "Aperto in Esplora file.", true);
    } catch (error) {
        setStatus(dom.fileDialogStatus, error.message);
    }
}

async function trashActiveGalleryFile() {
    if (!state.activeGalleryFile) return;
    const file = state.activeGalleryFile;
    const confirmed = window.confirm(`Spostare "${file.filename}" nel cestino?`);
    if (!confirmed) return;
    dom.trashFileButton.disabled = true;
    try {
        await readJson(await fetch(`/api/gallery/files/${file.id}/trash`, { method: "POST" }));
        closeFileDialog();
        setStatus(dom.globalStatus, "File spostato nel cestino.", true);
        await Promise.all([loadOverview(true, false), loadGalleryFiles()]);
    } catch (error) {
        setStatus(dom.fileDialogStatus, error.message);
    } finally {
        dom.trashFileButton.disabled = false;
    }
}

async function changeCharacterScore(characterId, delta) {
    return readJson(await fetch(`/api/characters/${characterId}/score`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ delta })
    }));
}

function populateRankingFranchiseFilter() {
    const current = dom.rankingFilter.value;
    dom.rankingFilter.replaceChildren();
    const all = document.createElement("option");
    all.value = "";
    all.textContent = "Tutte le serie";
    dom.rankingFilter.appendChild(all);
    state.franchises.forEach(franchise => {
        const option = document.createElement("option");
        option.value = franchise.id;
        option.textContent = franchise.name;
        dom.rankingFilter.appendChild(option);
    });
    if ([...dom.rankingFilter.options].some(option => option.value === current)) {
        dom.rankingFilter.value = current;
    }
}

async function loadRanking() {
    if (!state.overview) await loadOverview(true);
    populateRankingFranchiseFilter();
    dom.rankingList.replaceChildren();
    try {
        const params = new URLSearchParams({ limit: "500" });
        if (dom.rankingFilter.value) params.set("franchise_id", dom.rankingFilter.value);
        const data = await readJson(await fetch(`/api/ranking?${params}`));
        if (!data.results.length) {
            const empty = document.createElement("p");
            empty.className = "empty-message";
            empty.textContent = "Nessun personaggio disponibile.";
            dom.rankingList.appendChild(empty);
            return;
        }

        data.results.forEach((character, index) => {
            const row = document.createElement("article");
            row.className = "ranking-row";
            const position = document.createElement("strong");
            position.className = "ranking-position";
            position.textContent = index + 1;
            const info = document.createElement("button");
            info.type = "button";
            info.className = "ranking-character";
            info.innerHTML = `<strong>${escapeHtml(character.name)}</strong><small>${escapeHtml(character.franchise_name)} · ${character.file_count} file</small>`;
            info.addEventListener("click", async () => {
                showView("gallery");
                const franchiseData = await readJson(await fetch(`/api/gallery/franchises/${character.franchise_id}/characters`));
                const fullCharacter = franchiseData.characters.find(item => item.id === character.id) || character;
                openMediaContext({ kind: "character", title: character.name, character: fullCharacter, franchise: franchiseData.franchise });
            });
            const controls = createInlineScore(character);
            row.append(position, info, controls);
            dom.rankingList.appendChild(row);
        });
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

function setBackupButtonsDisabled(disabled) {
    dom.refreshBackupsButton.disabled = disabled;
    dom.createBackupButton.disabled = disabled;
    dom.exportMetadataButton.disabled = disabled;
    dom.openBackupsFolderButton.disabled = disabled;
    dom.backupList.querySelectorAll("button").forEach(button => {
        button.disabled = disabled;
    });
}

function backupReasonLabel(reason) {
    const labels = {
        manuale: "Creato manualmente",
        prima_della_sincronizzazione: "Prima della sincronizzazione",
        prima_dello_svuotamento_del_cestino: "Prima dello svuotamento del cestino",
        prima_del_ripristino: "Copia di sicurezza prima del ripristino"
    };
    return labels[reason] || String(reason || "Backup automatico").replaceAll("_", " ");
}

function renderBackups(data) {
    dom.manualBackupCount.textContent = data.manual_count;
    dom.automaticBackupCount.textContent = data.automatic_count;
    dom.automaticBackupLimit.textContent = data.automatic_limit;
    dom.latestBackupDate.textContent = data.results.length
        ? formatIsoDate(data.results[0].created_at)
        : "Nessun backup";

    dom.backupList.replaceChildren();
    if (!data.results.length) {
        const empty = document.createElement("p");
        empty.className = "empty-message";
        empty.textContent = "Non sono ancora presenti backup.";
        dom.backupList.appendChild(empty);
        return;
    }

    for (const backup of data.results) {
        const row = document.createElement("article");
        row.className = "backup-item";

        const info = document.createElement("div");
        info.className = "backup-item-info";
        const title = document.createElement("strong");
        title.textContent = backup.type === "manual" ? "Backup manuale" : "Backup automatico";
        const meta = document.createElement("span");
        meta.textContent = `${formatIsoDate(backup.created_at)} · ${formatFileSize(backup.database_size)}`;
        const reason = document.createElement("small");
        reason.textContent = backupReasonLabel(backup.reason);
        info.append(title, meta, reason);

        const actions = document.createElement("div");
        actions.className = "backup-item-actions";
        const restore = document.createElement("button");
        restore.type = "button";
        restore.textContent = "Ripristina";
        restore.addEventListener("click", () => restoreSelectedBackup(backup));
        const remove = document.createElement("button");
        remove.type = "button";
        remove.className = "danger-button";
        remove.textContent = "Elimina backup";
        remove.addEventListener("click", () => deleteSelectedBackup(backup));
        actions.append(restore, remove);

        row.append(info, actions);
        dom.backupList.appendChild(row);
    }
}

async function loadBackups() {
    setBackupButtonsDisabled(true);
    setStatus(dom.backupStatus, "Lettura dei backup...");
    try {
        const data = await readJson(await fetch("/api/settings/backups"));
        renderBackups(data);
        setStatus(dom.backupStatus, "");
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
    } finally {
        setBackupButtonsDisabled(false);
    }
}

async function createManualBackup() {
    setBackupButtonsDisabled(true);
    setStatus(dom.backupStatus, "Creazione del backup...");
    try {
        const result = await readJson(await fetch("/api/settings/backups", { method: "POST" }));
        await loadBackups();
        setStatus(dom.backupStatus, `Backup creato: ${result.id}.`, true);
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
    } finally {
        setBackupButtonsDisabled(false);
    }
}

async function exportMetadata() {
    setBackupButtonsDisabled(true);
    setStatus(dom.backupStatus, "Esportazione dei metadati...");
    try {
        const result = await readJson(await fetch("/api/settings/backups/export", { method: "POST" }));
        const link = document.createElement("a");
        link.href = result.download_url;
        link.download = result.filename;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setStatus(dom.backupStatus, `Metadati esportati: ${result.filename}.`, true);
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
    } finally {
        setBackupButtonsDisabled(false);
    }
}

async function openBackupsFolderFromUi() {
    try {
        await readJson(await fetch("/api/settings/backups/open", { method: "POST" }));
        setStatus(dom.backupStatus, "Cartella dei backup aperta.", true);
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
    }
}

async function restoreSelectedBackup(backup) {
    const confirmation = window.prompt(
        `Ripristinare il backup del ${formatIsoDate(backup.created_at)}?\n\nIl database e config.json attuali saranno sostituiti. Prima del ripristino verrà creato un backup automatico.\n\nScrivi RIPRISTINA per confermare.`
    );
    if (confirmation === null) return;
    if (confirmation !== "RIPRISTINA") {
        setStatus(dom.backupStatus, "Conferma non valida: il backup non è stato ripristinato.");
        return;
    }

    setBackupButtonsDisabled(true);
    setStatus(dom.backupStatus, "Ripristino del backup...");
    try {
        const result = await readJson(await fetch(`/api/settings/backups/${encodeURIComponent(backup.id)}/restore`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ confirmation })
        }));
        window.alert(`${result.message}\n\nCopia di sicurezza creata: ${result.safety_backup}`);
        window.location.reload();
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
        setBackupButtonsDisabled(false);
    }
}

async function deleteSelectedBackup(backup) {
    const confirmed = window.confirm(
        `Eliminare questo backup del ${formatIsoDate(backup.created_at)}?\n\nIl database attualmente in uso non verrà modificato.`
    );
    if (!confirmed) return;

    setBackupButtonsDisabled(true);
    try {
        await readJson(await fetch(`/api/settings/backups/${encodeURIComponent(backup.id)}`, { method: "DELETE" }));
        await loadBackups();
        setStatus(dom.backupStatus, "Backup eliminato.", true);
    } catch (error) {
        setStatus(dom.backupStatus, error.message);
    } finally {
        setBackupButtonsDisabled(false);
    }
}

function setCacheButtonsDisabled(disabled) {
    dom.refreshCacheStatsButton.disabled = disabled;
    dom.cleanCacheButton.disabled = disabled;
    dom.regenerateThumbnailsButton.disabled = disabled;
    dom.clearCacheButton.disabled = disabled;
}

function renderCacheStats(data) {
    dom.cacheSize.textContent = formatFileSize(data.size);
    dom.cacheFiles.textContent = data.files;
    dom.cacheStaticCount.textContent = data.static_thumbnails;
    dom.cachePreviewCount.textContent = data.animated_previews;
    dom.ffmpegStatus.textContent = data.ffmpeg_available
        ? "Disponibile: anteprime video attive"
        : "Non disponibile: anteprime video statiche";
}

async function loadCacheStats() {
    setCacheButtonsDisabled(true);
    setStatus(dom.cacheStatus, "Lettura della cache...");
    try {
        const data = await readJson(await fetch("/api/settings/cache"));
        renderCacheStats(data);
        setStatus(dom.cacheStatus, "");
    } catch (error) {
        setStatus(dom.cacheStatus, error.message);
    } finally {
        setCacheButtonsDisabled(false);
    }
}

async function cleanThumbnailCache() {
    setCacheButtonsDisabled(true);
    setStatus(dom.cacheStatus, "Pulizia della cache inutilizzata...");
    try {
        const data = await readJson(await fetch("/api/settings/cache/cleanup", { method: "POST" }));
        renderCacheStats(data);
        setStatus(
            dom.cacheStatus,
            `Pulizia completata: ${data.removed} file rimossi, ${formatFileSize(data.freed)} liberati.`,
            true
        );
    } catch (error) {
        setStatus(dom.cacheStatus, error.message);
    } finally {
        setCacheButtonsDisabled(false);
    }
}

async function regenerateThumbnails() {
    const confirmed = window.confirm(
        "Rigenerare tutte le miniature e le anteprime animate? L'operazione può richiedere tempo su archivi grandi."
    );
    if (!confirmed) return;
    setCacheButtonsDisabled(true);
    setStatus(dom.cacheStatus, "Rigenerazione delle miniature in corso...");
    try {
        const data = await readJson(await fetch("/api/settings/cache/regenerate", { method: "POST" }));
        renderCacheStats(data);
        const errorText = data.errors.length ? ` · ${data.errors.length} errori` : "";
        setStatus(
            dom.cacheStatus,
            `Rigenerate ${data.generated} miniature e ${data.animated_previews_generated} anteprime animate${errorText}.`,
            data.errors.length === 0
        );
        await loadOverview(true, false);
        if (!dom.todoView.hidden) await loadTodoFiles();
        if (!dom.trashView.hidden) await loadTrashItems();
        if (!dom.galleryView.hidden && state.mediaContext) await loadGalleryFiles();
    } catch (error) {
        setStatus(dom.cacheStatus, error.message);
    } finally {
        setCacheButtonsDisabled(false);
    }
}

async function clearThumbnailCache() {
    const confirmed = window.confirm(
        "Svuotare tutta la cache delle miniature? Gli originali non verranno modificati e le anteprime saranno ricreate quando servono."
    );
    if (!confirmed) return;
    setCacheButtonsDisabled(true);
    setStatus(dom.cacheStatus, "Svuotamento della cache...");
    try {
        const data = await readJson(await fetch("/api/settings/cache", { method: "DELETE" }));
        renderCacheStats(data);
        setStatus(
            dom.cacheStatus,
            `Cache svuotata: ${data.removed} file rimossi, ${formatFileSize(data.freed)} liberati.`,
            true
        );
    } catch (error) {
        setStatus(dom.cacheStatus, error.message);
    } finally {
        setCacheButtonsDisabled(false);
    }
}

async function synchronizeArchive() {
    dom.archiveSyncButton.disabled = true;
    setStatus(dom.globalStatus, "Sincronizzazione in corso...");
    try {
        const result = await readJson(await fetch("/api/archive/sync", { method: "POST" }));
        setStatus(
            dom.globalStatus,
            `Sincronizzazione completata: ${result.added} nuovi, ${result.updated} aggiornati, ${result.moved} spostati, ${result.removed} rimossi. Backup: ${result.automatic_backup}.`,
            true
        );
        await loadOverview(true, false);
        if (!dom.settingsView.hidden) await loadBackups();
        if (!dom.todoView.hidden) await loadTodoFiles();
        if (!dom.trashView.hidden) await loadTrashItems();
        if (!dom.rankingView.hidden) await loadRanking();
        if (!dom.galleryView.hidden) {
            if (state.mediaContext) await loadGalleryFiles();
            else if (state.currentFranchise) await openFranchise(state.currentFranchise.franchise.id);
            else renderOverview();
        }
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    } finally {
        dom.archiveSyncButton.disabled = false;
    }
}

async function syncFolders() {
    dom.folderSyncButton.disabled = true;
    setStatus(dom.globalStatus, "Lettura delle cartelle...");
    try {
        const result = await readJson(await fetch("/api/characters/sync", { method: "POST" }));
        setStatus(dom.globalStatus, `Rilevate ${result.franchises} serie e ${result.characters} personaggi.`, true);
        await loadOverview(true, false);
        if (!dom.galleryView.hidden) {
            if (state.mediaContext) await loadGalleryFiles();
            else if (state.currentFranchise) await openFranchise(state.currentFranchise.franchise.id);
            else renderOverview();
        }
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    } finally {
        dom.folderSyncButton.disabled = false;
    }
}

// Navigazione principale.
dom.navButtons.forEach(button => button.addEventListener("click", () => showView(button.dataset.view)));
dom.backToOverview.addEventListener("click", renderOverview);

dom.globalSearch.addEventListener("input", () => debounce("global-search", runGlobalSearch));
document.addEventListener("click", event => {
    if (!dom.globalSearchResults.contains(event.target) && event.target !== dom.globalSearch) {
        dom.globalSearchResults.replaceChildren();
    }
});

dom.mediaFilterForm.addEventListener("submit", event => {
    event.preventDefault();
    state.mediaPage = 1;
    loadGalleryFiles();
});
dom.clearMediaFilters.addEventListener("click", () => {
    resetMediaFilters();
    loadGalleryFiles();
});

dom.characterScoreMinus.addEventListener("click", async () => {
    if (!state.mediaContext?.character) return;
    const result = await changeCharacterScore(state.mediaContext.character.id, -1);
    state.mediaContext.character.score = result.score;
    dom.characterScoreValue.textContent = result.score;
});
dom.characterScorePlus.addEventListener("click", async () => {
    if (!state.mediaContext?.character) return;
    const result = await changeCharacterScore(state.mediaContext.character.id, 1);
    state.mediaContext.character.score = result.score;
    dom.characterScoreValue.textContent = result.score;
});

// New e organizzazione.
dom.refreshTodoButton.addEventListener("click", loadTodoFiles);
dom.refreshTrashButton.addEventListener("click", () => loadTrashItems());
dom.emptyTrashButton.addEventListener("click", emptyTrashFromUi);
dom.closeOrganizeDialog.addEventListener("click", closeOrganizer);
dom.cancelOrganize.addEventListener("click", closeOrganizer);
dom.organizeAiCheckbox.addEventListener("change", updateDestinationPreview);
dom.organizeCharacterSearch.addEventListener("input", () => debounce("organize-search", () => {
    searchCharacterNames(
        dom.organizeCharacterSearch.value,
        dom.organizeSearchResults,
        state.organizeCharacters,
        addOrganizeCharacter,
        name => openCreateCharacterDialog(name, "organize")
    );
}));
dom.openCreateCharacter.addEventListener("click", () => openCreateCharacterDialog(dom.organizeCharacterSearch.value, "organize"));
dom.organizeForm.addEventListener("submit", event => {
    event.preventDefault();
    submitOrganization(false);
});

// Creazione di serie/personaggi.
dom.closeCreateCharacter.addEventListener("click", () => dom.createCharacterDialog.close());
dom.cancelCreateCharacter.addEventListener("click", () => dom.createCharacterDialog.close());
dom.franchiseSelect.addEventListener("change", updateNewFranchiseVisibility);
dom.newFranchiseName.addEventListener("input", () => {
    if (!state.codeEditedManually) {
        dom.newFranchiseCode.value = deriveFranchiseCode(dom.newFranchiseName.value);
    }
});
dom.newFranchiseCode.addEventListener("input", () => {
    dom.newFranchiseCode.value = dom.newFranchiseCode.value.replace(/[^a-z0-9]/gi, "").toUpperCase();
    state.codeEditedManually = dom.newFranchiseCode.value.trim().length > 0;
});
dom.createCharacterForm.addEventListener("submit", event => {
    event.preventDefault();
    createCharacterFromForm();
});

// Finestra dei metadati.
dom.closeFileDialog.addEventListener("click", closeFileDialog);
dom.cancelFileEdit.addEventListener("click", closeFileDialog);
dom.revealFileButton.addEventListener("click", revealActiveFile);
dom.trashFileButton.addEventListener("click", trashActiveGalleryFile);
dom.editCharacterSearch.addEventListener("input", () => debounce("edit-search", () => {
    searchCharacterNames(
        dom.editCharacterSearch.value,
        dom.editSearchResults,
        state.editCharacters,
        addEditCharacter,
        name => openCreateCharacterDialog(name, "edit")
    );
}));
dom.fileEditForm.addEventListener("submit", event => {
    event.preventDefault();
    saveFileMetadata();
});

// Classifica e sincronizzazione.
dom.rankingFilter.addEventListener("change", loadRanking);
dom.archiveSyncButton.addEventListener("click", synchronizeArchive);
dom.folderSyncButton.addEventListener("click", syncFolders);
dom.refreshBackupsButton.addEventListener("click", loadBackups);
dom.createBackupButton.addEventListener("click", createManualBackup);
dom.exportMetadataButton.addEventListener("click", exportMetadata);
dom.openBackupsFolderButton.addEventListener("click", openBackupsFolderFromUi);
dom.refreshCacheStatsButton.addEventListener("click", loadCacheStats);
dom.cleanCacheButton.addEventListener("click", cleanThumbnailCache);
dom.regenerateThumbnailsButton.addEventListener("click", regenerateThumbnails);
dom.clearCacheButton.addEventListener("click", clearThumbnailCache);

loadOverview(true);
