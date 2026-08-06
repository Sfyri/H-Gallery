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
    characterHeadingActions: byId("character-heading-actions"),
    characterScoreBox: byId("character-score-box"),
    characterScoreMinus: byId("character-score-minus"),
    characterScorePlus: byId("character-score-plus"),
    characterScoreValue: byId("character-score-value"),
    manageCharacterAliases: byId("manage-character-aliases"),
    mediaFilterForm: byId("media-filter-form"),
    mediaSearch: byId("media-search"),
    mediaTypeFilter: byId("media-type-filter"),
    mediaAiFilter: byId("media-ai-filter"),
    mediaTagFilter: byId("media-tag-filter"),
    mediaTagSuggestions: byId("media-tag-suggestions"),
    mediaSort: byId("media-sort"),
    clearMediaFilters: byId("clear-media-filters"),
    mediaResultSummary: byId("media-result-summary"),
    galleryMediaGrid: byId("gallery-media-grid"),
    pagination: byId("pagination"),
    storySection: byId("story-section"),
    storyResultSummary: byId("story-result-summary"),
    storyGrid: byId("story-grid"),
    gallerySelectionToolbar: byId("gallery-selection-toolbar"),
    gallerySelectionCount: byId("gallery-selection-count"),
    selectAllGalleryButton: byId("select-all-gallery"),
    clearGallerySelectionButton: byId("clear-gallery-selection"),
    createStoryFromGalleryButton: byId("create-story-from-gallery"),

    todoFolderPath: byId("todo-folder-path"),
    todoFileCount: byId("todo-file-count"),
    todoMediaGrid: byId("todo-media-grid"),
    refreshTodoButton: byId("refresh-todo-button"),
    todoSelectionToolbar: byId("todo-selection-toolbar"),
    todoSelectionCount: byId("todo-selection-count"),
    selectAllTodoButton: byId("select-all-todo"),
    clearTodoSelectionButton: byId("clear-todo-selection"),
    organizeSelectedTodoButton: byId("organize-selected-todo"),
    createStoryFromNewButton: byId("create-story-from-new"),
    trashSelectedTodoButton: byId("trash-selected-todo"),

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
    organizeDialogTitle: byId("organize-dialog-title"),
    dialogFilename: byId("dialog-filename"),
    dialogPreview: byId("dialog-preview"),
    organizeStatus: byId("organize-status"),
    organizeCharacterSearch: byId("organize-character-search"),
    organizeSearchResults: byId("organize-search-results"),
    organizeSelectedCharacters: byId("organize-selected-characters"),
    organizeTagsInput: byId("organize-tags-input"),
    organizeTagSuggestions: byId("organize-tag-suggestions"),
    organizeArtistsInput: byId("organize-artists-input"),
    organizeArtistSuggestions: byId("organize-artist-suggestions"),
    organizeAiCheckbox: byId("organize-ai-checkbox"),
    organizeKeepDuplicatesRow: byId("organize-keep-duplicates-row"),
    organizeKeepDuplicatesCheckbox: byId("organize-keep-duplicates-checkbox"),
    openCreateCharacter: byId("open-create-character"),

    createCharacterDialog: byId("create-character-dialog"),
    createCharacterForm: byId("create-character-form"),
    closeCreateCharacter: byId("close-create-character"),
    cancelCreateCharacter: byId("cancel-create-character"),
    submitCreateCharacter: byId("submit-create-character"),
    newCharacterName: byId("new-character-name"),
    newCharacterAliases: byId("new-character-aliases"),
    franchiseSelect: byId("franchise-select"),
    newFranchiseFields: byId("new-franchise-fields"),
    newFranchiseName: byId("new-franchise-name"),
    newFranchiseCode: byId("new-franchise-code"),
    createCharacterStatus: byId("create-character-status"),

    fileDialog: byId("file-dialog"),
    fileEditForm: byId("file-edit-form"),
    fileDialogTitle: byId("file-dialog-title"),
    filePreviousButton: byId("file-previous-button"),
    fileNextButton: byId("file-next-button"),
    fileNavigationIndicator: byId("file-navigation-indicator"),
    fileDialogPreview: byId("file-dialog-preview"),
    fileProperties: byId("file-properties"),
    editCharacterSearch: byId("edit-character-search"),
    editSearchResults: byId("edit-search-results"),
    editSelectedCharacters: byId("edit-selected-characters"),
    editTagsInput: byId("edit-tags-input"),
    editTagSuggestions: byId("edit-tag-suggestions"),
    editArtistsInput: byId("edit-artists-input"),
    editArtistSuggestions: byId("edit-artist-suggestions"),
    editAiCheckbox: byId("edit-ai-checkbox"),
    fileDialogStatus: byId("file-dialog-status"),
    closeFileDialog: byId("close-file-dialog"),
    cancelFileEdit: byId("cancel-file-edit"),
    saveFileEdit: byId("save-file-edit"),
    revealFileButton: byId("reveal-file-button"),
    trashFileButton: byId("trash-file-button"),

    characterAliasDialog: byId("character-alias-dialog"),
    characterAliasForm: byId("character-alias-form"),
    characterAliasTitle: byId("character-alias-title"),
    characterNameInput: byId("character-name-input"),
    characterAliasInput: byId("character-alias-input"),
    characterAliasStatus: byId("character-alias-status"),
    closeCharacterAliasDialog: byId("close-character-alias-dialog"),
    cancelCharacterAlias: byId("cancel-character-alias"),
    saveCharacterAlias: byId("save-character-alias"),

    storyDialog: byId("story-dialog"),
    storyForm: byId("story-form"),
    storyDialogTitle: byId("story-dialog-title"),
    storyDialogSubtitle: byId("story-dialog-subtitle"),
    closeStoryDialog: byId("close-story-dialog"),
    cancelStory: byId("cancel-story"),
    submitStory: byId("submit-story"),
    dissolveStory: byId("dissolve-story"),
    storyTitleInput: byId("story-title-input"),
    storyCharacterSearch: byId("story-character-search"),
    storyCharacterResults: byId("story-character-results"),
    storySelectedCharacters: byId("story-selected-characters"),
    storyCreateCharacter: byId("story-create-character"),
    storyTagsInput: byId("story-tags-input"),
    storyTagSuggestions: byId("story-tag-suggestions"),
    storyArtistsInput: byId("story-artists-input"),
    storyArtistSuggestions: byId("story-artist-suggestions"),
    storyReadingDirection: byId("story-reading-direction"),
    storyAiCheckbox: byId("story-ai-checkbox"),
    storyDuplicatesRow: byId("story-duplicates-row"),
    storyAllowDuplicates: byId("story-allow-duplicates"),
    storyStatus: byId("story-status"),
    storyPagesList: byId("story-pages-list"),
    sortStoryPages: byId("sort-story-pages"),
    reverseStoryPages: byId("reverse-story-pages"),

    storyReaderDialog: byId("story-reader-dialog"),
    storyReaderTitle: byId("story-reader-title"),
    storyReaderMeta: byId("story-reader-meta"),
    storyReaderMode: byId("story-reader-mode"),
    storyReaderContent: byId("story-reader-content"),
    storyReaderNavigation: byId("story-reader-navigation"),
    storyReaderPrevious: byId("story-reader-previous"),
    storyReaderNext: byId("story-reader-next"),
    storyReaderIndicator: byId("story-reader-indicator"),
    closeStoryReader: byId("close-story-reader"),
    editActiveStory: byId("edit-active-story")
};

const NEW_FRANCHISE_VALUE = "__new__";

const state = {
    overview: null,
    franchises: [],
    currentFranchise: null,
    mediaContext: null,
    mediaPage: 1,
    galleryPages: 1,
    galleryTotal: 0,
    galleryLimit: 200,
    trashPage: 1,
    activeTodoFile: null,
    activeTodoFiles: [],
    todoFiles: [],
    todoSelectedPaths: new Set(),
    lastTodoSelectionIndex: null,
    galleryFiles: [],
    gallerySelectedIds: new Set(),
    organizeCharacters: [],
    activeGalleryFile: null,
    activeGalleryFileIndex: -1,
    editCharacters: [],
    creationTarget: "organize",
    franchiseList: [],
    codeEditedManually: false,
    aliasCharacter: null,
    storyMode: null,
    storySourceItems: [],
    storyCharacters: [],
    activeStory: null,
    readerStory: null,
    readerPageIndex: 0,
    draggedStoryPageKey: null,
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

function formatMediaFormat(file) {
    const extension = String(file?.extension || "").replace(/^\./, "").trim();
    if (extension) return extension.toUpperCase();
    return file?.media_type === "video" ? "VIDEO" : "IMMAGINE";
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

function normalizeTagText(value) {
    return String(value || "").trim().replace(/\s+/g, " ");
}

function parseTags(value) {
    const result = [];
    const seen = new Set();
    for (const raw of value.split(",")) {
        const tag = normalizeTagText(raw);
        const key = tag.toLocaleLowerCase("it-IT");
        if (tag && !seen.has(key)) {
            result.push(tag);
            seen.add(key);
        }
    }
    return result;
}

function tagTypeClass(type) {
    const normalized = String(type || "general").toLocaleLowerCase("it-IT");
    if (normalized === "artist") return "tag-artist";
    if (normalized === "system") return "tag-system";
    return "tag-general";
}

function createTagChip(tag, { prefix = "" } = {}) {
    const chip = document.createElement("span");
    chip.className = `tag-chip ${tagTypeClass(tag.type)}`;
    chip.textContent = `${prefix}${tag.name}`;
    chip.title = tag.type === "artist"
        ? "Artista"
        : tag.type === "system" ? "Tag di sistema" : "Tag";
    return chip;
}

function renderTagSummary(container, tags, limit = 5) {
    container.replaceChildren();
    const visibleTags = (tags || []).slice(0, limit);
    visibleTags.forEach(tag => container.appendChild(createTagChip(tag)));
    if ((tags || []).length > limit) {
        const overflow = document.createElement("span");
        overflow.className = "tag-chip tag-overflow";
        overflow.textContent = "…";
        overflow.title = `${tags.length - limit} tag aggiuntivi`;
        container.appendChild(overflow);
    }
}

function getActiveTagToken(input) {
    const cursor = input.selectionStart ?? input.value.length;
    const parts = input.value.split(",");
    const index = input.value.slice(0, cursor).split(",").length - 1;
    return {
        parts,
        index: Math.min(Math.max(index, 0), Math.max(parts.length - 1, 0)),
        query: normalizeTagText(parts[index] || "")
    };
}

function replaceActiveTag(input, tagName) {
    const token = getActiveTagToken(input);
    token.parts[token.index] = normalizeTagText(tagName);

    const unique = [];
    const seen = new Set();
    for (const part of token.parts) {
        const cleaned = normalizeTagText(part);
        const key = cleaned.toLocaleLowerCase("it-IT");
        if (cleaned && !seen.has(key)) {
            unique.push(cleaned);
            seen.add(key);
        }
    }

    input.value = unique.length ? `${unique.join(", ")}, ` : "";
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
}

function setupTagAutocomplete(input, resultsContainer, { excludeAi = false, tagType = null } = {}) {
    if (!input || !resultsContainer) return;

    let suggestions = [];
    let activeIndex = -1;
    let requestSerial = 0;

    const closeSuggestions = () => {
        suggestions = [];
        activeIndex = -1;
        resultsContainer.replaceChildren();
        input.setAttribute("aria-expanded", "false");
    };

    const setActiveIndex = index => {
        if (!suggestions.length) {
            activeIndex = -1;
            return;
        }
        activeIndex = (index + suggestions.length) % suggestions.length;
        [...resultsContainer.querySelectorAll(".tag-suggestion")].forEach((button, buttonIndex) => {
            const active = buttonIndex === activeIndex;
            button.classList.toggle("active", active);
            button.setAttribute("aria-selected", String(active));
            if (active) button.scrollIntoView({ block: "nearest" });
        });
    };

    const selectSuggestion = suggestion => {
        replaceActiveTag(input, suggestion.name);
        closeSuggestions();
    };

    const renderSuggestions = items => {
        resultsContainer.replaceChildren();
        suggestions = items;
        activeIndex = -1;
        input.setAttribute("aria-expanded", String(items.length > 0));

        for (const suggestion of items) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = `tag-suggestion ${tagTypeClass(suggestion.type)}`;
            button.setAttribute("role", "option");
            button.setAttribute("aria-selected", "false");

            const name = document.createElement("strong");
            name.textContent = suggestion.name;
            const count = document.createElement("small");
            count.textContent = `${suggestion.usage_count ?? suggestion.file_count} utilizzi`;
            button.append(name, count);

            button.addEventListener("mousedown", event => event.preventDefault());
            button.addEventListener("click", () => selectSuggestion(suggestion));
            resultsContainer.appendChild(button);
        }
    };

    const loadSuggestions = async () => {
        const token = getActiveTagToken(input);
        const selectedKeys = new Set(
            token.parts
                .filter((_part, index) => index !== token.index)
                .map(part => normalizeTagText(part).toLocaleLowerCase("it-IT"))
                .filter(Boolean)
        );

        const params = new URLSearchParams({ limit: "10" });
        if (token.query) params.set("q", token.query);
        if (tagType) params.set("type", tagType);
        const currentRequest = ++requestSerial;

        try {
            const data = await readJson(await fetch(`/api/gallery/tags?${params.toString()}`));
            if (currentRequest !== requestSerial) return;
            const filtered = data.results.filter(tag => {
                const key = tag.name.toLocaleLowerCase("it-IT");
                return !selectedKeys.has(key) && !(excludeAi && key === "ai");
            });
            renderSuggestions(filtered);
        } catch (error) {
            if (currentRequest === requestSerial) closeSuggestions();
            console.error(error);
        }
    };

    input.setAttribute("aria-autocomplete", "list");
    input.setAttribute("aria-controls", resultsContainer.id);
    input.setAttribute("aria-expanded", "false");
    input.addEventListener("focus", loadSuggestions);
    input.addEventListener("input", () => {
        debounce(`tag-suggestions-${input.id}`, loadSuggestions, 120);
    });
    input.addEventListener("keydown", event => {
        if (event.key === "ArrowDown" && suggestions.length) {
            event.preventDefault();
            setActiveIndex(activeIndex + 1);
        } else if (event.key === "ArrowUp" && suggestions.length) {
            event.preventDefault();
            setActiveIndex(activeIndex <= 0 ? suggestions.length - 1 : activeIndex - 1);
        } else if (event.key === "Enter" && activeIndex >= 0) {
            event.preventDefault();
            selectSuggestion(suggestions[activeIndex]);
        } else if (event.key === "Escape") {
            closeSuggestions();
        }
    });
    input.addEventListener("blur", () => {
        window.setTimeout(() => {
            input.value = parseTags(input.value).join(", ");
            closeSuggestions();
        }, 120);
    });
}

function createMediaElement(file, controls = false) {
    if (controls) {
        if (file.media_type === "image") {
            const image = document.createElement("img");
            image.src = file.media_url;
            image.alt = file.filename || file.name;
            image.loading = "eager";
            image.classList.toggle("transparent-media", Boolean(file.has_transparency));
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
        [summary.franchises, "Serie"],
        [summary.total_files, "File"],
        [summary.images, "Immagini"],
        [summary.videos, "Video"],
        [summary.stories || 0, "Storie"],
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
            subtitle: `${franchise.character_count} personaggi · ${franchise.total_files} File`,
            coverUrl: franchise.cover_url,
            badges: [`${franchise.images} Immagini`, `${franchise.videos} Video`, `${franchise.ai_files} IA`],
            onClick: () => openFranchise(franchise.id)
        }));
    });

    if (!fragment.childNodes.length) {
        const empty = document.createElement("p");
        empty.className = "empty-message";
        empty.textContent = "La galleria non contiene ancora file organizzati.";
        fragment.appendChild(empty);
    }
    dom.franchiseGrid.appendChild(fragment);
}

async function openFranchise(franchiseId) {
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
            subtitle: character.aliases?.length
                ? `${character.total_files} File associati\nAlias: ${character.aliases.join(", ")}`
                : `${character.total_files} File associati`,
            coverUrl: character.cover_url,
            badges: [`${character.images} Immagini`, `${character.videos} Video`, `${character.ai_files} IA`],
            scoreControls: { character },
            onClick: () => openMediaContext({
                kind: "character",
                title: character.name,
                character,
                franchise: data.franchise
            })
        }));
    });

    if (!fragment.childNodes.length) {
        const empty = document.createElement("p");
        empty.className = "empty-message";
        empty.textContent = "Questa serie non contiene file organizzati.";
        fragment.appendChild(empty);
    }
    dom.characterGrid.appendChild(fragment);
}

function openMediaContext(context) {
    state.mediaContext = context;
    state.gallerySelectedIds.clear();
    resetMediaFilters();
    dom.overviewPanel.hidden = true;
    dom.franchisePanel.hidden = true;
    dom.mediaPanel.hidden = false;
    dom.mediaTitle.textContent = context.title;

    if (context.kind === "character") {
        const aliasSuffix = context.character.aliases?.length
            ? ` · Alias: ${context.character.aliases.join(", ")}`
            : "";
        dom.mediaSubtitle.textContent = `${context.franchise.name}${aliasSuffix}`;
        dom.characterHeadingActions.hidden = false;
        dom.characterScoreValue.textContent = context.character.score;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: context.franchise.name, action: () => openFranchise(context.franchise.id) },
            { label: context.character.name }
        ]);
    } else if (context.kind === "multiple") {
        dom.mediaSubtitle.textContent = "File conservati fisicamente nella cartella !Multiple";
        dom.characterHeadingActions.hidden = true;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: context.franchise.name, action: () => openFranchise(context.franchise.id) },
            { label: "!Multiple" }
        ]);
    } else if (context.kind === "crossovers") {
        dom.mediaSubtitle.textContent = "File con personaggi appartenenti a serie differenti";
        dom.characterHeadingActions.hidden = true;
        renderBreadcrumb([
            { label: "Galleria", action: renderOverview },
            { label: "!Crossovers" }
        ]);
    } else if (context.kind === "tag") {
        dom.mediaSubtitle.textContent = `Ricerca per il tag “${context.tag}”`;
        dom.characterHeadingActions.hidden = true;
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

function buildStoryQuery() {
    const params = new URLSearchParams();
    const context = state.mediaContext;
    if (context.kind === "character") params.set("character_id", context.character.id);
    if (context.kind === "multiple") {
        params.set("franchise_id", context.franchise.id);
        params.set("collection", "multiple");
    }
    if (context.kind === "crossovers") params.set("collection", "crossovers");
    if (context.kind === "tag") params.append("tags", context.tag);

    if (dom.mediaAiFilter.value) params.set("ai_generated", dom.mediaAiFilter.value);
    if (dom.mediaSearch.value.trim()) params.set("q", dom.mediaSearch.value.trim());
    parseTags(dom.mediaTagFilter.value).forEach(tag => params.append("tags", tag));
    params.set("limit", "200");
    return params;
}

async function loadGalleryFiles() {
    if (!state.mediaContext) return null;
    dom.galleryMediaGrid.replaceChildren();
    dom.pagination.replaceChildren();
    dom.storyGrid.replaceChildren();
    dom.storySection.hidden = true;
    dom.mediaResultSummary.textContent = "Caricamento...";
    try {
        const [data, storyData] = await Promise.all([
            readJson(await fetch(`/api/gallery/files?${buildGalleryFileQuery()}`)),
            readJson(await fetch(`/api/stories?${buildStoryQuery()}`))
        ]);
        state.galleryFiles = data.files;
        state.mediaPage = data.page;
        state.galleryPages = data.pages;
        state.galleryTotal = data.total;
        state.galleryLimit = data.limit;
        state.gallerySelectedIds = new Set(
            [...state.gallerySelectedIds].filter(id => data.files.some(file => file.id === id))
        );
        dom.mediaResultSummary.textContent = `${data.total} File singoli · Pagina ${data.page} di ${data.pages}`;
        renderStoryCards(dom.mediaTypeFilter.value === "video" ? [] : storyData.stories);
        renderGalleryMediaCards(data.files);
        renderPagination(data.page, data.pages);
        updateGallerySelectionUi();
        return data;
    } catch (error) {
        console.error(error);
        dom.mediaResultSummary.textContent = "Errore";
        setStatus(dom.globalStatus, error.message);
        return null;
    }
}

function renderStoryCards(stories) {
    dom.storyGrid.replaceChildren();
    dom.storySection.hidden = stories.length === 0;
    dom.storyResultSummary.textContent = `${stories.length} ${stories.length === 1 ? "Storia" : "Storie"}`;
    if (!stories.length) return;

    const fragment = document.createDocumentFragment();
    stories.forEach(story => {
        const card = document.createElement("article");
        card.className = "story-card";

        const preview = document.createElement("button");
        preview.type = "button";
        preview.className = "preview-container preview-button";
        if (story.cover_url) {
            const image = document.createElement("img");
            image.src = story.cover_url;
            image.alt = `Copertina di ${story.title}`;
            image.loading = "lazy";
            preview.appendChild(image);
        } else {
            const placeholder = document.createElement("span");
            placeholder.className = "empty-message";
            placeholder.textContent = "Nessuna copertina";
            preview.appendChild(placeholder);
        }
        preview.addEventListener("click", () => openStoryReader(story.id));

        const info = document.createElement("div");
        info.className = "media-info";
        const title = document.createElement("p");
        title.className = "media-name";
        title.textContent = story.title;
        const details = document.createElement("p");
        details.className = "media-details";
        details.innerHTML = `<span>${story.page_count} pagine</span><span>${story.reading_direction === "rtl" ? "← Manga" : "Fumetto →"}</span>`;
        const characters = document.createElement("p");
        characters.className = "card-characters";
        characters.textContent = story.characters.map(character => character.name).join(", ");
        const tags = document.createElement("div");
        tags.className = "card-tags";
        renderTagSummary(tags, story.tags, 5);
        info.append(title, details, characters, tags);

        const actions = document.createElement("div");
        actions.className = "story-card-actions";
        const readButton = document.createElement("button");
        readButton.type = "button";
        readButton.textContent = "Leggi";
        readButton.addEventListener("click", () => openStoryReader(story.id));
        const editButton = document.createElement("button");
        editButton.type = "button";
        editButton.className = "secondary-button";
        editButton.textContent = "Modifica";
        editButton.addEventListener("click", () => openStoryEditor(story.id));
        actions.append(readButton, editButton);
        card.append(preview, info, actions);
        fragment.appendChild(card);
    });
    dom.storyGrid.appendChild(fragment);
}

function updateGallerySelectionUi() {
    const availableIds = new Set(
        state.galleryFiles.filter(file => file.media_type === "image").map(file => file.id)
    );
    state.gallerySelectedIds = new Set(
        [...state.gallerySelectedIds].filter(id => availableIds.has(id))
    );
    const selected = state.gallerySelectedIds.size;
    const available = availableIds.size;
    dom.gallerySelectionToolbar.hidden = available === 0;
    dom.gallerySelectionCount.textContent = `${selected} ${selected === 1 ? "Immagine selezionata" : "Immagini selezionate"}`;
    dom.selectAllGalleryButton.disabled = available === 0 || selected === available;
    dom.clearGallerySelectionButton.disabled = selected === 0;
    dom.createStoryFromGalleryButton.disabled = selected < 2;

    document.querySelectorAll(".gallery-select-checkbox").forEach(checkbox => {
        const fileId = Number(checkbox.dataset.fileId);
        const checked = state.gallerySelectedIds.has(fileId);
        checkbox.checked = checked;
        checkbox.closest(".media-card")?.classList.toggle("selected-card", checked);
    });
}

function createGalleryMediaCard(file) {
    const card = document.createElement("article");
    card.className = "media-card gallery-file-card";

    if (file.media_type === "image") {
        const selectionLabel = document.createElement("label");
        selectionLabel.className = "gallery-selection-toggle";
        selectionLabel.title = `Seleziona ${file.filename}`;
        const checkbox = document.createElement("input");
        checkbox.type = "checkbox";
        checkbox.className = "gallery-select-checkbox";
        checkbox.dataset.fileId = file.id;
        checkbox.checked = state.gallerySelectedIds.has(file.id);
        checkbox.addEventListener("click", event => {
            event.stopPropagation();
            if (checkbox.checked) state.gallerySelectedIds.add(file.id);
            else state.gallerySelectedIds.delete(file.id);
            updateGallerySelectionUi();
        });
        selectionLabel.appendChild(checkbox);
        card.appendChild(selectionLabel);
    }

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
    details.innerHTML = `<span>${formatMediaFormat(file)}</span><span>${formatFileSize(file.size)}</span>`;

    const tags = document.createElement("div");
    tags.className = "card-tags";
    renderTagSummary(tags, file.tags, 5);

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
        empty.textContent = "Nessun file singolo corrisponde ai filtri selezionati.";
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
            const aliasText = character.aliases?.length
                ? `<small>Alias: ${escapeHtml(character.aliases.join(", "))}</small>`
                : "";
            button.innerHTML = `<strong>${escapeHtml(character.name)}</strong><small>${escapeHtml(character.franchise_name)}</small>${aliasText}`;
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

        (data.stories || []).forEach(story => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "floating-result";
            button.innerHTML = `<strong>${escapeHtml(story.title)}</strong><small>Storia · ${story.page_count} pagine</small>`;
            button.addEventListener("click", () => {
                dom.globalSearchResults.replaceChildren();
                openStoryReader(story.id);
            });
            fragment.appendChild(button);
        });

        data.tags.forEach(tag => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = `floating-result ${tagTypeClass(tag.type)}`;
            const tagLabel = tag.type === "artist" ? "Artista" : tag.type === "system" ? "Sistema" : "Tag";
            button.innerHTML = `<strong>#${escapeHtml(tag.name)}</strong><small>${tagLabel} · ${tag.usage_count ?? tag.file_count} utilizzi</small>`;
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

function updateTodoSelectionUi() {
    const availablePaths = new Set(state.todoFiles.map(file => file.relative_path));
    state.todoSelectedPaths = new Set(
        [...state.todoSelectedPaths].filter(path => availablePaths.has(path))
    );

    const selectedCount = state.todoSelectedPaths.size;
    const totalCount = state.todoFiles.length;
    dom.todoSelectionToolbar.hidden = totalCount === 0;
    dom.todoSelectionCount.textContent = `${selectedCount} ${selectedCount === 1 ? "file selezionato" : "file selezionati"}`;
    dom.selectAllTodoButton.disabled = totalCount === 0 || selectedCount === totalCount;
    dom.clearTodoSelectionButton.disabled = selectedCount === 0;
    dom.organizeSelectedTodoButton.disabled = selectedCount === 0;
    const selectedImages = state.todoFiles.filter(
        file => state.todoSelectedPaths.has(file.relative_path) && file.media_type === "image"
    ).length;
    dom.createStoryFromNewButton.disabled = selectedCount < 2 || selectedImages !== selectedCount;
    dom.trashSelectedTodoButton.disabled = selectedCount === 0;

    document.querySelectorAll(".todo-select-checkbox").forEach(checkbox => {
        const selected = state.todoSelectedPaths.has(checkbox.dataset.relativePath);
        checkbox.checked = selected;
        checkbox.closest(".media-card")?.classList.toggle("selected-card", selected);
    });
}

function changeTodoSelection(file, index, checked, useRange = false) {
    if (useRange && state.lastTodoSelectionIndex !== null) {
        const start = Math.min(state.lastTodoSelectionIndex, index);
        const end = Math.max(state.lastTodoSelectionIndex, index);
        state.todoFiles.slice(start, end + 1).forEach(item => {
            if (checked) state.todoSelectedPaths.add(item.relative_path);
            else state.todoSelectedPaths.delete(item.relative_path);
        });
    } else if (checked) {
        state.todoSelectedPaths.add(file.relative_path);
    } else {
        state.todoSelectedPaths.delete(file.relative_path);
    }

    state.lastTodoSelectionIndex = index;
    updateTodoSelectionUi();
}

function selectAllTodoFiles() {
    state.todoFiles.forEach(file => state.todoSelectedPaths.add(file.relative_path));
    state.lastTodoSelectionIndex = state.todoFiles.length ? state.todoFiles.length - 1 : null;
    updateTodoSelectionUi();
}

function clearTodoSelection() {
    state.todoSelectedPaths.clear();
    state.lastTodoSelectionIndex = null;
    updateTodoSelectionUi();
}

function getSelectedTodoFiles() {
    return state.todoFiles.filter(file => state.todoSelectedPaths.has(file.relative_path));
}

function findTodoCard(relativePath) {
    return [...dom.todoMediaGrid.querySelectorAll(".todo-media-card")]
        .find(card => card.dataset.todoPath === relativePath) || null;
}

function captureTodoContinuation(removedPaths) {
    const removed = new Set(removedPaths);
    const removedIndexes = state.todoFiles
        .map((file, index) => removed.has(file.relative_path) ? index : -1)
        .filter(index => index >= 0);

    if (!removedIndexes.length) return null;

    const firstRemovedIndex = Math.min(...removedIndexes);
    const lastRemovedIndex = Math.max(...removedIndexes);
    const nextFile = state.todoFiles
        .slice(lastRemovedIndex + 1)
        .find(file => !removed.has(file.relative_path));
    const previousFile = [...state.todoFiles.slice(0, firstRemovedIndex)]
        .reverse()
        .find(file => !removed.has(file.relative_path));
    const targetFile = nextFile || previousFile;

    if (!targetFile) return null;

    const stickyTop = document.querySelector(".topbar")?.getBoundingClientRect().bottom || 0;
    const visibleRemovedCards = removedIndexes
        .map(index => findTodoCard(state.todoFiles[index].relative_path))
        .filter(Boolean)
        .map(card => ({ card, rect: card.getBoundingClientRect() }))
        .filter(item => item.rect.bottom > stickyTop && item.rect.top < window.innerHeight)
        .sort((left, right) => Math.abs(left.rect.top - stickyTop) - Math.abs(right.rect.top - stickyTop));

    const targetCard = findTodoCard(targetFile.relative_path);
    const referenceCard = visibleRemovedCards[0]?.card || findTodoCard(state.todoFiles[firstRemovedIndex].relative_path);
    const desiredTop = nextFile
        ? referenceCard?.getBoundingClientRect().top
        : targetCard?.getBoundingClientRect().top;

    return {
        targetPath: targetFile.relative_path,
        desiredTop: Number.isFinite(desiredTop) ? desiredTop : null,
        fallbackScrollY: window.scrollY
    };
}

async function restoreTodoContinuation(continuation) {
    if (!continuation?.targetPath) return;

    await new Promise(resolve => requestAnimationFrame(resolve));
    const card = findTodoCard(continuation.targetPath);
    if (!card) {
        window.scrollTo({ top: continuation.fallbackScrollY || 0, behavior: "auto" });
        return;
    }

    if (Number.isFinite(continuation.desiredTop)) {
        const delta = card.getBoundingClientRect().top - continuation.desiredTop;
        if (Math.abs(delta) > 0.5) window.scrollBy({ top: delta, behavior: "auto" });
        return;
    }

    card.scrollIntoView({ block: "nearest", behavior: "auto" });
}

async function loadTodoFiles(continuation = null) {
    const preservePosition = Boolean(continuation?.targetPath);
    dom.todoFileCount.textContent = "Caricamento...";
    if (!preservePosition) dom.todoMediaGrid.replaceChildren();
    try {
        const data = await readJson(await fetch("/api/todo/files"));
        state.todoFiles = data.files;
        dom.todoFileCount.textContent = `${data.total_files} File da sistemare`;
        dom.todoFolderPath.textContent = "File in attesa di organizzazione";
        dom.todoBadge.textContent = data.total_files;

        if (data.files.length === 0) {
            state.todoSelectedPaths.clear();
            state.lastTodoSelectionIndex = null;
            updateTodoSelectionUi();
            const empty = document.createElement("p");
            empty.className = "empty-message";
            empty.textContent = "New non contiene immagini o video.";
            dom.todoMediaGrid.replaceChildren(empty);
            return;
        }

        const fragment = document.createDocumentFragment();
        data.files.forEach((file, index) => {
            const card = document.createElement("article");
            card.className = "media-card todo-media-card";
            card.dataset.todoPath = file.relative_path;

            const selectionLabel = document.createElement("label");
            selectionLabel.className = "todo-selection-toggle";
            selectionLabel.title = `Seleziona ${file.name}`;
            const selectionCheckbox = document.createElement("input");
            selectionCheckbox.type = "checkbox";
            selectionCheckbox.className = "todo-select-checkbox";
            selectionCheckbox.dataset.relativePath = file.relative_path;
            selectionCheckbox.checked = state.todoSelectedPaths.has(file.relative_path);
            selectionCheckbox.setAttribute("aria-label", `Seleziona ${file.name}`);
            selectionCheckbox.addEventListener("click", event => {
                event.stopPropagation();
                changeTodoSelection(file, index, selectionCheckbox.checked, event.shiftKey);
            });
            const selectionMark = document.createElement("span");
            selectionMark.setAttribute("aria-hidden", "true");
            selectionLabel.append(selectionCheckbox, selectionMark);

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
            details.innerHTML = `<span>${formatMediaFormat(file)}</span><span>${formatFileSize(file.size)}</span>`;
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
            card.append(selectionLabel, preview, info);
            fragment.appendChild(card);
        });
        dom.todoMediaGrid.replaceChildren(fragment);
        updateTodoSelectionUi();
        await restoreTodoContinuation(continuation);
    } catch (error) {
        console.error(error);
        state.todoFiles = [];
        dom.todoMediaGrid.replaceChildren();
        dom.todoFileCount.textContent = "Errore";
        updateTodoSelectionUi();
        setStatus(dom.globalStatus, error.message);
    }
}

async function trashTodoFile(file) {
    try {
        await readJson(await fetch("/api/todo/trash", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ relative_path: file.relative_path })
        }));
        const continuation = captureTodoContinuation([file.relative_path]);
        await Promise.all([loadTodoFiles(continuation), loadOverview(true, false)]);
        setStatus(dom.globalStatus, "File spostato nel cestino.", true);
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

async function trashSelectedTodoFiles() {
    const files = getSelectedTodoFiles();
    if (!files.length) return;

    dom.trashSelectedTodoButton.disabled = true;
    const failedPaths = new Set();
    const movedPaths = [];
    let movedCount = 0;

    for (const file of files) {
        try {
            await readJson(await fetch("/api/todo/trash", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ relative_path: file.relative_path })
            }));
            movedPaths.push(file.relative_path);
            movedCount += 1;
        } catch (error) {
            console.error(error);
            failedPaths.add(file.relative_path);
        }
    }

    state.todoSelectedPaths = failedPaths;
    const continuation = captureTodoContinuation(movedPaths);
    await Promise.all([loadTodoFiles(continuation), loadOverview(true, false)]);

    const failedCount = failedPaths.size;
    const message = failedCount
        ? `${movedCount} file spostati nel cestino; ${failedCount} non elaborati.`
        : `${movedCount} file spostati nel cestino.`;
    setStatus(dom.globalStatus, message, movedCount > 0);
    dom.trashSelectedTodoButton.disabled = false;
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
        dom.trashSummary.textContent = `${data.total} File · ${formatFileSize(data.total_size)}`;
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
    details.innerHTML = `<span>${formatMediaFormat(item)}</span><span>${formatFileSize(item.size)}</span>`;

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
    renderTagSummary(tags, item.tags, 5);

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
            if (character.aliases?.length) {
                const aliases = document.createElement("small");
                aliases.className = "search-result-aliases";
                aliases.textContent = `Alias: ${character.aliases.join(", ")}`;
                button.appendChild(aliases);
            }
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

function renderOrganizerPreview(files) {
    dom.dialogPreview.replaceChildren();
    dom.dialogPreview.classList.toggle("bulk-dialog-preview", files.length > 1);

    if (files.length === 1) {
        dom.dialogPreview.appendChild(createMediaElement(files[0], true));
        return;
    }

    files.slice(0, 6).forEach(file => {
        const preview = document.createElement("div");
        preview.className = "bulk-preview-item";
        preview.appendChild(createMediaElement(file));
        dom.dialogPreview.appendChild(preview);
    });

    if (files.length > 6) {
        const remaining = document.createElement("div");
        remaining.className = "bulk-preview-more";
        remaining.textContent = `+${files.length - 6}`;
        dom.dialogPreview.appendChild(remaining);
    }
}

function openOrganizer(fileOrFiles) {
    const files = Array.isArray(fileOrFiles) ? fileOrFiles : [fileOrFiles];
    if (!files.length) return;

    state.activeTodoFiles = files;
    state.activeTodoFile = files[0];
    state.organizeCharacters = [];

    const isBatch = files.length > 1;
    dom.organizeDialogTitle.textContent = isBatch
        ? `Organizza ${files.length} file`
        : "Organizza file";
    dom.dialogFilename.textContent = isBatch
        ? "I personaggi, i tag e lo stato IA verranno applicati a tutti i file selezionati."
        : files[0].relative_path;
    renderOrganizerPreview(files);

    dom.organizeCharacterSearch.value = "";
    dom.organizeSearchResults.replaceChildren();
    dom.organizeTagsInput.value = "";
    dom.organizeTagSuggestions.replaceChildren();
    dom.organizeArtistsInput.value = "";
    dom.organizeArtistSuggestions.replaceChildren();
    dom.organizeAiCheckbox.checked = false;
    dom.organizeKeepDuplicatesRow.hidden = !isBatch;
    dom.organizeKeepDuplicatesCheckbox.checked = false;
    dom.submitOrganize.textContent = isBatch
        ? `Organizza ${files.length} file`
        : "Rinomina e sposta";
    setStatus(dom.organizeStatus, "");
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
    dom.organizeDialog.showModal();
    dom.organizeCharacterSearch.focus();
}

function closeOrganizer() {
    dom.organizeDialog.close();
    dom.dialogPreview.classList.remove("bulk-dialog-preview");
    state.activeTodoFile = null;
    state.activeTodoFiles = [];
}

function addOrganizeCharacter(character) {
    if (!state.organizeCharacters.some(item => item.id === character.id)) {
        state.organizeCharacters.push(character);
    }
    dom.organizeCharacterSearch.value = "";
    dom.organizeSearchResults.replaceChildren();
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
}

function removeOrganizeCharacter(characterId) {
    state.organizeCharacters = state.organizeCharacters.filter(item => item.id !== characterId);
    renderSelectedCharacters(dom.organizeSelectedCharacters, state.organizeCharacters, removeOrganizeCharacter);
}

function buildBatchResultMessage(result) {
    const parts = [`${result.organized_count} organizzati`];
    if (result.duplicate_count) parts.push(`${result.duplicate_count} duplicati ignorati`);
    if (result.error_count) parts.push(`${result.error_count} non elaborati`);
    return `${parts.join(" · ")}.`;
}

async function submitBatchOrganization() {
    const files = state.activeTodoFiles;
    const tags = parseTags(dom.organizeTagsInput.value);
    const artists = parseTags(dom.organizeArtistsInput.value);
    const aiGenerated = dom.organizeAiCheckbox.checked;
    const allowDuplicates = dom.organizeKeepDuplicatesCheckbox.checked;

    const confirmationLines = [
        `Stai per organizzare ${files.length} file.`,
        `Personaggi: ${state.organizeCharacters.map(character => `${character.franchise_name} / ${character.name}`).join(", ")}`,
        `Tag comuni: ${tags.length ? tags.join(", ") : "nessuno"}`,
        `Artista: ${artists.length ? artists.join(", ") : "nessuno"}`,
        `IA: ${aiGenerated ? "sì" : "no"}`,
        `Duplicati identici: ${allowDuplicates ? "conserva" : "ignora"}`
    ];
    if (!window.confirm(confirmationLines.join("\n\n"))) return;

    const response = await fetch("/api/organize/batch", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
            relative_paths: files.map(file => file.relative_path),
            character_ids: state.organizeCharacters.map(character => character.id),
            tags,
            artists,
            ai_generated: aiGenerated,
            allow_duplicates: allowDuplicates
        })
    });
    const result = await readJson(response);

    const remainingPaths = new Set([
        ...result.duplicates.map(item => item.relative_path),
        ...result.errors.map(item => item.relative_path)
    ]);
    const organizedPaths = result.organized.map(item => item.source_relative_path);
    const continuation = captureTodoContinuation(organizedPaths);
    state.todoSelectedPaths = remainingPaths;

    const message = buildBatchResultMessage(result);
    if (result.organized_count === 0 && (result.duplicate_count || result.error_count)) {
        setStatus(dom.organizeStatus, message);
        updateTodoSelectionUi();
        return;
    }

    closeOrganizer();
    await Promise.all([loadTodoFiles(continuation), loadOverview(true, false)]);
    setStatus(dom.globalStatus, message, result.organized_count > 0 && result.error_count === 0);
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
        if (state.activeTodoFiles.length > 1) {
            await submitBatchOrganization();
            return;
        }

        const response = await fetch("/api/organize", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                relative_path: state.activeTodoFile.relative_path,
                character_ids: state.organizeCharacters.map(character => character.id),
                tags: parseTags(dom.organizeTagsInput.value),
                artists: parseTags(dom.organizeArtistsInput.value),
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
        const continuation = captureTodoContinuation([state.activeTodoFile.relative_path]);
        state.todoSelectedPaths.delete(state.activeTodoFile.relative_path);
        setStatus(dom.globalStatus, `File organizzato: ${result.relative_path}`, true);
        closeOrganizer();
        await Promise.all([loadTodoFiles(continuation), loadOverview(true, false)]);
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
                name: dom.newCharacterName.value.trim(),
                aliases: parseTags(dom.newCharacterAliases.value)
            })
        }));

        dom.createCharacterDialog.close();
        if (state.creationTarget === "edit") addEditCharacter(character);
        else if (state.creationTarget === "story") addStoryCharacter(character);
        else addOrganizeCharacter(character);
        await loadOverview(true, false);
        setStatus(dom.globalStatus, `Creato: ${character.label}`, true);
    } catch (error) {
        setStatus(dom.createCharacterStatus, error.message);
    } finally {
        dom.submitCreateCharacter.disabled = false;
    }
}

async function openCharacterAliasDialog() {
    const character = state.mediaContext?.kind === "character"
        ? state.mediaContext.character
        : null;
    if (!character) return;

    state.aliasCharacter = character;
    dom.characterAliasTitle.textContent = `Modifica ${character.name}`;
    dom.characterNameInput.value = character.name;
    dom.characterAliasInput.value = "";
    setStatus(dom.characterAliasStatus, "Caricamento...");
    dom.characterAliasDialog.showModal();

    try {
        const data = await readJson(await fetch(`/api/characters/${character.id}/aliases`));
        dom.characterNameInput.value = data.name;
        dom.characterAliasInput.value = data.aliases.join(", ");
        setStatus(dom.characterAliasStatus, "");
        dom.characterNameInput.focus();
        dom.characterNameInput.select();
    } catch (error) {
        setStatus(dom.characterAliasStatus, error.message);
    }
}

function closeCharacterAliasDialog() {
    dom.characterAliasDialog.close();
    state.aliasCharacter = null;
}

async function saveCharacterAliases() {
    if (!state.aliasCharacter) return;
    const name = dom.characterNameInput.value.trim();
    if (!name) {
        setStatus(dom.characterAliasStatus, "Inserisci il nome del personaggio.");
        return;
    }

    dom.saveCharacterAlias.disabled = true;
    setStatus(dom.characterAliasStatus, "Salvataggio e rinomina dei file...");
    try {
        const data = await readJson(await fetch(
            `/api/characters/${state.aliasCharacter.id}`,
            {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    name,
                    aliases: parseTags(dom.characterAliasInput.value)
                })
            }
        ));

        Object.assign(state.aliasCharacter, data);
        if (state.mediaContext?.character?.id === data.id) {
            Object.assign(state.mediaContext.character, data);
            state.mediaContext.title = data.name;
            dom.mediaTitle.textContent = data.name;
            const aliasSuffix = data.aliases.length
                ? ` · Alias: ${data.aliases.join(", ")}`
                : "";
            dom.mediaSubtitle.textContent = `${state.mediaContext.franchise.name}${aliasSuffix}`;
            renderBreadcrumb([
                { label: "Galleria", action: renderOverview },
                { label: state.mediaContext.franchise.name, action: () => openFranchise(state.mediaContext.franchise.id) },
                { label: data.name }
            ]);
        }
        if (state.currentFranchise) {
            const current = state.currentFranchise.characters.find(item => item.id === data.id);
            if (current) Object.assign(current, data);
        }

        closeCharacterAliasDialog();
        await Promise.all([loadOverview(true, false), loadGalleryFiles()]);
        if (state.currentFranchise) renderCharacterGrid(state.currentFranchise);
        setStatus(
            dom.globalStatus,
            data.renamed ? `Personaggio rinominato in ${data.name}.` : "Personaggio aggiornato.",
            true
        );
    } catch (error) {
        setStatus(dom.characterAliasStatus, error.message);
    } finally {
        dom.saveCharacterAlias.disabled = false;
    }
}

function updateFileNavigation() {
    const index = state.galleryFiles.findIndex(file => file.id === state.activeGalleryFile?.id);
    state.activeGalleryFileIndex = index;
    const pageTotal = state.galleryFiles.length;
    dom.filePreviousButton.disabled = index < 0 || (index === 0 && state.mediaPage <= 1);
    dom.fileNextButton.disabled = index < 0 || (index >= pageTotal - 1 && state.mediaPage >= state.galleryPages);
    const globalIndex = index >= 0
        ? (state.mediaPage - 1) * state.galleryLimit + index + 1
        : 0;
    dom.fileNavigationIndicator.textContent = index >= 0
        ? `${globalIndex} / ${state.galleryTotal}`
        : "—";
}

function renderFileDialog(file) {
    state.activeGalleryFile = file;
    state.editCharacters = [...file.characters];
    dom.fileDialogTitle.textContent = "Dettagli file";
    dom.fileDialogPreview.replaceChildren(createMediaElement(file, true));
    dom.editCharacterSearch.value = "";
    dom.editSearchResults.replaceChildren();
    dom.editTagsInput.value = file.tags
        .filter(tag => (tag.type || "general") === "general")
        .map(tag => tag.name)
        .join(", ");
    dom.editTagSuggestions.replaceChildren();
    dom.editArtistsInput.value = file.tags
        .filter(tag => tag.type === "artist")
        .map(tag => tag.name)
        .join(", ");
    dom.editArtistSuggestions.replaceChildren();
    dom.editAiCheckbox.checked = file.ai_generated;
    renderSelectedCharacters(dom.editSelectedCharacters, state.editCharacters, removeEditCharacter);
    renderFileProperties(file);
    updateFileNavigation();
}

async function openFileDialog(fileId) {
    const isFirstOpen = !dom.fileDialog.open;
    setStatus(dom.fileDialogStatus, isFirstOpen ? "Caricamento..." : "");
    if (isFirstOpen) dom.fileDialog.showModal();
    try {
        const file = await readJson(await fetch(`/api/gallery/files/${fileId}`));
        renderFileDialog(file);
        setStatus(dom.fileDialogStatus, file.characters.length ? "" : "Questo file non ha personaggi associati.");
    } catch (error) {
        setStatus(dom.fileDialogStatus, error.message);
    }
}

async function navigateFileDialog(offset) {
    if (!state.activeGalleryFile) return;
    const index = state.galleryFiles.findIndex(file => file.id === state.activeGalleryFile.id);
    const next = state.galleryFiles[index + offset];
    if (next) {
        await openFileDialog(next.id);
        return;
    }

    if (offset > 0 && state.mediaPage < state.galleryPages) {
        state.mediaPage += 1;
        const data = await loadGalleryFiles();
        const first = data?.files?.[0];
        if (first) await openFileDialog(first.id);
    } else if (offset < 0 && state.mediaPage > 1) {
        state.mediaPage -= 1;
        const data = await loadGalleryFiles();
        const last = data?.files?.at(-1);
        if (last) await openFileDialog(last.id);
    }
}

function renderFileProperties(file) {
    const pathParts = String(file.relative_path || "").split("/");
    const directory = pathParts.length > 1 ? pathParts.slice(0, -1).join("/") : "—";
    const properties = [
        ["Nome file", file.filename],
        ["Directory", directory],
        ["Formato", formatMediaFormat(file)]
    ];
    if (file.media_type === "image") {
        const resolution = file.width && file.height
            ? `${file.width} × ${file.height} px`
            : "Non disponibile";
        properties.push(["Risoluzione", resolution]);
    }
    properties.push(["Dimensione file", formatFileSize(file.size)]);

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
    state.activeGalleryFileIndex = -1;
    state.editCharacters = [];
    dom.fileNavigationIndicator.textContent = "—";
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
                artists: parseTags(dom.editArtistsInput.value),
                ai_generated: dom.editAiCheckbox.checked
            })
        }));
        renderFileDialog(result);
        setStatus(dom.fileDialogStatus, result.moved ? "Salvato e file spostato." : "Modifiche salvate.", true);
        await Promise.all([loadGalleryFiles(), loadOverview(true, false)]);
        updateFileNavigation();
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


function getSelectedGalleryFiles() {
    return state.galleryFiles.filter(file => state.gallerySelectedIds.has(file.id));
}

function selectAllGalleryImages() {
    state.galleryFiles
        .filter(file => file.media_type === "image")
        .forEach(file => state.gallerySelectedIds.add(file.id));
    updateGallerySelectionUi();
}

function clearGallerySelection() {
    state.gallerySelectedIds.clear();
    updateGallerySelectionUi();
}

function storyItemKey(item) {
    return String(item.id ?? item.relative_path);
}

function storyItemFromTodo(file) {
    return {
        key: file.relative_path,
        relative_path: file.relative_path,
        name: file.name,
        thumbnail_url: file.thumbnail_url,
        media_url: file.media_url,
        media_type: file.media_type,
        has_transparency: Boolean(file.has_transparency),
        ai_generated: false,
        characters: []
    };
}

function storyItemFromGallery(file) {
    return {
        key: String(file.id),
        id: file.id,
        name: file.filename,
        thumbnail_url: file.thumbnail_url,
        media_url: file.media_url,
        media_type: file.media_type,
        has_transparency: Boolean(file.has_transparency),
        ai_generated: file.ai_generated,
        characters: file.characters || []
    };
}

function storyItemFromPage(page) {
    return {
        key: String(page.id),
        id: page.id,
        name: page.filename,
        thumbnail_url: page.thumbnail_url,
        media_url: page.media_url,
        media_type: "image",
        has_transparency: Boolean(page.has_transparency),
        available: page.available !== false,
        ai_generated: page.ai_generated,
        characters: []
    };
}

function inferStoryCharacters(items) {
    const byId = new Map();
    items.forEach(item => (item.characters || []).forEach(character => byId.set(character.id, character)));
    return [...byId.values()];
}

function renderStorySelectedCharacters() {
    renderSelectedCharacters(
        dom.storySelectedCharacters,
        state.storyCharacters,
        removeStoryCharacter
    );
}

function addStoryCharacter(character) {
    if (!state.storyCharacters.some(item => item.id === character.id)) {
        state.storyCharacters.push(character);
    }
    dom.storyCharacterSearch.value = "";
    dom.storyCharacterResults.replaceChildren();
    renderStorySelectedCharacters();
}

function removeStoryCharacter(characterId) {
    state.storyCharacters = state.storyCharacters.filter(item => item.id !== characterId);
    renderStorySelectedCharacters();
}

function renderStoryPages() {
    dom.storyPagesList.replaceChildren();
    const fragment = document.createDocumentFragment();
    state.storySourceItems.forEach((item, index) => {
        const page = document.createElement("article");
        page.className = "story-page-item";
        page.draggable = true;
        page.dataset.key = storyItemKey(item);

        let preview;
        if (item.available === false) {
            preview = document.createElement("div");
            preview.className = "story-page-missing story-page-missing-preview";
            preview.textContent = "Pagina non disponibile";
        } else {
            preview = document.createElement("img");
            preview.src = item.thumbnail_url || item.media_url;
            preview.alt = item.name;
            preview.loading = "lazy";
            preview.classList.toggle("transparent-media", Boolean(item.has_transparency));
        }

        const controls = document.createElement("div");
        controls.className = "story-page-controls";
        const numberLabel = document.createElement("label");
        numberLabel.className = "story-page-number";
        numberLabel.textContent = "Pagina";
        const number = document.createElement("input");
        number.type = "number";
        number.min = "1";
        number.max = String(state.storySourceItems.length);
        number.value = String(index + 1);
        number.dataset.storyPageNumber = storyItemKey(item);
        numberLabel.appendChild(number);

        const coverLabel = document.createElement("label");
        coverLabel.className = "story-page-cover";
        const cover = document.createElement("input");
        cover.type = "radio";
        cover.name = "story-cover";
        cover.value = storyItemKey(item);
        cover.checked = String(state.storyCoverKey) === storyItemKey(item);
        cover.addEventListener("change", () => {
            if (cover.checked) state.storyCoverKey = storyItemKey(item);
        });
        coverLabel.append(cover, document.createTextNode("Copertina"));
        controls.append(numberLabel, coverLabel);

        page.addEventListener("dragstart", () => {
            state.draggedStoryPageKey = storyItemKey(item);
            page.classList.add("dragging");
        });
        page.addEventListener("dragend", () => {
            state.draggedStoryPageKey = null;
            page.classList.remove("dragging");
            document.querySelectorAll(".story-page-item.drag-over").forEach(element => element.classList.remove("drag-over"));
        });
        page.addEventListener("dragover", event => {
            event.preventDefault();
            if (state.draggedStoryPageKey && state.draggedStoryPageKey !== storyItemKey(item)) {
                page.classList.add("drag-over");
            }
        });
        page.addEventListener("dragleave", () => page.classList.remove("drag-over"));
        page.addEventListener("drop", event => {
            event.preventDefault();
            page.classList.remove("drag-over");
            const fromKey = state.draggedStoryPageKey;
            const toKey = storyItemKey(item);
            if (!fromKey || fromKey === toKey) return;
            const fromIndex = state.storySourceItems.findIndex(value => storyItemKey(value) === fromKey);
            const toIndex = state.storySourceItems.findIndex(value => storyItemKey(value) === toKey);
            if (fromIndex < 0 || toIndex < 0) return;
            const [moved] = state.storySourceItems.splice(fromIndex, 1);
            state.storySourceItems.splice(toIndex, 0, moved);
            renderStoryPages();
        });

        page.append(preview, controls);
        fragment.appendChild(page);
    });
    dom.storyPagesList.appendChild(fragment);
}

function sortStoryPagesByNumbers() {
    const values = new Map();
    dom.storyPagesList.querySelectorAll("input[data-story-page-number]").forEach((input, index) => {
        values.set(input.dataset.storyPageNumber, {
            value: Number(input.value) || index + 1,
            index
        });
    });
    state.storySourceItems.sort((a, b) => {
        const av = values.get(storyItemKey(a));
        const bv = values.get(storyItemKey(b));
        return (av?.value ?? 0) - (bv?.value ?? 0) || (av?.index ?? 0) - (bv?.index ?? 0);
    });
    renderStoryPages();
}

function reverseStoryPages() {
    state.storySourceItems.reverse();
    renderStoryPages();
}

function resetStoryDialog() {
    state.storySourceItems = [];
    state.storyCharacters = [];
    state.activeStory = null;
    state.storyCoverKey = null;
    state.storyMode = null;
    dom.storyPagesList.replaceChildren();
    dom.storyCharacterResults.replaceChildren();
    dom.storyTagSuggestions.replaceChildren();
    dom.storyArtistSuggestions.replaceChildren();
    setStatus(dom.storyStatus, "");
}

function openStoryCreator(items, mode) {
    if (items.length < 2 || items.some(item => item.media_type !== "image")) {
        setStatus(dom.globalStatus, "Seleziona almeno due immagini. I video non possono essere pagine di una storia.");
        return;
    }
    state.storyMode = mode;
    state.activeStory = null;
    state.storySourceItems = mode === "new"
        ? items.map(storyItemFromTodo)
        : items.map(storyItemFromGallery);
    state.storyCharacters = mode === "gallery" ? inferStoryCharacters(state.storySourceItems) : [];
    state.storyCoverKey = storyItemKey(state.storySourceItems[0]);

    dom.storyDialogTitle.textContent = "Crea storia";
    dom.storyDialogSubtitle.textContent = `${items.length} immagini selezionate`;
    dom.storyTitleInput.value = "";
    dom.storyCharacterSearch.value = "";
    dom.storyCharacterResults.replaceChildren();
    dom.storyTagsInput.value = "";
    dom.storyArtistsInput.value = "";
    dom.storyReadingDirection.value = "rtl";
    dom.storyAiCheckbox.checked = mode === "gallery" && items.every(item => item.ai_generated);
    dom.storyDuplicatesRow.hidden = mode !== "new";
    dom.storyAllowDuplicates.checked = false;
    dom.dissolveStory.hidden = true;
    dom.submitStory.textContent = "Crea storia";
    setStatus(dom.storyStatus, "");
    renderStorySelectedCharacters();
    renderStoryPages();
    dom.storyDialog.showModal();
    dom.storyTitleInput.focus();
}

async function openStoryEditor(storyId) {
    try {
        const story = await readJson(await fetch(`/api/stories/${storyId}`));
        state.storyMode = "edit";
        state.activeStory = story;
        state.storySourceItems = story.pages.map(storyItemFromPage);
        state.storyCharacters = [...story.characters];
        state.storyCoverKey = String(story.cover_file_id || story.pages[0]?.id || "");

        dom.storyDialogTitle.textContent = `Modifica: ${story.title}`;
        dom.storyDialogSubtitle.textContent = `${story.pages.length} pagine`;
        dom.storyTitleInput.value = story.title;
        dom.storyCharacterSearch.value = "";
        dom.storyCharacterResults.replaceChildren();
        dom.storyTagsInput.value = story.tags.filter(tag => tag.type === "general").map(tag => tag.name).join(", ");
        dom.storyArtistsInput.value = story.tags.filter(tag => tag.type === "artist").map(tag => tag.name).join(", ");
        dom.storyReadingDirection.value = story.reading_direction;
        dom.storyAiCheckbox.checked = story.ai_generated;
        dom.storyDuplicatesRow.hidden = true;
        dom.dissolveStory.hidden = false;
        dom.submitStory.textContent = "Salva storia";
        setStatus(dom.storyStatus, "");
        renderStorySelectedCharacters();
        renderStoryPages();
            dom.storyDialog.showModal();
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

function closeStoryDialog() {
    dom.storyDialog.close();
    resetStoryDialog();
}

function storyCoverIndex() {
    const index = state.storySourceItems.findIndex(item => storyItemKey(item) === String(state.storyCoverKey));
    return Math.max(0, index);
}

async function submitStoryForm(allowDuplicates = false) {
    const title = dom.storyTitleInput.value.trim();
    if (!title) {
        setStatus(dom.storyStatus, "Inserisci il titolo della storia.");
        return;
    }
    if (!state.storyCharacters.length) {
        setStatus(dom.storyStatus, "Seleziona almeno un personaggio.");
        return;
    }
    if (state.storySourceItems.length < 2) {
        setStatus(dom.storyStatus, "Una storia deve avere almeno due pagine.");
        return;
    }

    dom.submitStory.disabled = true;
    setStatus(dom.storyStatus, "Salvataggio della storia...");
    const common = {
        title,
        character_ids: state.storyCharacters.map(character => character.id),
        tags: parseTags(dom.storyTagsInput.value),
        artists: parseTags(dom.storyArtistsInput.value),
        ai_generated: dom.storyAiCheckbox.checked,
        reading_direction: dom.storyReadingDirection.value
    };

    try {
        let response;
        if (state.storyMode === "edit") {
            response = await fetch(`/api/stories/${state.activeStory.id}`, {
                method: "PUT",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    ...common,
                    ordered_file_ids: state.storySourceItems.map(item => item.id),
                    cover_file_id: Number(state.storyCoverKey)
                })
            });
        } else if (state.storyMode === "new") {
            response = await fetch("/api/stories/from-new", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    ...common,
                    relative_paths: state.storySourceItems.map(item => item.relative_path),
                    cover_index: storyCoverIndex(),
                    allow_duplicates: allowDuplicates || dom.storyAllowDuplicates.checked
                })
            });
        } else {
            response = await fetch("/api/stories/from-gallery", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({
                    ...common,
                    file_ids: state.storySourceItems.map(item => item.id),
                    cover_index: storyCoverIndex()
                })
            });
        }

        if (response.status === 409 && state.storyMode === "new") {
            const payload = await response.json();
            const duplicateCount = payload.detail?.duplicates?.length || 1;
            const keep = window.confirm(`${duplicateCount} duplicati identici trovati. Conservarli comunque nella storia?`);
            if (keep) await submitStoryForm(true);
            else setStatus(dom.storyStatus, "Creazione annullata.");
            return;
        }

        const result = await readJson(response);
        closeStoryDialog();
        state.todoSelectedPaths.clear();
        state.gallerySelectedIds.clear();
        await Promise.all([loadTodoFiles(), loadOverview(true, false)]);
        if (state.mediaContext) await loadGalleryFiles();
        setStatus(dom.globalStatus, `Storia salvata: ${result.title}`, true);
    } catch (error) {
        setStatus(dom.storyStatus, error.message);
    } finally {
        dom.submitStory.disabled = false;
    }
}

async function dissolveActiveStory() {
    if (!state.activeStory) return;
    const confirmed = window.confirm(
        `Sciogliere la storia “${state.activeStory.title}”?\n\nLe pagine verranno mantenute e riportate nella galleria normale.`
    );
    if (!confirmed) return;
    dom.dissolveStory.disabled = true;
    try {
        await readJson(await fetch(`/api/stories/${state.activeStory.id}/dissolve`, { method: "DELETE" }));
        closeStoryDialog();
        await Promise.all([loadOverview(true, false), state.mediaContext ? loadGalleryFiles() : Promise.resolve()]);
        setStatus(dom.globalStatus, "Storia sciolta. Le immagini sono tornate nella galleria normale.", true);
    } catch (error) {
        setStatus(dom.storyStatus, error.message);
    } finally {
        dom.dissolveStory.disabled = false;
    }
}

async function openStoryReader(storyId) {
    try {
        const story = await readJson(await fetch(`/api/stories/${storyId}`));
        state.readerStory = story;
        state.readerPageIndex = 0;
        dom.storyReaderTitle.textContent = story.title;
        const missingPages = story.pages.filter(page => page.available === false).length;
        const missingLabel = missingPages ? ` · ${missingPages} non disponibili` : "";
        dom.storyReaderMeta.textContent = `${story.pages.length} pagine${missingLabel} · ${story.characters.map(character => character.name).join(", ")}`;
        dom.storyReaderMode.value = "single";
        renderStoryReader();
        dom.storyReaderDialog.showModal();
    } catch (error) {
        setStatus(dom.globalStatus, error.message);
    }
}

function createMissingStoryPage(pageNumber = null) {
    const placeholder = document.createElement("div");
    placeholder.className = "story-page-missing";
    placeholder.textContent = pageNumber === null
        ? "Nessuna pagina disponibile."
        : `Pagina ${pageNumber} non disponibile.`;
    return placeholder;
}

function renderStoryReader() {
    const story = state.readerStory;
    if (!story) return;
    dom.storyReaderContent.replaceChildren();
    const vertical = dom.storyReaderMode.value === "vertical";
    dom.storyReaderNavigation.hidden = vertical;

    if (!story.pages.length) {
        dom.storyReaderNavigation.hidden = true;
        dom.storyReaderContent.appendChild(createMissingStoryPage());
        return;
    }

    if (vertical) {
        const container = document.createElement("div");
        container.className = "story-reader-vertical";
        story.pages.forEach(page => {
            if (page.available === false) {
                container.appendChild(createMissingStoryPage(page.page_number));
                return;
            }
            const image = document.createElement("img");
            image.src = page.media_url;
            image.alt = `${story.title} — pagina ${page.page_number}`;
            image.loading = "lazy";
            image.classList.toggle("transparent-media", Boolean(page.has_transparency));
            container.appendChild(image);
        });
        dom.storyReaderContent.appendChild(container);
        return;
    }

    state.readerPageIndex = Math.min(Math.max(state.readerPageIndex, 0), story.pages.length - 1);
    const page = story.pages[state.readerPageIndex];
    const container = document.createElement("div");
    container.className = "story-reader-single";
    if (page.available === false) {
        container.appendChild(createMissingStoryPage(page.page_number));
    } else {
        const image = document.createElement("img");
        image.src = page.media_url;
        image.alt = `${story.title} — pagina ${state.readerPageIndex + 1}`;
        image.classList.toggle("transparent-media", Boolean(page.has_transparency));
        container.appendChild(image);
    }
    dom.storyReaderContent.appendChild(container);
    dom.storyReaderIndicator.textContent = `${state.readerPageIndex + 1} / ${story.pages.length}`;
    dom.storyReaderPrevious.disabled = state.readerPageIndex <= 0;
    dom.storyReaderNext.disabled = state.readerPageIndex >= story.pages.length - 1;
}

function changeStoryReaderPage(delta) {
    if (!state.readerStory || dom.storyReaderMode.value !== "single") return;
    state.readerPageIndex += delta;
    renderStoryReader();
}

function closeStoryReader() {
    dom.storyReaderDialog.close();
    state.readerStory = null;
    state.readerPageIndex = 0;
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
dom.selectAllGalleryButton.addEventListener("click", selectAllGalleryImages);
dom.clearGallerySelectionButton.addEventListener("click", clearGallerySelection);
dom.createStoryFromGalleryButton.addEventListener("click", () => openStoryCreator(getSelectedGalleryFiles(), "gallery"));

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
dom.manageCharacterAliases.addEventListener("click", openCharacterAliasDialog);

// New e organizzazione.
dom.refreshTodoButton.addEventListener("click", () => loadTodoFiles());
dom.selectAllTodoButton.addEventListener("click", selectAllTodoFiles);
dom.clearTodoSelectionButton.addEventListener("click", clearTodoSelection);
dom.organizeSelectedTodoButton.addEventListener("click", () => openOrganizer(getSelectedTodoFiles()));
dom.createStoryFromNewButton.addEventListener("click", () => openStoryCreator(getSelectedTodoFiles(), "new"));
dom.trashSelectedTodoButton.addEventListener("click", trashSelectedTodoFiles);
dom.refreshTrashButton.addEventListener("click", () => loadTrashItems());
dom.emptyTrashButton.addEventListener("click", emptyTrashFromUi);
dom.closeOrganizeDialog.addEventListener("click", closeOrganizer);
dom.cancelOrganize.addEventListener("click", closeOrganizer);
const loadOrganizerCharacterSuggestions = () => searchCharacterNames(
    dom.organizeCharacterSearch.value,
    dom.organizeSearchResults,
    state.organizeCharacters,
    addOrganizeCharacter,
    name => openCreateCharacterDialog(name, "organize")
);

dom.organizeCharacterSearch.setAttribute("aria-autocomplete", "list");
dom.organizeCharacterSearch.setAttribute("aria-controls", dom.organizeSearchResults.id);
dom.organizeCharacterSearch.addEventListener("focus", () => {
    if (dom.organizeCharacterSearch.value.trim()) loadOrganizerCharacterSuggestions();
});
dom.organizeCharacterSearch.addEventListener("input", () => {
    debounce("organize-search", loadOrganizerCharacterSuggestions, 120);
});
dom.organizeCharacterSearch.addEventListener("keydown", event => {
    if (event.key === "Escape") dom.organizeSearchResults.replaceChildren();
});
dom.organizeCharacterSearch.addEventListener("blur", () => {
    window.setTimeout(() => dom.organizeSearchResults.replaceChildren(), 120);
});
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
dom.filePreviousButton.addEventListener("click", () => navigateFileDialog(-1));
dom.fileNextButton.addEventListener("click", () => navigateFileDialog(1));
dom.revealFileButton.addEventListener("click", revealActiveFile);
dom.trashFileButton.addEventListener("click", trashActiveGalleryFile);
const loadEditCharacterSuggestions = () => searchCharacterNames(
    dom.editCharacterSearch.value,
    dom.editSearchResults,
    state.editCharacters,
    addEditCharacter,
    name => openCreateCharacterDialog(name, "edit")
);
dom.editCharacterSearch.setAttribute("aria-autocomplete", "list");
dom.editCharacterSearch.setAttribute("aria-controls", dom.editSearchResults.id);
dom.editCharacterSearch.addEventListener("focus", () => {
    if (dom.editCharacterSearch.value.trim()) loadEditCharacterSuggestions();
});
dom.editCharacterSearch.addEventListener("input", () => {
    debounce("edit-search", loadEditCharacterSuggestions, 120);
});
dom.editCharacterSearch.addEventListener("keydown", event => {
    if (event.key === "Escape") dom.editSearchResults.replaceChildren();
});
dom.editCharacterSearch.addEventListener("blur", () => {
    window.setTimeout(() => dom.editSearchResults.replaceChildren(), 120);
});
dom.fileEditForm.addEventListener("submit", event => {
    event.preventDefault();
    saveFileMetadata();
});

// Modifica dei personaggi.
dom.closeCharacterAliasDialog.addEventListener("click", closeCharacterAliasDialog);
dom.cancelCharacterAlias.addEventListener("click", closeCharacterAliasDialog);
dom.characterAliasForm.addEventListener("submit", event => {
    event.preventDefault();
    saveCharacterAliases();
});

// Storie.
dom.closeStoryDialog.addEventListener("click", closeStoryDialog);
dom.cancelStory.addEventListener("click", closeStoryDialog);
dom.storyForm.addEventListener("submit", event => {
    event.preventDefault();
    submitStoryForm(false);
});
const loadStoryCharacterSuggestions = () => searchCharacterNames(
    dom.storyCharacterSearch.value,
    dom.storyCharacterResults,
    state.storyCharacters,
    addStoryCharacter,
    name => openCreateCharacterDialog(name, "story")
);
dom.storyCharacterSearch.setAttribute("aria-autocomplete", "list");
dom.storyCharacterSearch.setAttribute("aria-controls", dom.storyCharacterResults.id);
dom.storyCharacterSearch.addEventListener("focus", () => {
    if (dom.storyCharacterSearch.value.trim()) loadStoryCharacterSuggestions();
});
dom.storyCharacterSearch.addEventListener("input", () => {
    debounce("story-character-search", loadStoryCharacterSuggestions, 120);
});
dom.storyCharacterSearch.addEventListener("keydown", event => {
    if (event.key === "Escape") dom.storyCharacterResults.replaceChildren();
});
dom.storyCharacterSearch.addEventListener("blur", () => {
    window.setTimeout(() => dom.storyCharacterResults.replaceChildren(), 120);
});
dom.storyCreateCharacter.addEventListener("click", () => openCreateCharacterDialog(dom.storyCharacterSearch.value, "story"));
dom.sortStoryPages.addEventListener("click", sortStoryPagesByNumbers);
dom.reverseStoryPages.addEventListener("click", reverseStoryPages);
dom.dissolveStory.addEventListener("click", dissolveActiveStory);

dom.closeStoryReader.addEventListener("click", closeStoryReader);
dom.storyReaderMode.addEventListener("change", renderStoryReader);
dom.storyReaderPrevious.addEventListener("click", () => changeStoryReaderPage(-1));
dom.storyReaderNext.addEventListener("click", () => changeStoryReaderPage(1));
dom.editActiveStory.addEventListener("click", () => {
    const storyId = state.readerStory?.id;
    closeStoryReader();
    if (storyId) openStoryEditor(storyId);
});
document.addEventListener("keydown", event => {
    if (!dom.fileDialog.open || !state.activeGalleryFile) return;
    const activeElement = document.activeElement;
    if (activeElement?.matches("input, textarea, select, [contenteditable='true']")) return;
    if (event.key === "ArrowLeft") {
        event.preventDefault();
        navigateFileDialog(-1);
    } else if (event.key === "ArrowRight") {
        event.preventDefault();
        navigateFileDialog(1);
    }
});
document.addEventListener("keydown", event => {
    if (!dom.storyReaderDialog.open || dom.storyReaderMode.value !== "single" || !state.readerStory) return;
    if (event.key === "Escape") return;
    const rtl = state.readerStory.reading_direction === "rtl";
    if (event.key === "ArrowLeft") {
        event.preventDefault();
        changeStoryReaderPage(rtl ? 1 : -1);
    } else if (event.key === "ArrowRight") {
        event.preventDefault();
        changeStoryReaderPage(rtl ? -1 : 1);
    }
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

setupTagAutocomplete(dom.mediaTagFilter, dom.mediaTagSuggestions);
setupTagAutocomplete(dom.organizeTagsInput, dom.organizeTagSuggestions, { excludeAi: true, tagType: "general" });
setupTagAutocomplete(dom.organizeArtistsInput, dom.organizeArtistSuggestions, { excludeAi: true, tagType: "artist" });
setupTagAutocomplete(dom.editTagsInput, dom.editTagSuggestions, { excludeAi: true, tagType: "general" });
setupTagAutocomplete(dom.editArtistsInput, dom.editArtistSuggestions, { excludeAi: true, tagType: "artist" });
setupTagAutocomplete(dom.storyTagsInput, dom.storyTagSuggestions, { excludeAi: true, tagType: "general" });
setupTagAutocomplete(dom.storyArtistsInput, dom.storyArtistSuggestions, { excludeAi: true, tagType: "artist" });

loadOverview(true);
