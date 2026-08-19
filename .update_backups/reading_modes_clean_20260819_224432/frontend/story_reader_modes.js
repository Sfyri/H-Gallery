"use strict";

(() => {
    /*
     * M9.2.4 - reader Windows
     *
     * L'ordine canonico di una storia e' esclusivamente story.pages / page_number.
     * Normal e Manga cambiano solo il verso con cui l'utente naviga.
     * reading_direction non viene letto, mostrato o inviato dal frontend.
     *
     * app.js M9.2.2 contiene ancora alcuni accessi al vecchio controllo DOM.
     * Questo shim evita errori nelle funzioni legacy che aprono il dialog finche'
     * tali funzioni non vengono eliminate dal sorgente principale. Il valore non
     * viene incluso nei payload HTTP e non controlla il reader.
     */
    dom.storyReadingDirection = { value: undefined };

    const readerMode = dom.storyReaderMode;
    if (!readerMode) return;

    const MODES = [
        ["normal", "Normale"],
        ["manga", "Manga"],
        ["vertical", "Scorrimento verticale"],
    ];

    readerMode.replaceChildren(...MODES.map(([value, label]) => {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label;
        return option;
    }));
    readerMode.value = "normal";

    function currentReaderMode() {
        const mode = readerMode.value;
        return mode === "manga" || mode === "vertical" ? mode : "normal";
    }

    function setPagedNavigation(mode, index, pageCount) {
        if (mode === "manga") {
            // Nel manga il lato sinistro porta alla pagina successiva.
            dom.storyReaderPrevious.textContent = "← Successiva";
            dom.storyReaderNext.textContent = "Precedente →";
            dom.storyReaderPrevious.disabled = index >= pageCount - 1;
            dom.storyReaderNext.disabled = index <= 0;
            return;
        }

        dom.storyReaderPrevious.textContent = "← Precedente";
        dom.storyReaderNext.textContent = "Successiva →";
        dom.storyReaderPrevious.disabled = index <= 0;
        dom.storyReaderNext.disabled = index >= pageCount - 1;
    }

    /*
     * Sostituisce il submit legacy. Nessuno dei tre endpoint riceve piu'
     * reading_direction dal frontend.
     */
    submitStoryForm = async function submitStoryWithoutReadingDirection(allowDuplicates = false) {
        const title = dom.storyTitleInput.value.trim();
        if (!title) {
            setStatus(dom.storyStatus, "Inserisci il titolo della storia.");
            return;
        }
        if (state.storyMode === "new" && !state.storyCharacters.length) {
            setStatus(dom.storyStatus, "Seleziona almeno un personaggio.");
            return;
        }
        if (state.storySourceItems.length < 2) {
            setStatus(dom.storyStatus, "Una storia deve avere almeno due pagine.");
            return;
        }

        dom.submitStory.disabled = true;
        setStatus(dom.storyStatus, "Salvataggio della storia...");

        const common = { title };
        const newPageMetadata = {
            character_ids: state.storyCharacters.map(character => character.id),
            tags: parseTags(dom.storyTagsInput.value),
            artists: parseTags(dom.storyArtistsInput.value),
            ai_generated: dom.storyAiCheckbox.checked,
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
                        cover_file_id: Number(state.storyCoverKey),
                    }),
                });
            } else if (state.storyMode === "new") {
                response = await fetch("/api/stories/from-new", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        ...common,
                        ...newPageMetadata,
                        relative_paths: state.storySourceItems.map(item => item.relative_path),
                        cover_index: storyCoverIndex(),
                        allow_duplicates: allowDuplicates || dom.storyAllowDuplicates.checked,
                    }),
                });
            } else {
                response = await fetch("/api/stories/from-gallery", {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify({
                        ...common,
                        file_ids: state.storySourceItems.map(item => item.id),
                        cover_index: storyCoverIndex(),
                    }),
                });
            }

            if (response.status === 409 && state.storyMode === "new") {
                const payload = await response.json();
                const duplicateCount = payload.detail?.duplicates?.length || 1;
                const keep = window.confirm(
                    `${duplicateCount} duplicati identici trovati. Conservarli comunque nella storia?`,
                );
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
    };

    openStoryReader = async function openStoryReaderWithUserMode(storyId) {
        try {
            const story = await readJson(await fetch(`/api/stories/${storyId}`));
            // Il reader non deve conoscere la vecchia proprieta'.
            if (Object.prototype.hasOwnProperty.call(story, "reading_direction")) {
                delete story.reading_direction;
            }

            state.readerStory = story;
            state.readerPageIndex = 0;
            dom.storyReaderTitle.textContent = story.title;

            const missingPages = story.pages.filter(page => page.available === false).length;
            const missingLabel = missingPages ? ` · ${missingPages} non disponibili` : "";
            const characterLabel = story.characters.map(character => character.name).join(", ");
            dom.storyReaderMeta.textContent = `${story.pages.length} pagine${missingLabel}${characterLabel ? ` · ${characterLabel}` : ""}`;

            readerMode.value = "normal";
            renderStoryReader();
            dom.storyReaderDialog.showModal();
        } catch (error) {
            setStatus(dom.globalStatus, error.message);
        }
    };

    renderStoryReader = function renderStoryReaderWithUserMode() {
        const story = state.readerStory;
        if (!story) return;

        const mode = currentReaderMode();
        const vertical = mode === "vertical";
        dom.storyReaderContent.replaceChildren();
        dom.storyReaderNavigation.hidden = vertical;

        if (!story.pages.length) {
            dom.storyReaderNavigation.hidden = true;
            dom.storyReaderContent.appendChild(createMissingStoryPage());
            return;
        }

        if (vertical) {
            const container = document.createElement("div");
            container.className = "story-reader-vertical";

            // Sempre page_number crescente. La modalita' non modifica i dati.
            for (const page of story.pages) {
                if (page.available === false) {
                    container.appendChild(createMissingStoryPage(page.page_number));
                    continue;
                }
                const image = document.createElement("img");
                image.src = page.media_url;
                image.alt = `${story.title} — pagina ${page.page_number}`;
                image.loading = "lazy";
                image.decoding = "async";
                image.classList.toggle("transparent-media", Boolean(page.has_transparency));
                container.appendChild(image);
            }

            dom.storyReaderContent.appendChild(container);
            return;
        }

        // In ogni modalita' indice 0 = pagina 1. Mai invertire story.pages.
        state.readerPageIndex = Math.min(
            Math.max(state.readerPageIndex, 0),
            story.pages.length - 1,
        );
        const page = story.pages[state.readerPageIndex];
        const container = document.createElement("div");
        container.className = "story-reader-single";

        if (page.available === false) {
            container.appendChild(createMissingStoryPage(page.page_number));
        } else {
            const image = document.createElement("img");
            image.src = page.media_url;
            image.alt = `${story.title} — pagina ${page.page_number || state.readerPageIndex + 1}`;
            image.classList.toggle("transparent-media", Boolean(page.has_transparency));
            container.appendChild(image);
        }

        dom.storyReaderContent.appendChild(container);
        const displayedPage = Number(page.page_number) || state.readerPageIndex + 1;
        dom.storyReaderIndicator.textContent = `${displayedPage} / ${story.pages.length}`;
        setPagedNavigation(mode, state.readerPageIndex, story.pages.length);
    };

    /*
     * delta indica il pulsante/lato fisico:
     * -1 = sinistra, +1 = destra.
     * Normal: sinistra torna indietro, destra avanza.
     * Manga:  sinistra avanza, destra torna indietro.
     */
    changeStoryReaderPage = function changeStoryReaderPageWithUserMode(delta) {
        if (!state.readerStory || currentReaderMode() === "vertical") return;

        const logicalDelta = currentReaderMode() === "manga" ? -delta : delta;
        const nextIndex = state.readerPageIndex + logicalDelta;
        if (nextIndex < 0 || nextIndex >= state.readerStory.pages.length) return;

        state.readerPageIndex = nextIndex;
        renderStoryReader();
    };

    readerMode.addEventListener("change", () => {
        state.readerPageIndex = 0;
        renderStoryReader();
    });

    // Il listener M9.2.2 controlla solo il valore "single" e resta quindi inattivo.
    document.addEventListener("keydown", event => {
        if (!dom.storyReaderDialog.open || currentReaderMode() === "vertical" || !state.readerStory) return;
        if (event.key === "Escape") return;

        const activeElement = document.activeElement;
        if (activeElement?.matches("input, textarea, select, [contenteditable='true']")) return;

        if (event.key === "ArrowLeft") {
            event.preventDefault();
            changeStoryReaderPage(-1);
        } else if (event.key === "ArrowRight") {
            event.preventDefault();
            changeStoryReaderPage(1);
        }
    });

    // Rimuove dalle card qualsiasi etichetta LTR/RTL generata dal renderer legacy.
    const cleanStoryCardDirections = () => {
        if (!dom.storyGrid) return;
        for (const details of dom.storyGrid.querySelectorAll(".media-details")) {
            while (details.children.length > 1) details.lastElementChild.remove();
        }
    };

    cleanStoryCardDirections();
    if (dom.storyGrid) {
        new MutationObserver(cleanStoryCardDirections).observe(dom.storyGrid, {
            childList: true,
            subtree: true,
        });
    }
})();
