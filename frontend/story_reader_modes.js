"use strict";

(() => {
    // reading_direction rimane solo per compatibilità con le API esistenti.
    // La modalità di lettura viene scelta dall'utente nel reader.
    if (dom.storyReadingDirection) {
        dom.storyReadingDirection.value = "ltr";
        dom.storyReadingDirection.hidden = true;
    }
    const legacyDirectionLabel = document.querySelector('label[for="story-reading-direction"]');
    if (legacyDirectionLabel) legacyDirectionLabel.hidden = true;

    const originalSubmitStoryForm = submitStoryForm;
    submitStoryForm = async function submitStoryWithoutReadingDirection(allowDuplicates = false) {
        if (dom.storyReadingDirection) dom.storyReadingDirection.value = "ltr";
        return originalSubmitStoryForm(allowDuplicates);
    };

    const readerMode = dom.storyReaderMode;
    readerMode.replaceChildren();
    for (const [value, label] of [
        ["normal", "Normale"],
        ["manga", "Manga"],
        ["vertical", "Scorrimento verticale"],
    ]) {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label;
        readerMode.appendChild(option);
    }
    readerMode.value = "normal";

    function currentReaderMode() {
        const mode = readerMode.value;
        return mode === "manga" || mode === "vertical" ? mode : "normal";
    }

    function configurePagedNavigation(mode, index, pageCount) {
        if (mode === "manga") {
            // In un manga la pagina successiva si raggiunge andando verso sinistra.
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

    openStoryReader = async function openStoryReaderWithUserMode(storyId) {
        try {
            const story = await readJson(await fetch(`/api/stories/${storyId}`));
            state.readerStory = story;
            state.readerPageIndex = 0;
            dom.storyReaderTitle.textContent = story.title;
            const missingPages = story.pages.filter(page => page.available === false).length;
            const missingLabel = missingPages ? ` · ${missingPages} non disponibili` : "";
            dom.storyReaderMeta.textContent = `${story.pages.length} pagine${missingLabel} · ${story.characters.map(character => character.name).join(", ")}`;
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

        dom.storyReaderContent.replaceChildren();
        const mode = currentReaderMode();
        const vertical = mode === "vertical";
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

        // L'ordine dati resta sempre 1, 2, 3... anche in modalità Manga.
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
        configurePagedNavigation(mode, state.readerPageIndex, story.pages.length);
    };

    // delta indica la direzione fisica: -1 = sinistra, +1 = destra.
    changeStoryReaderPage = function changeStoryReaderPageWithUserMode(delta) {
        if (!state.readerStory || currentReaderMode() === "vertical") return;
        const logicalDelta = currentReaderMode() === "manga" ? -delta : delta;
        state.readerPageIndex += logicalDelta;
        renderStoryReader();
    };

    readerMode.addEventListener("change", () => {
        state.readerPageIndex = 0;
        renderStoryReader();
    });

    // Il listener originale di app.js ascolta solo la vecchia modalità "single".
    // Questo gestisce le frecce per Normale e Manga.
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

    // La direzione salvata nella storia non viene più mostrata nelle card.
    const cleanStoryCardDirections = () => {
        dom.storyGrid.querySelectorAll(".media-details").forEach(details => {
            while (details.children.length > 1) {
                details.lastElementChild.remove();
            }
        });
    };
    cleanStoryCardDirections();
    new MutationObserver(cleanStoryCardDirections).observe(dom.storyGrid, {
        childList: true,
        subtree: true,
    });
})();
