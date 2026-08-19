"use strict";

(() => {
    // La direzione LTR/RTL resta solo come campo legacy richiesto dalle API esistenti.
    // Non viene più mostrata all'utente e non controlla il reader.
    if (dom.storyReadingDirection) {
        dom.storyReadingDirection.value = "ltr";
    }

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

    function readerPagesForMode(story, mode) {
        if (mode === "manga") return [...story.pages].reverse();
        return story.pages;
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
            dom.storyReaderMode.value = "normal";
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
        const mode = dom.storyReaderMode.value || "normal";
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

        const pages = readerPagesForMode(story, mode);
        state.readerPageIndex = Math.min(Math.max(state.readerPageIndex, 0), pages.length - 1);
        const page = pages[state.readerPageIndex];
        const container = document.createElement("div");
        container.className = "story-reader-single";

        if (page.available === false) {
            container.appendChild(createMissingStoryPage(page.page_number));
        } else {
            const image = document.createElement("img");
            image.src = page.media_url;
            image.alt = `${story.title} — pagina ${page.page_number}`;
            image.classList.toggle("transparent-media", Boolean(page.has_transparency));
            container.appendChild(image);
        }

        dom.storyReaderContent.appendChild(container);
        const displayedPage = Number(page.page_number) || (
            mode === "manga"
                ? story.pages.length - state.readerPageIndex
                : state.readerPageIndex + 1
        );
        dom.storyReaderIndicator.textContent = `${displayedPage} / ${story.pages.length}`;
        dom.storyReaderPrevious.disabled = state.readerPageIndex <= 0;
        dom.storyReaderNext.disabled = state.readerPageIndex >= pages.length - 1;
    };

    changeStoryReaderPage = function changeStoryReaderPageWithUserMode(delta) {
        if (!state.readerStory || dom.storyReaderMode.value === "vertical") return;
        state.readerPageIndex += delta;
        renderStoryReader();
    };

    // Il listener originale resta innocuo per normal/manga; questo esegue il nuovo reader.
    dom.storyReaderMode.addEventListener("change", () => {
        state.readerPageIndex = 0;
        renderStoryReader();
    });

    // Il vecchio listener da tastiera reagisce soltanto alla modalità "single",
    // che non esiste più. Questa è quindi l'unica navigazione attiva del reader.
    document.addEventListener("keydown", event => {
        if (!dom.storyReaderDialog.open || dom.storyReaderMode.value === "vertical" || !state.readerStory) return;
        if (event.key === "Escape") return;
        const manga = dom.storyReaderMode.value === "manga";
        if (event.key === "ArrowLeft") {
            event.preventDefault();
            changeStoryReaderPage(manga ? 1 : -1);
        } else if (event.key === "ArrowRight") {
            event.preventDefault();
            changeStoryReaderPage(manga ? -1 : 1);
        }
    });

    // Le card non devono più descrivere la storia come LTR/RTL: la modalità è scelta nel reader.
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
