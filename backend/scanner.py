from __future__ import annotations

import json
import shutil
import re
from functools import lru_cache
import unicodedata
import uuid
from pathlib import Path
from typing import Any
from urllib.parse import quote

from PIL import Image, ImageSequence, UnidentifiedImageError

from backend.database import get_connection
from backend.paths import (
    CONFIG_PATH,
    GALLERY_ROOT,
    ensure_user_layout,
    migrate_legacy_user_storage,
)

IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".tif", ".tiff",
}
VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".webm", ".avi", ".mov", ".m4v",
}

WINDOWS_RESERVED_NAMES = {
    "CON", "PRN", "AUX", "NUL",
    *(f"COM{number}" for number in range(1, 10)),
    *(f"LPT{number}" for number in range(1, 10)),
}
INVALID_WINDOWS_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1F]')


def load_config() -> dict[str, Any]:
    """Legge le preferenze della galleria attiva.

    Il percorso dell'archivio è gestito dalla configurazione dell'applicazione,
    mentre le preferenze specifiche della galleria sono conservate in
    ``.user/config.json`` dentro l'archivio stesso.
    """

    migrate_legacy_user_storage()
    ensure_user_layout()

    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            "Configurazione della galleria non trovata. Avvia configure.py o "
            f"Reconfigure.bat: {CONFIG_PATH}"
        )

    with CONFIG_PATH.open("r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    if not isinstance(config, dict):
        raise ValueError("La configurazione della galleria non è valida.")

    # Il percorso assoluto appartiene al registro dell'applicazione e non alla
    # configurazione portabile dell'archivio.
    if "gallery_root" in config or "script_folder" in config:
        config.pop("gallery_root", None)
        config.pop("script_folder", None)
        temporary_path = CONFIG_PATH.with_suffix(".json.tmp")
        temporary_path.write_text(
            json.dumps(config, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary_path.replace(CONFIG_PATH)

    if not GALLERY_ROOT.exists() or not GALLERY_ROOT.is_dir():
        raise NotADirectoryError(f"La galleria non è accessibile: {GALLERY_ROOT}")

    runtime_config = dict(config)
    runtime_config["gallery_root"] = str(GALLERY_ROOT)
    return runtime_config


def get_media_type(file_path: Path) -> str | None:
    extension = file_path.suffix.lower()
    if extension in IMAGE_EXTENSIONS:
        return "image"
    if extension in VIDEO_EXTENSIONS:
        return "video"
    return None


@lru_cache(maxsize=4096)
def _cached_image_has_transparency(
    absolute_path: str,
    file_size: int,
    modified_ns: int,
) -> bool:
    del file_size, modified_ns  # Fanno parte della chiave e invalidano la cache.
    try:
        with Image.open(absolute_path) as image:
            for frame in ImageSequence.Iterator(image):
                if "A" in frame.getbands():
                    minimum_alpha, _maximum_alpha = frame.getchannel("A").getextrema()
                    if minimum_alpha < 255:
                        return True
                elif "transparency" in frame.info:
                    alpha = frame.convert("RGBA").getchannel("A")
                    minimum_alpha, _maximum_alpha = alpha.getextrema()
                    if minimum_alpha < 255:
                        return True
    except (FileNotFoundError, OSError, UnidentifiedImageError):
        return False
    return False


def image_has_transparency(file_path: Path) -> bool:
    """Restituisce True solo se un PNG/GIF usa davvero pixel trasparenti."""

    if file_path.suffix.lower() not in {".png", ".gif"}:
        return False
    try:
        info = file_path.stat()
    except OSError:
        return False
    return _cached_image_has_transparency(
        str(file_path.resolve()),
        int(info.st_size),
        int(info.st_mtime_ns),
    )


def normalize_search_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    without_accents = "".join(
        character for character in normalized
        if not unicodedata.combining(character)
    )
    return without_accents.casefold().strip()


def normalize_alias(value: str) -> str:
    """Normalizza gli spazi di un alias senza modificarne la grafia."""

    return " ".join(str(value).split())


def normalize_aliases(aliases: list[str] | None, character_name: str = "") -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    character_key = normalize_search_text(character_name)

    for alias in aliases or []:
        cleaned = normalize_alias(alias)
        key = normalize_search_text(cleaned)
        if not cleaned or not key or key == character_key or key in seen:
            continue
        normalized.append(cleaned)
        seen.add(key)

    return normalized


def _normalize_filename_component(value: str) -> str:
    """Replica la normalizzazione usata per i nomi dei file organizzati.

    La funzione resta locale a questo modulo per evitare una dipendenza
    circolare con ``backend.file_manager``, che importa già ``scanner``.
    """

    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    cleaned = re.sub(r"[^A-Za-z0-9]+", "", ascii_value)
    return cleaned or "Unknown"


def _replace_path_prefix(relative_path: str, old_prefix: str, new_prefix: str) -> str:
    path = Path(relative_path)
    old_path = Path(old_prefix)
    try:
        suffix = path.relative_to(old_path)
    except ValueError:
        return relative_path
    return (Path(new_prefix) / suffix).as_posix()


def _replace_filename_prefix(filename: str, old_prefix: str, new_prefix: str) -> str:
    marker = f"{old_prefix}_"
    if filename.casefold().startswith(marker.casefold()):
        return f"{new_prefix}{filename[len(old_prefix):]}"
    return filename


def get_character_aliases(character_id: int) -> dict[str, Any]:
    with get_connection() as connection:
        character = connection.execute(
            """
            SELECT c.id, c.name, c.relative_path, c.score,
                   fr.id AS franchise_id, fr.name AS franchise_name,
                   fr.code AS franchise_code
            FROM characters c
            JOIN franchises fr ON fr.id = c.franchise_id
            WHERE c.id = ?
            """,
            (character_id,),
        ).fetchone()
        if character is None:
            raise ValueError("Personaggio non trovato.")

        rows = connection.execute(
            """
            SELECT alias
            FROM character_aliases
            WHERE character_id = ?
            ORDER BY alias COLLATE NOCASE
            """,
            (character_id,),
        ).fetchall()

    return {
        "id": int(character["id"]),
        "name": str(character["name"]),
        "relative_path": str(character["relative_path"]),
        "score": int(character["score"]),
        "franchise_id": int(character["franchise_id"]),
        "franchise_name": str(character["franchise_name"]),
        "franchise_code": str(character["franchise_code"]),
        "aliases": [str(row["alias"]) for row in rows],
        "label": f"{character['franchise_name']} / {character['name']}",
    }


def update_character_aliases(character_id: int, aliases: list[str]) -> dict[str, Any]:
    with get_connection() as connection:
        character = connection.execute(
            "SELECT id, name FROM characters WHERE id = ?",
            (character_id,),
        ).fetchone()
        if character is None:
            raise ValueError("Personaggio non trovato.")

        normalized = normalize_aliases(aliases, str(character["name"]))
        connection.execute(
            "DELETE FROM character_aliases WHERE character_id = ?",
            (character_id,),
        )
        connection.executemany(
            "INSERT INTO character_aliases(character_id, alias) VALUES (?, ?)",
            [(character_id, alias) for alias in normalized],
        )

    return get_character_aliases(character_id)


def update_character(
    character_id: int,
    name: str,
    aliases: list[str] | None = None,
) -> dict[str, Any]:
    """Aggiorna nome e alias rinominando in sicurezza cartella e file.

    Il nome viene sostituito soltanto nei file che seguono il prefisso creato
    da H-Gallery. I file in ``!Multiple`` e ``!Crossovers`` restano invariati:
    l'associazione al personaggio usa l'ID e riflette automaticamente il nuovo
    nome nell'interfaccia.
    """

    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    character_name = validate_folder_name(name, kind="personaggio")
    special_names = {
        str(config.get("multiple_folder", "!Multiple")).casefold(),
        str(config.get("ai_folder", ".AI")).casefold(),
        str(config.get("stories_folder", "!Stories")).casefold(),
    }
    if character_name.casefold() in special_names:
        raise ValueError("Questo nome è riservato dal programma.")

    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT c.id, c.name, c.relative_path, c.franchise_id,
                   fr.name AS franchise_name, fr.code AS franchise_code,
                   fr.relative_path AS franchise_relative_path
            FROM characters c
            JOIN franchises fr ON fr.id = c.franchise_id
            WHERE c.id = ? AND c.is_active = 1 AND fr.is_active = 1
            """,
            (character_id,),
        ).fetchone()
        if row is None:
            raise ValueError("Personaggio non trovato.")

        duplicate = connection.execute(
            """
            SELECT id
            FROM characters
            WHERE franchise_id = ? AND id <> ? AND name = ? COLLATE NOCASE
            LIMIT 1
            """,
            (int(row["franchise_id"]), character_id, character_name),
        ).fetchone()
        if duplicate is not None:
            raise ValueError("Questo personaggio esiste già nella serie selezionata.")

    old_name = str(row["name"])
    old_relative = str(row["relative_path"])
    normalized_aliases = normalize_aliases(aliases, character_name)

    if old_name == character_name:
        with get_connection() as connection:
            connection.execute(
                "DELETE FROM character_aliases WHERE character_id = ?",
                (character_id,),
            )
            connection.executemany(
                "INSERT INTO character_aliases(character_id, alias) VALUES (?, ?)",
                [(character_id, alias) for alias in normalized_aliases],
            )
        result = get_character_aliases(character_id)
        result["renamed"] = False
        result["old_name"] = old_name
        result["old_relative_path"] = old_relative
        return result

    franchise_path = (gallery_root / str(row["franchise_relative_path"])).resolve()
    old_directory = (gallery_root / old_relative).resolve()
    new_directory = (franchise_path / character_name).resolve()
    try:
        old_directory.relative_to(franchise_path)
        new_directory.relative_to(franchise_path)
    except ValueError as error:
        raise PermissionError("Il percorso del personaggio non appartiene alla serie.") from error

    if not old_directory.exists() or not old_directory.is_dir():
        raise FileNotFoundError(
            "La cartella del personaggio non esiste più. Esegui Rileggi cartelle."
        )

    # Windows non distingue maiuscole/minuscole: controlla anche i fratelli
    # con confronto case-insensitive prima di iniziare qualsiasi spostamento.
    for sibling in franchise_path.iterdir():
        if sibling == old_directory:
            continue
        if sibling.name.casefold() == character_name.casefold():
            raise ValueError("Esiste già una cartella con il nome scelto.")
    if new_directory.exists() and new_directory != old_directory:
        raise ValueError("Esiste già una cartella con il nome scelto.")

    old_file_prefix = str(row["franchise_code"]) + _normalize_filename_component(old_name)
    new_file_prefix = str(row["franchise_code"]) + _normalize_filename_component(character_name)

    file_renames: list[tuple[Path, str]] = []
    target_keys: set[str] = set()
    for file_path in sorted(old_directory.rglob("*"), key=lambda path: str(path).casefold()):
        if not file_path.is_file():
            continue
        new_filename = _replace_filename_prefix(
            file_path.name, old_file_prefix, new_file_prefix
        )
        if new_filename == file_path.name:
            continue
        target = file_path.with_name(new_filename)
        target_key = str(target).casefold()
        if target_key in target_keys:
            raise FileExistsError(f"Più file produrrebbero lo stesso nome: {new_filename}")
        target_keys.add(target_key)
        if target.exists() and target != file_path:
            raise FileExistsError(f"Esiste già un file con il nome: {new_filename}")
        file_renames.append((file_path.relative_to(old_directory), new_filename))

    new_relative = new_directory.relative_to(gallery_root).as_posix()
    staging_directory = franchise_path / f".hgallery-character-rename-{uuid.uuid4().hex}"
    completed_file_renames: list[tuple[Path, Path]] = []
    directory_moved = False

    try:
        # Il passaggio intermedio rende affidabili anche le rinomine che
        # cambiano soltanto maiuscole/minuscole su Windows.
        old_directory.rename(staging_directory)
        staging_directory.rename(new_directory)
        directory_moved = True

        for relative_path, new_filename in file_renames:
            source = new_directory / relative_path
            target = source.with_name(new_filename)
            temporary = source.with_name(
                f".hgallery-file-rename-{uuid.uuid4().hex}{source.suffix}"
            )
            source.rename(temporary)
            temporary.rename(target)
            completed_file_renames.append((source, target))

        renamed_by_internal_path = {
            relative_path.as_posix(): (relative_path.parent / new_filename).as_posix()
            for relative_path, new_filename in file_renames
        }

        with get_connection() as connection:
            file_rows = connection.execute(
                """
                SELECT id, filename, relative_path
                FROM files
                WHERE is_trashed = 0
                  AND (
                      relative_path = ?
                      OR substr(relative_path, 1, length(?) + 1) = ? || '/'
                  )
                """,
                (old_relative, old_relative, old_relative),
            ).fetchall()
            for file_row in file_rows:
                old_file_relative = str(file_row["relative_path"])
                internal = Path(old_file_relative).relative_to(Path(old_relative)).as_posix()
                new_internal = renamed_by_internal_path.get(internal, internal)
                new_file_relative = (Path(new_relative) / new_internal).as_posix()
                connection.execute(
                    """
                    UPDATE files
                    SET filename = ?, relative_path = ?
                    WHERE id = ?
                    """,
                    (Path(new_internal).name, new_file_relative, int(file_row["id"])),
                )

            story_rows = connection.execute(
                """
                SELECT id, relative_path
                FROM stories
                WHERE relative_path = ?
                   OR substr(relative_path, 1, length(?) + 1) = ? || '/'
                """,
                (old_relative, old_relative, old_relative),
            ).fetchall()
            for story_row in story_rows:
                connection.execute(
                    "UPDATE stories SET relative_path = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
                    (
                        _replace_path_prefix(
                            str(story_row["relative_path"]), old_relative, new_relative
                        ),
                        int(story_row["id"]),
                    ),
                )

            trash_rows = connection.execute(
                """
                SELECT id, original_relative_path, original_filename
                FROM trash_items
                WHERE source_kind = 'gallery'
                  AND (
                      original_relative_path = ?
                      OR substr(original_relative_path, 1, length(?) + 1) = ? || '/'
                  )
                """,
                (old_relative, old_relative, old_relative),
            ).fetchall()
            for trash_row in trash_rows:
                old_original = str(trash_row["original_relative_path"])
                new_original = _replace_path_prefix(
                    old_original, old_relative, new_relative
                )
                original_path = Path(new_original)
                renamed_original = _replace_filename_prefix(
                    original_path.name, old_file_prefix, new_file_prefix
                )
                if renamed_original != original_path.name:
                    new_original = original_path.with_name(renamed_original).as_posix()
                connection.execute(
                    """
                    UPDATE trash_items
                    SET original_relative_path = ?, original_filename = ?
                    WHERE id = ?
                    """,
                    (
                        new_original,
                        _replace_filename_prefix(
                            str(trash_row["original_filename"]),
                            old_file_prefix,
                            new_file_prefix,
                        ),
                        int(trash_row["id"]),
                    ),
                )

            connection.execute(
                """
                UPDATE characters
                SET name = ?, relative_path = ?
                WHERE id = ?
                """,
                (character_name, new_relative, character_id),
            )
            connection.execute(
                "DELETE FROM character_aliases WHERE character_id = ?",
                (character_id,),
            )
            connection.executemany(
                "INSERT INTO character_aliases(character_id, alias) VALUES (?, ?)",
                [(character_id, alias) for alias in normalized_aliases],
            )
            connection.execute(
                """
                INSERT INTO operations(
                    operation_type, source_relative_path, destination_relative_path
                ) VALUES ('character_rename', ?, ?)
                """,
                (old_relative, new_relative),
            )
    except Exception:
        for source, target in reversed(completed_file_renames):
            if target.exists():
                rollback_temp = target.with_name(
                    f".hgallery-file-rollback-{uuid.uuid4().hex}{target.suffix}"
                )
                target.rename(rollback_temp)
                rollback_temp.rename(source)
        if directory_moved and new_directory.exists():
            rollback_directory = franchise_path / f".hgallery-character-rollback-{uuid.uuid4().hex}"
            new_directory.rename(rollback_directory)
            rollback_directory.rename(old_directory)
        elif staging_directory.exists():
            staging_directory.rename(old_directory)
        raise

    result = get_character_aliases(character_id)
    result["renamed"] = old_name != character_name
    result["old_name"] = old_name
    result["old_relative_path"] = old_relative
    return result


def derive_franchise_code(name: str) -> str:
    """Genera un codice leggibile per una nuova serie.

    - Più parole: iniziale di ogni parola ("The Legend of Zelda" -> "TLOZ").
    - Una parola: prime quattro consonanti ("Konosuba" -> "KNSB").

    I codici già salvati nel database non vengono modificati.
    """

    normalized = unicodedata.normalize("NFKD", name)
    ascii_name = normalized.encode("ascii", "ignore").decode("ascii")
    words = [
        "".join(character for character in word if character.isalnum())
        for word in re.split(r"[\s\-_]+", ascii_name.strip())
    ]
    words = [word for word in words if word]

    if not words:
        return "FR"

    if len(words) > 1:
        code = "".join(word[0] for word in words)
        return (code[:10] or "FR").upper()

    word = words[0]
    consonants = "".join(
        character
        for character in word
        if character.isalpha() and character.casefold() not in "aeiou"
    )

    # Nomi composti solo da vocali o numeri devono comunque produrre un codice.
    code = consonants[:4] or word[:4]
    return (code or "FR").upper()


def make_unique_franchise_code(
    connection: Any,
    requested_code: str,
    *,
    exclude_franchise_id: int | None = None,
) -> str:
    """Restituisce un codice univoco aggiungendo 01, 02, 03... se necessario."""

    base_code = validate_franchise_code(requested_code)
    parameters: list[Any] = [base_code]
    exclusion = ""
    if exclude_franchise_id is not None:
        exclusion = " AND id <> ?"
        parameters.append(exclude_franchise_id)

    duplicate = connection.execute(
        f"SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE{exclusion} LIMIT 1",
        parameters,
    ).fetchone()
    if duplicate is None:
        return base_code

    number = 1
    while True:
        suffix = f"{number:02d}"
        available_base_length = max(1, 10 - len(suffix))
        candidate = f"{base_code[:available_base_length]}{suffix}"
        parameters = [candidate]
        if exclude_franchise_id is not None:
            parameters.append(exclude_franchise_id)
        duplicate = connection.execute(
            f"SELECT 1 FROM franchises WHERE code = ? COLLATE NOCASE{exclusion} LIMIT 1",
            parameters,
        ).fetchone()
        if duplicate is None:
            return candidate
        number += 1


def validate_folder_name(name: str, *, kind: str) -> str:
    cleaned = name.strip()
    if not cleaned:
        raise ValueError(f"Il nome della {kind} non può essere vuoto.")
    if cleaned in {".", ".."}:
        raise ValueError(f"Nome della {kind} non valido.")
    if cleaned.startswith(".") or cleaned.startswith("!"):
        raise ValueError(f"Il nome della {kind} non può iniziare con '.' oppure '!'.")
    if INVALID_WINDOWS_CHARS.search(cleaned):
        raise ValueError(f"Il nome della {kind} contiene caratteri non validi per Windows.")
    if cleaned.endswith(" ") or cleaned.endswith("."):
        raise ValueError(f"Il nome della {kind} non può terminare con uno spazio o un punto.")
    if cleaned.upper() in WINDOWS_RESERVED_NAMES:
        raise ValueError(f"Il nome '{cleaned}' è riservato da Windows.")
    return cleaned


def validate_franchise_code(code: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]", "", code).upper()
    if not 1 <= len(cleaned) <= 10:
        raise ValueError("Il codice della serie deve contenere da 1 a 10 lettere o numeri.")
    return cleaned


def get_franchise_folders(config: dict[str, Any]) -> list[Path]:
    gallery_root = Path(config["gallery_root"]).resolve()
    ignored = {
        config.get("script_folder", ".Script"),
        config.get("todo_folder", ".toDo"),
        config.get("trash_folder", ".trash"),
        config.get("crossovers_folder", "!Crossovers"),
    }

    return sorted(
        (
            path for path in gallery_root.iterdir()
            if path.is_dir()
            and path.name not in ignored
            and not path.name.startswith(".")
            and not path.name.startswith("!")
        ),
        key=lambda path: path.name.casefold(),
    )


def get_character_folders(franchise_path: Path, config: dict[str, Any]) -> list[Path]:
    special_names = {
        config.get("multiple_folder", "!Multiple"),
        config.get("ai_folder", ".AI"),
        config.get("stories_folder", "!Stories"),
    }

    return sorted(
        (
            path for path in franchise_path.iterdir()
            if path.is_dir()
            and path.name not in special_names
            and not path.name.startswith(".")
            and not path.name.startswith("!")
        ),
        key=lambda path: path.name.casefold(),
    )



def _directory_contains_files(directory: Path) -> bool:
    """Restituisce True se la directory contiene almeno un file o collegamento.

    In caso di errore di accesso la directory viene considerata non vuota, così
    la pulizia non rischia mai di rimuovere contenuti non verificati.
    """

    if not directory.exists() or not directory.is_dir():
        return False

    try:
        for path in directory.rglob("*"):
            if path.is_symlink() or path.is_file():
                return True
    except OSError:
        return True

    return False


def _remove_tree_if_fileless(directory: Path) -> bool:
    """Elimina una gerarchia composta esclusivamente da cartelle vuote."""

    if (
        not directory.exists()
        or not directory.is_dir()
        or directory.is_symlink()
        or _directory_contains_files(directory)
    ):
        return False

    try:
        shutil.rmtree(directory)
    except OSError:
        return False
    return True


def _prune_story_root(story_root: Path) -> int:
    """Elimina le cartelle di storie vuote e poi l’eventuale radice !Stories."""

    if not story_root.exists() or not story_root.is_dir():
        return 0
    removed = 0
    try:
        children = list(story_root.iterdir())
    except OSError:
        return 0
    for child in children:
        if child.is_dir() and _remove_tree_if_fileless(child):
            removed += 1
    if _remove_tree_if_fileless(story_root):
        removed += 1
    return removed


def prune_empty_directories() -> dict[str, int]:
    """Rimuove dal disco soltanto cartelle gestite che non contengono file.

    Le directory tecniche principali (.Script, .toDo e .trash) non vengono mai
    eliminate. Le cartelle possono essere ricreate automaticamente quando un
    file viene organizzato o ripristinato.
    """

    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    ai_folder = str(config.get("ai_folder", ".AI"))
    multiple_folder = str(config.get("multiple_folder", "!Multiple"))
    crossovers_folder = str(config.get("crossovers_folder", "!Crossovers"))
    stories_folder = str(config.get("stories_folder", "!Stories"))

    removed_ai = 0
    removed_characters = 0
    removed_multiple = 0
    removed_franchises = 0
    removed_crossovers = 0
    removed_stories = 0

    # Usa un elenco materializzato: alcune cartelle verranno eliminate durante
    # l'iterazione.
    franchise_paths = list(get_franchise_folders(config))
    for franchise_path in franchise_paths:
        if not franchise_path.exists():
            continue

        for character_path in list(get_character_folders(franchise_path, config)):
            ai_path = character_path / ai_folder
            for story_root in (character_path / stories_folder, ai_path / stories_folder):
                removed_stories += _prune_story_root(story_root)
            if _remove_tree_if_fileless(ai_path):
                removed_ai += 1
            if _remove_tree_if_fileless(character_path):
                removed_characters += 1

        multiple_path = franchise_path / multiple_folder
        if multiple_path.exists():
            multiple_ai_path = multiple_path / ai_folder
            for story_root in (multiple_path / stories_folder, multiple_ai_path / stories_folder):
                removed_stories += _prune_story_root(story_root)
            if _remove_tree_if_fileless(multiple_ai_path):
                removed_ai += 1
            if _remove_tree_if_fileless(multiple_path):
                removed_multiple += 1

        if _remove_tree_if_fileless(franchise_path):
            removed_franchises += 1

    crossovers_path = gallery_root / crossovers_folder
    if crossovers_path.exists():
        crossovers_ai_path = crossovers_path / ai_folder
        for story_root in (crossovers_path / stories_folder, crossovers_ai_path / stories_folder):
            removed_stories += _prune_story_root(story_root)
        if _remove_tree_if_fileless(crossovers_ai_path):
            removed_ai += 1
        if _remove_tree_if_fileless(crossovers_path):
            removed_crossovers += 1

    return {
        "removed_ai_folders": removed_ai,
        "removed_character_folders": removed_characters,
        "removed_multiple_folders": removed_multiple,
        "removed_franchise_folders": removed_franchises,
        "removed_crossovers_folders": removed_crossovers,
        "removed_story_folders": removed_stories,
    }


def _path_has_database_file(
    connection: Any,
    relative_path: str,
    *,
    trashed: bool | None,
) -> bool:
    conditions = [
        "(relative_path = ? OR substr(relative_path, 1, length(?) + 1) = ? || '/')"
    ]
    parameters: list[Any] = [relative_path, relative_path, relative_path]
    if trashed is not None:
        conditions.append("is_trashed = ?")
        parameters.append(int(trashed))

    row = connection.execute(
        f"SELECT 1 FROM files WHERE {' AND '.join(conditions)} LIMIT 1",
        parameters,
    ).fetchone()
    return row is not None


def _path_has_trash_origin(connection: Any, relative_path: str) -> bool:
    row = connection.execute(
        """
        SELECT 1
        FROM trash_items
        WHERE source_kind = 'gallery'
          AND (
              original_relative_path = ?
              OR substr(original_relative_path, 1, length(?) + 1) = ? || '/'
          )
        LIMIT 1
        """,
        (relative_path, relative_path, relative_path),
    ).fetchone()
    return row is not None


def cleanup_empty_entities() -> dict[str, int]:
    """Pulisce cartelle e record inutilizzati senza compromettere il cestino.

    Una serie o un personaggio con file nel cestino resta disponibile per nuove
    associazioni e ripristini, ma la galleria lo nasconde finché non possiede
    file attivi. I record senza file attivi né cestinati vengono eliminati.
    """

    directory_result = prune_empty_directories()
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()

    removed_characters = 0
    removed_franchises = 0
    activated_characters = 0
    deactivated_characters = 0
    activated_franchises = 0
    deactivated_franchises = 0

    with get_connection() as connection:
        character_rows = connection.execute(
            """
            SELECT id, franchise_id, relative_path, is_active
            FROM characters
            ORDER BY id
            """
        ).fetchall()

        for row in character_rows:
            character_id = int(row["id"])
            relative_path = str(row["relative_path"])
            directory = (gallery_root / relative_path).resolve()
            try:
                directory.relative_to(gallery_root)
            except ValueError:
                physical_files = False
            else:
                physical_files = _directory_contains_files(directory)

            active_link = connection.execute(
                """
                SELECT 1
                FROM file_characters fc
                JOIN files f ON f.id = fc.file_id
                WHERE fc.character_id = ? AND f.is_trashed = 0
                LIMIT 1
                """,
                (character_id,),
            ).fetchone() is not None
            any_link = connection.execute(
                """
                SELECT 1
                FROM file_characters
                WHERE character_id = ?
                LIMIT 1
                """,
                (character_id,),
            ).fetchone() is not None

            active_path = _path_has_database_file(
                connection, relative_path, trashed=False
            )
            trashed_origin = _path_has_trash_origin(connection, relative_path)

            has_active = physical_files or active_link or active_path
            has_any = has_active or any_link or trashed_origin

            if not has_any:
                connection.execute(
                    "DELETE FROM characters WHERE id = ?",
                    (character_id,),
                )
                removed_characters += 1
                continue

            # Anche un personaggio presente soltanto nel cestino resta
            # selezionabile durante l'organizzazione di nuovi file.
            new_active = 1
            old_active = int(row["is_active"])
            if new_active != old_active:
                connection.execute(
                    "UPDATE characters SET is_active = ? WHERE id = ?",
                    (new_active, character_id),
                )
                if new_active:
                    activated_characters += 1
                else:
                    deactivated_characters += 1

        franchise_rows = connection.execute(
            """
            SELECT id, relative_path, is_active
            FROM franchises
            ORDER BY id
            """
        ).fetchall()

        for row in franchise_rows:
            franchise_id = int(row["id"])
            relative_path = str(row["relative_path"])
            directory = (gallery_root / relative_path).resolve()
            try:
                directory.relative_to(gallery_root)
            except ValueError:
                physical_files = False
            else:
                physical_files = _directory_contains_files(directory)

            active_character = connection.execute(
                """
                SELECT 1
                FROM characters
                WHERE franchise_id = ? AND is_active = 1
                LIMIT 1
                """,
                (franchise_id,),
            ).fetchone() is not None
            any_character = connection.execute(
                """
                SELECT 1
                FROM characters
                WHERE franchise_id = ?
                LIMIT 1
                """,
                (franchise_id,),
            ).fetchone() is not None

            active_path = _path_has_database_file(
                connection, relative_path, trashed=False
            )
            trashed_origin = _path_has_trash_origin(connection, relative_path)

            has_active = physical_files or active_character or active_path
            has_any = has_active or any_character or trashed_origin

            if not has_any:
                connection.execute(
                    "DELETE FROM franchises WHERE id = ?",
                    (franchise_id,),
                )
                removed_franchises += 1
                continue

            new_active = 1
            old_active = int(row["is_active"])
            if new_active != old_active:
                connection.execute(
                    "UPDATE franchises SET is_active = ? WHERE id = ?",
                    (new_active, franchise_id),
                )
                if new_active:
                    activated_franchises += 1
                else:
                    deactivated_franchises += 1

    return {
        **directory_result,
        "removed_character_records": removed_characters,
        "removed_franchise_records": removed_franchises,
        "activated_character_records": activated_characters,
        "deactivated_character_records": deactivated_characters,
        "activated_franchise_records": activated_franchises,
        "deactivated_franchise_records": deactivated_franchises,
    }


def sync_characters() -> dict[str, Any]:
    """Sincronizza serie e personaggi presenti sul disco senza sovrascrivere i codici salvati."""

    initial_cleanup = prune_empty_directories()
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    configured_codes = config.get("franchise_codes", {})

    franchise_count = 0
    character_count = 0
    created_franchises = 0
    created_characters = 0

    with get_connection() as connection:
        connection.execute("UPDATE franchises SET is_active = 0")
        connection.execute("UPDATE characters SET is_active = 0")

        for franchise_path in get_franchise_folders(config):
            franchise_name = franchise_path.name
            franchise_relative = franchise_path.relative_to(gallery_root).as_posix()

            existing_franchise = connection.execute(
                """
                SELECT id, code
                FROM franchises
                WHERE name = ? OR relative_path = ?
                ORDER BY CASE WHEN relative_path = ? THEN 0 ELSE 1 END
                LIMIT 1
                """,
                (franchise_name, franchise_relative, franchise_relative),
            ).fetchone()

            if existing_franchise:
                franchise_id = int(existing_franchise["id"])
                franchise_code = str(existing_franchise["code"])
                connection.execute(
                    """
                    UPDATE franchises
                    SET name = ?, relative_path = ?, is_active = 1
                    WHERE id = ?
                    """,
                    (franchise_name, franchise_relative, franchise_id),
                )
            else:
                franchise_code = make_unique_franchise_code(
                    connection,
                    str(
                        configured_codes.get(franchise_name)
                        or derive_franchise_code(franchise_name)
                    ),
                )
                cursor = connection.execute(
                    """
                    INSERT INTO franchises(name, code, relative_path, is_active)
                    VALUES (?, ?, ?, 1)
                    """,
                    (franchise_name, franchise_code, franchise_relative),
                )
                franchise_id = int(cursor.lastrowid)
                created_franchises += 1

            franchise_count += 1

            for character_path in get_character_folders(franchise_path, config):
                character_relative = character_path.relative_to(gallery_root).as_posix()
                existing_character = connection.execute(
                    """
                    SELECT id
                    FROM characters
                    WHERE (franchise_id = ? AND name = ?) OR relative_path = ?
                    LIMIT 1
                    """,
                    (franchise_id, character_path.name, character_relative),
                ).fetchone()

                if existing_character:
                    connection.execute(
                        """
                        UPDATE characters
                        SET franchise_id = ?, name = ?, relative_path = ?, is_active = 1
                        WHERE id = ?
                        """,
                        (
                            franchise_id,
                            character_path.name,
                            character_relative,
                            int(existing_character["id"]),
                        ),
                    )
                else:
                    connection.execute(
                        """
                        INSERT INTO characters(franchise_id, name, relative_path, is_active)
                        VALUES (?, ?, ?, 1)
                        """,
                        (franchise_id, character_path.name, character_relative),
                    )
                    created_characters += 1

                character_count += 1

    entity_cleanup = cleanup_empty_entities()
    combined_cleanup = dict(entity_cleanup)
    for key, value in initial_cleanup.items():
        combined_cleanup[key] = int(combined_cleanup.get(key, 0)) + int(value)

    return {
        "franchises": franchise_count,
        "characters": character_count,
        "created_franchises": created_franchises,
        "created_characters": created_characters,
        "cleanup": combined_cleanup,
    }


def list_franchises() -> list[dict[str, Any]]:
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, name, code, relative_path
            FROM franchises
            WHERE is_active = 1
            ORDER BY name COLLATE NOCASE
            """
        ).fetchall()

    return [
        {
            "id": int(row["id"]),
            "name": str(row["name"]),
            "code": str(row["code"]),
            "relative_path": str(row["relative_path"]),
        }
        for row in rows
    ]


def create_franchise(name: str, code: str | None = None) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    franchise_name = validate_folder_name(name, kind="serie")
    requested_code = code or derive_franchise_code(franchise_name)

    reserved = {
        config.get("script_folder", ".Script").casefold(),
        config.get("todo_folder", ".toDo").casefold(),
        config.get("crossovers_folder", "!Crossovers").casefold(),
    }
    if franchise_name.casefold() in reserved:
        raise ValueError("Questo nome è riservato dal programma.")

    destination = (gallery_root / franchise_name).resolve()
    try:
        destination.relative_to(gallery_root)
    except ValueError as error:
        raise ValueError("Percorso della serie non valido.") from error

    with get_connection() as connection:
        duplicate = connection.execute(
            "SELECT id FROM franchises WHERE name = ? COLLATE NOCASE",
            (franchise_name,),
        ).fetchone()
        if duplicate:
            raise ValueError("Esiste già una serie con questo nome.")

        franchise_code = make_unique_franchise_code(connection, requested_code)

        if destination.exists() and not destination.is_dir():
            raise ValueError("Esiste già un file con il nome scelto per la serie.")
        destination.mkdir(parents=False, exist_ok=True)

        cursor = connection.execute(
            """
            INSERT INTO franchises(name, code, relative_path, is_active)
            VALUES (?, ?, ?, 1)
            """,
            (franchise_name, franchise_code, destination.relative_to(gallery_root).as_posix()),
        )
        franchise_id = int(cursor.lastrowid)

    return {
        "id": franchise_id,
        "name": franchise_name,
        "code": franchise_code,
        "relative_path": destination.relative_to(gallery_root).as_posix(),
    }


def create_character(
    franchise_id: int,
    name: str,
    aliases: list[str] | None = None,
) -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    character_name = validate_folder_name(name, kind="personaggio")

    special_names = {
        config.get("multiple_folder", "!Multiple").casefold(),
        config.get("ai_folder", ".AI").casefold(),
        config.get("stories_folder", "!Stories").casefold(),
    }
    if character_name.casefold() in special_names:
        raise ValueError("Questo nome è riservato dal programma.")

    with get_connection() as connection:
        franchise = connection.execute(
            """
            SELECT id, name, code, relative_path
            FROM franchises
            WHERE id = ? AND is_active = 1
            """,
            (franchise_id,),
        ).fetchone()
        if franchise is None:
            raise ValueError("Serie non trovata.")

        duplicate = connection.execute(
            """
            SELECT id
            FROM characters
            WHERE franchise_id = ? AND name = ? COLLATE NOCASE
            """,
            (franchise_id, character_name),
        ).fetchone()
        if duplicate:
            raise ValueError("Questo personaggio esiste già nella serie selezionata.")

        franchise_path = (gallery_root / str(franchise["relative_path"])).resolve()
        destination = (franchise_path / character_name).resolve()
        try:
            destination.relative_to(franchise_path)
        except ValueError as error:
            raise ValueError("Percorso del personaggio non valido.") from error

        if destination.exists() and not destination.is_dir():
            raise ValueError("Esiste già un file con il nome scelto per il personaggio.")
        destination.mkdir(parents=True, exist_ok=True)

        relative_path = destination.relative_to(gallery_root).as_posix()
        cursor = connection.execute(
            """
            INSERT INTO characters(franchise_id, name, relative_path, is_active)
            VALUES (?, ?, ?, 1)
            """,
            (franchise_id, character_name, relative_path),
        )
        character_id = int(cursor.lastrowid)
        normalized_aliases = normalize_aliases(aliases, character_name)
        connection.executemany(
            "INSERT INTO character_aliases(character_id, alias) VALUES (?, ?)",
            [(character_id, alias) for alias in normalized_aliases],
        )

    return {
        "id": character_id,
        "name": character_name,
        "franchise_name": str(franchise["name"]),
        "franchise_code": str(franchise["code"]),
        "relative_path": relative_path,
        "score": 0,
        "aliases": normalized_aliases,
        "label": f"{franchise['name']} / {character_name}",
    }


def search_characters(query: str, limit: int = 20) -> list[dict[str, Any]]:
    normalized_query = normalize_search_text(query)
    if not normalized_query:
        return []

    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT
                characters.id,
                characters.name,
                characters.relative_path,
                characters.score,
                franchises.id AS franchise_id,
                franchises.name AS franchise_name,
                franchises.code AS franchise_code
            FROM characters
            JOIN franchises ON franchises.id = characters.franchise_id
            WHERE characters.is_active = 1
              AND franchises.is_active = 1
            """
        ).fetchall()
        alias_rows = connection.execute(
            """
            SELECT ca.character_id, ca.alias
            FROM character_aliases ca
            JOIN characters c ON c.id = ca.character_id
            JOIN franchises fr ON fr.id = c.franchise_id
            WHERE c.is_active = 1 AND fr.is_active = 1
            ORDER BY ca.alias COLLATE NOCASE
            """
        ).fetchall()

    aliases_by_character: dict[int, list[str]] = {}
    for row in alias_rows:
        aliases_by_character.setdefault(int(row["character_id"]), []).append(
            str(row["alias"])
        )

    ranked_results: list[tuple[int, str, dict[str, Any]]] = []

    for row in rows:
        character_id = int(row["id"])
        character_name = str(row["name"])
        franchise_name = str(row["franchise_name"])
        aliases = aliases_by_character.get(character_id, [])
        normalized_name = normalize_search_text(character_name)
        normalized_aliases = [(alias, normalize_search_text(alias)) for alias in aliases]
        normalized_label = normalize_search_text(
            f"{franchise_name} {character_name} {' '.join(aliases)}"
        )
        matched_alias = next(
            (alias for alias, normalized_alias in normalized_aliases
             if normalized_alias == normalized_query),
            None,
        )

        if normalized_query == normalized_name:
            rank = 0
        elif matched_alias is not None:
            rank = 1
        elif normalized_name.startswith(normalized_query):
            rank = 2
        elif any(alias.startswith(normalized_query) for _raw, alias in normalized_aliases):
            rank = 3
        elif normalized_query in normalized_name:
            rank = 4
        elif any(normalized_query in alias for _raw, alias in normalized_aliases):
            rank = 5
        elif all(part in normalized_label for part in normalized_query.split()):
            rank = 6
        else:
            continue

        result = {
            "id": character_id,
            "name": character_name,
            "franchise_id": int(row["franchise_id"]),
            "franchise_name": franchise_name,
            "franchise_code": str(row["franchise_code"]),
            "relative_path": str(row["relative_path"]),
            "score": int(row["score"]),
            "aliases": aliases,
            "matched_alias": matched_alias,
            "label": f"{franchise_name} / {character_name}",
        }
        ranked_results.append((rank, normalized_name, result))

    ranked_results.sort(
        key=lambda item: (item[0], item[1], item[2]["franchise_name"].casefold())
    )
    return [item[2] for item in ranked_results[:limit]]


def list_todo_files() -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    todo_folder_name = config.get("todo_folder", ".toDo")
    todo_root = (gallery_root / todo_folder_name).resolve()

    if not todo_root.exists():
        return {
            "folder": todo_folder_name,
            "display_name": "New",
            "path": str(todo_root),
            "exists": False,
            "files": [],
            "total_files": 0,
        }

    files: list[dict[str, Any]] = []

    for file_path in sorted(todo_root.rglob("*"), key=lambda path: str(path).casefold()):
        if not file_path.is_file():
            continue

        media_type = get_media_type(file_path)
        if media_type is None:
            continue

        try:
            file_info = file_path.stat()
        except OSError:
            continue

        relative_path = file_path.relative_to(todo_root).as_posix()
        files.append(
            {
                "name": file_path.name,
                "relative_path": relative_path,
                "extension": file_path.suffix.lower(),
                "media_type": media_type,
                "size": file_info.st_size,
                "modified_at": file_info.st_mtime,
                "media_url": "/media/todo/" + quote(relative_path, safe="/"),
                "thumbnail_url": (
                    "/api/thumbnails/new?relative_path="
                    + quote(relative_path, safe="")
                    + f"&v={file_info.st_size}-{int(file_info.st_mtime * 1000)}-1"
                ),
                "animated_preview_url": (
                    "/api/thumbnails/new/preview?relative_path="
                    + quote(relative_path, safe="")
                    + f"&v={file_info.st_size}-{int(file_info.st_mtime * 1000)}-1"
                    if (media_type == "video" and shutil.which("ffmpeg"))
                    or file_path.suffix.lower() == ".gif"
                    else None
                ),
                "has_transparency": image_has_transparency(file_path),
            }
        )

    return {
        "folder": todo_folder_name,
        "display_name": "New",
        "path": str(todo_root),
        "exists": True,
        "files": files,
        "total_files": len(files),
    }


def scan_gallery() -> dict[str, Any]:
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    franchises: list[dict[str, Any]] = []
    total_images = 0
    total_videos = 0

    for franchise_path in get_franchise_folders(config):
        images = 0
        videos = 0

        for file_path in franchise_path.rglob("*"):
            if not file_path.is_file():
                continue
            media_type = get_media_type(file_path)
            if media_type == "image":
                images += 1
            elif media_type == "video":
                videos += 1

        characters = get_character_folders(franchise_path, config)
        franchises.append(
            {
                "name": franchise_path.name,
                "path": str(franchise_path),
                "character_folders": len(characters),
                "images": images,
                "videos": videos,
                "total_files": images + videos,
            }
        )
        total_images += images
        total_videos += videos

    todo = list_todo_files()

    return {
        "gallery_root": str(gallery_root),
        "franchises": franchises,
        "todo": {
            "name": todo["folder"],
            "path": todo["path"],
            "total_files": todo["total_files"],
            "exists": todo["exists"],
        },
        "summary": {
            "franchises": len(franchises),
            "images": total_images,
            "videos": total_videos,
            "total_files": total_images + total_videos,
        },
    }
