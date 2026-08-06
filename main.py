from __future__ import annotations

from contextlib import asynccontextmanager
import sqlite3
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from backend.database import init_database
from backend.backups import (
    create_automatic_backup,
    create_manual_backup,
    create_metadata_export,
    delete_backup,
    get_export_path,
    list_backups,
    open_backups_folder,
    restore_backup,
)
from backend.file_manager import (
    get_ranking,
    organize_file,
    organize_files_batch,
    preview_organization,
    update_character_score,
)
from backend.gallery import (
    get_franchise_characters,
    get_gallery_file,
    get_gallery_overview,
    list_gallery_files,
    list_tags,
    reveal_file,
    search_gallery,
    update_file_metadata,
)
from backend.indexer import synchronize_archive
from backend.stories import (
    create_story_from_gallery,
    create_story_from_new,
    dissolve_story,
    get_story,
    list_stories,
    preview_story,
    update_story,
)
from backend.trash import (
    empty_trash,
    list_trash_items,
    permanently_delete_trash_item,
    restore_trash_item,
    trash_gallery_file,
    trash_todo_file,
)
from backend.thumbnails import (
    cache_stats,
    clean_unused_cache,
    clear_cache,
    ensure_animated_preview,
    ensure_static_thumbnail,
    get_gallery_source,
    get_todo_source,
    get_trash_source,
    regenerate_cache,
)
from backend.scanner import (
    create_character,
    create_franchise,
    get_media_type,
    list_franchises,
    get_character_aliases,
    list_todo_files,
    load_config,
    scan_gallery,
    search_characters,
    sync_characters,
    update_character_aliases,
)

PROJECT_ROOT = Path(__file__).resolve().parent
FRONTEND_ROOT = PROJECT_ROOT / "frontend"


class OrganizeRequest(BaseModel):
    relative_path: str
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False
    allow_duplicate: bool = False


class OrganizePreviewRequest(BaseModel):
    character_ids: list[int] = Field(min_length=1)
    ai_generated: bool = False
    extension: str


class BatchOrganizeRequest(BaseModel):
    relative_paths: list[str] = Field(min_length=1, max_length=500)
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False
    allow_duplicates: bool = False


class StoryPreviewRequest(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    character_ids: list[int] = Field(min_length=1)
    ai_generated: bool = False
    page_count: int = Field(ge=2, le=500)


class StoryCreateFromNewRequest(BaseModel):
    relative_paths: list[str] = Field(min_length=2, max_length=500)
    title: str = Field(min_length=1, max_length=120)
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False
    reading_direction: str = "rtl"
    cover_index: int = Field(default=0, ge=0)
    allow_duplicates: bool = False


class StoryCreateFromGalleryRequest(BaseModel):
    file_ids: list[int] = Field(min_length=2, max_length=500)
    title: str = Field(min_length=1, max_length=120)
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False
    reading_direction: str = "rtl"
    cover_index: int = Field(default=0, ge=0)


class StoryUpdateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False
    reading_direction: str = "rtl"
    ordered_file_ids: list[int] = Field(min_length=2, max_length=500)
    cover_file_id: int | None = None


class ScoreRequest(BaseModel):
    delta: int


class FranchiseCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    code: str | None = Field(default=None, max_length=10)


class CharacterCreateRequest(BaseModel):
    franchise_id: int
    name: str = Field(min_length=1, max_length=120)
    aliases: list[str] = Field(default_factory=list)


class CharacterAliasesRequest(BaseModel):
    aliases: list[str] = Field(default_factory=list)


class FileMetadataRequest(BaseModel):
    character_ids: list[int] = Field(min_length=1)
    tags: list[str] = Field(default_factory=list)
    artists: list[str] = Field(default_factory=list)
    ai_generated: bool = False


class TodoTrashRequest(BaseModel):
    relative_path: str = Field(min_length=1)


class TrashRestoreRequest(BaseModel):
    auto_rename: bool = False


class EmptyTrashRequest(BaseModel):
    confirmation: str


class BackupRestoreRequest(BaseModel):
    confirmation: str


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_database()
    sync_characters()
    yield


app = FastAPI(
    title="H-Gallery",
    description="Galleria locale per immagini e video",
    version="1.5.0",
    lifespan=lifespan,
)

app.mount("/static", StaticFiles(directory=FRONTEND_ROOT), name="static")


@app.get("/", include_in_schema=False)
def home():
    return FileResponse(FRONTEND_ROOT / "index.html")


@app.get("/api/scan")
def get_gallery_scan():
    try:
        return scan_gallery()
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


@app.post("/api/archive/sync")
def sync_archive():
    try:
        backup = create_automatic_backup("prima_della_sincronizzazione")
        result = synchronize_archive()
        result["automatic_backup"] = backup["id"]
        return result
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


# Compatibilità con il pulsante/API della versione 0.3.
@app.post("/api/index/rebuild")
def rebuild_archive_index():
    return sync_archive()


@app.post("/api/characters/sync")
def sync_character_index():
    try:
        return sync_characters()
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/franchises")
def franchises():
    return {"results": list_franchises()}


@app.post("/api/franchises", status_code=201)
def add_franchise(request: FranchiseCreateRequest):
    try:
        return create_franchise(request.name, request.code)
    except (FileNotFoundError, NotADirectoryError, ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/characters", status_code=201)
def add_character(request: CharacterCreateRequest):
    try:
        return create_character(request.franchise_id, request.name, request.aliases)
    except (FileNotFoundError, NotADirectoryError, ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/characters/search")
def character_search(
    q: str = Query(min_length=1, max_length=100),
    limit: int = Query(default=20, ge=1, le=100),
):
    return {"results": search_characters(q, limit)}


@app.get("/api/characters/{character_id}/aliases")
def character_aliases(character_id: int):
    try:
        return get_character_aliases(character_id)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.put("/api/characters/{character_id}/aliases")
def save_character_aliases(character_id: int, request: CharacterAliasesRequest):
    try:
        return update_character_aliases(character_id, request.aliases)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.get("/api/todo/files")
def get_todo_files():
    try:
        return list_todo_files()
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error


@app.post("/api/organize/preview")
def organize_preview(request: OrganizePreviewRequest):
    try:
        return preview_organization(
            request.character_ids,
            request.ai_generated,
            request.extension,
        )
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/organize")
def organize(request: OrganizeRequest):
    try:
        result = organize_file(
            relative_path=request.relative_path,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
            allow_duplicate=request.allow_duplicate,
        )
        if result.get("status") == "duplicate":
            raise HTTPException(status_code=409, detail=result)
        return result
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (NotADirectoryError, ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/organize/batch")
def organize_batch(request: BatchOrganizeRequest):
    try:
        backup = create_automatic_backup("prima_dell_organizzazione_multipla")
        result = organize_files_batch(
            relative_paths=request.relative_paths,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
            allow_duplicates=request.allow_duplicates,
        )
        result["automatic_backup"] = backup["id"]
        return result
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (FileNotFoundError, NotADirectoryError, ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/stories/preview")
def story_preview(request: StoryPreviewRequest):
    try:
        return preview_story(
            request.title,
            request.character_ids,
            request.ai_generated,
            request.page_count,
        )
    except (FileNotFoundError, NotADirectoryError, ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/stories/from-new", status_code=201)
def create_new_story(request: StoryCreateFromNewRequest):
    try:
        backup = create_automatic_backup("prima_della_creazione_storia")
        result = create_story_from_new(
            relative_paths=request.relative_paths,
            title=request.title,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
            reading_direction=request.reading_direction,
            cover_index=request.cover_index,
            allow_duplicates=request.allow_duplicates,
        )
        if result.get("status") == "duplicate":
            raise HTTPException(status_code=409, detail=result)
        result["automatic_backup"] = backup["id"]
        return result
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (NotADirectoryError, ValueError, FileExistsError, OSError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/stories/from-gallery", status_code=201)
def create_gallery_story(request: StoryCreateFromGalleryRequest):
    try:
        backup = create_automatic_backup("prima_della_creazione_storia")
        result = create_story_from_gallery(
            file_ids=request.file_ids,
            title=request.title,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
            reading_direction=request.reading_direction,
            cover_index=request.cover_index,
        )
        result["automatic_backup"] = backup["id"]
        return result
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (NotADirectoryError, ValueError, FileExistsError, OSError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/stories")
def stories(
    character_id: int | None = Query(default=None, ge=1),
    franchise_id: int | None = Query(default=None, ge=1),
    collection: str | None = Query(default=None),
    ai_generated: bool | None = Query(default=None),
    tags: list[str] = Query(default=[]),
    q: str | None = Query(default=None, max_length=200),
    limit: int = Query(default=200, ge=1, le=500),
):
    try:
        return list_stories(
            character_id=character_id,
            franchise_id=franchise_id,
            collection=collection,
            ai_generated=ai_generated,
            tags=tags,
            query=q,
            limit=limit,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/stories/{story_id}")
def story_details(story_id: int):
    try:
        return get_story(story_id)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.put("/api/stories/{story_id}")
def edit_story(story_id: int, request: StoryUpdateRequest):
    try:
        backup = create_automatic_backup("prima_della_modifica_storia")
        result = update_story(
            story_id,
            title=request.title,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
            reading_direction=request.reading_direction,
            ordered_file_ids=request.ordered_file_ids,
            cover_file_id=request.cover_file_id,
        )
        result["automatic_backup"] = backup["id"]
        return result
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError, OSError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.delete("/api/stories/{story_id}/dissolve")
def dissolve_existing_story(story_id: int):
    try:
        backup = create_automatic_backup("prima_dello_scioglimento_storia")
        result = dissolve_story(story_id)
        result["automatic_backup"] = backup["id"]
        return result
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError, OSError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/gallery/overview")
def gallery_overview():
    try:
        return get_gallery_overview()
    except (FileNotFoundError, NotADirectoryError, ValueError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/gallery/franchises/{franchise_id}/characters")
def gallery_franchise_characters(franchise_id: int):
    try:
        return get_franchise_characters(franchise_id)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.get("/api/gallery/files")
def gallery_files(
    character_id: int | None = Query(default=None, ge=1),
    franchise_id: int | None = Query(default=None, ge=1),
    collection: str | None = Query(default=None),
    media_type: str | None = Query(default=None),
    ai_generated: bool | None = Query(default=None),
    tags: list[str] = Query(default=[]),
    q: str | None = Query(default=None, max_length=200),
    sort: str = Query(default="newest"),
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=60, ge=1, le=200),
):
    try:
        return list_gallery_files(
            character_id=character_id,
            franchise_id=franchise_id,
            collection=collection,
            media_type=media_type,
            ai_generated=ai_generated,
            tags=tags,
            query=q,
            sort=sort,
            page=page,
            limit=limit,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/gallery/files/{file_id}")
def gallery_file(file_id: int):
    try:
        return get_gallery_file(file_id)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error


@app.put("/api/gallery/files/{file_id}")
def edit_gallery_file(file_id: int, request: FileMetadataRequest):
    try:
        return update_file_metadata(
            file_id,
            character_ids=request.character_ids,
            tags=request.tags,
            artists=request.artists,
            ai_generated=request.ai_generated,
        )
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/gallery/files/{file_id}/reveal")
def reveal_gallery_file(file_id: int):
    try:
        return reveal_file(file_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, RuntimeError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/gallery/tags")
def gallery_tags(
    q: str | None = Query(default=None, max_length=100),
    limit: int = Query(default=100, ge=1, le=500),
    type: str | None = Query(default=None, pattern="^(general|artist|system)$"),
):
    return {"results": list_tags(q, limit, type)}


@app.get("/api/gallery/search")
def gallery_search(
    q: str = Query(min_length=1, max_length=100),
    limit: int = Query(default=12, ge=1, le=50),
):
    return search_gallery(q, limit)


@app.get("/api/trash")
def trash_list(
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=100, ge=1, le=200),
):
    return list_trash_items(page=page, limit=limit)


@app.post("/api/gallery/files/{file_id}/trash")
def move_gallery_file_to_trash(file_id: int):
    try:
        return trash_gallery_file(file_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/todo/trash")
def move_todo_file_to_trash(request: TodoTrashRequest):
    try:
        return trash_todo_file(request.relative_path)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/trash/empty")
def delete_all_trash(request: EmptyTrashRequest):
    try:
        if request.confirmation.strip().upper() != "ELIMINA":
            raise ValueError("Conferma non valida. Scrivi ELIMINA.")
        backup = create_automatic_backup("prima_dello_svuotamento_del_cestino")
        result = empty_trash(request.confirmation)
        result["automatic_backup"] = backup["id"]
        return result
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/trash/{trash_id}/restore")
def restore_from_trash(trash_id: int, request: TrashRestoreRequest):
    try:
        result = restore_trash_item(trash_id, request.auto_rename)
        if result.get("status") == "conflict":
            raise HTTPException(status_code=409, detail=result)
        return result
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (ValueError, FileExistsError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.delete("/api/trash/{trash_id}")
def delete_from_trash(trash_id: int):
    try:
        return permanently_delete_trash_item(trash_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


def _thumbnail_response(path: Path) -> FileResponse:
    return FileResponse(
        path,
        media_type="image/webp",
        headers={"Cache-Control": "public, max-age=31536000, immutable"},
    )


@app.get("/api/thumbnails/gallery/{file_id}")
def gallery_thumbnail(file_id: int):
    try:
        return _thumbnail_response(ensure_static_thumbnail(get_gallery_source(file_id)))
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/thumbnails/gallery/{file_id}/preview")
def gallery_animated_preview(file_id: int):
    try:
        path = ensure_animated_preview(get_gallery_source(file_id))
        if path is None:
            raise HTTPException(status_code=404, detail="Anteprima animata non disponibile.")
        return _thumbnail_response(path)
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/thumbnails/new")
def new_thumbnail(relative_path: str = Query(min_length=1)):
    try:
        return _thumbnail_response(ensure_static_thumbnail(get_todo_source(relative_path)))
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/thumbnails/new/preview")
def new_animated_preview(relative_path: str = Query(min_length=1)):
    try:
        path = ensure_animated_preview(get_todo_source(relative_path))
        if path is None:
            raise HTTPException(status_code=404, detail="Anteprima animata non disponibile.")
        return _thumbnail_response(path)
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/thumbnails/trash/{trash_id}")
def trash_thumbnail(trash_id: int):
    try:
        return _thumbnail_response(ensure_static_thumbnail(get_trash_source(trash_id)))
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/thumbnails/trash/{trash_id}/preview")
def trash_animated_preview(trash_id: int):
    try:
        path = ensure_animated_preview(get_trash_source(trash_id))
        if path is None:
            raise HTTPException(status_code=404, detail="Anteprima animata non disponibile.")
        return _thumbnail_response(path)
    except HTTPException:
        raise
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (ValueError, PermissionError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/settings/cache")
def thumbnail_cache_status():
    return cache_stats()


@app.post("/api/settings/cache/cleanup")
def cleanup_thumbnail_cache():
    return clean_unused_cache()


@app.post("/api/settings/cache/regenerate")
def regenerate_thumbnail_cache():
    return regenerate_cache()


@app.delete("/api/settings/cache")
def empty_thumbnail_cache():
    return clear_cache()


@app.get("/api/settings/backups")
def backup_list():
    return list_backups()


@app.post("/api/settings/backups", status_code=201)
def backup_create():
    try:
        return create_manual_backup()
    except (OSError, sqlite3.Error, ValueError) as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.delete("/api/settings/backups/{backup_id}")
def backup_delete(backup_id: str):
    try:
        return delete_backup(backup_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except (OSError, ValueError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/settings/backups/{backup_id}/restore")
def backup_restore(backup_id: str, request: BackupRestoreRequest):
    try:
        return restore_backup(backup_id, request.confirmation)
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except PermissionError as error:
        raise HTTPException(status_code=403, detail=str(error)) from error
    except (OSError, sqlite3.Error, ValueError) as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/settings/backups/export", status_code=201)
def metadata_export():
    try:
        return create_metadata_export()
    except (OSError, sqlite3.Error, ValueError) as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/settings/backups/exports/{filename}")
def metadata_export_download(filename: str):
    try:
        path = get_export_path(filename)
        return FileResponse(
            path,
            media_type="application/json",
            filename=path.name,
        )
    except FileNotFoundError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.post("/api/settings/backups/open")
def backups_open_folder():
    try:
        return open_backups_folder()
    except RuntimeError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@app.get("/api/ranking")
def ranking(
    limit: int = Query(default=100, ge=1, le=500),
    franchise_id: int | None = Query(default=None, ge=1),
):
    return {"results": get_ranking(limit, franchise_id)}


@app.post("/api/characters/{character_id}/score")
def change_score(character_id: int, request: ScoreRequest):
    try:
        return update_character_score(character_id, request.delta)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


def resolve_media_file(base_root: Path, relative_path: str) -> Path:
    requested_file = (base_root / relative_path).resolve()
    try:
        requested_file.relative_to(base_root)
    except ValueError as error:
        raise HTTPException(status_code=403, detail="Percorso non consentito.") from error

    if not requested_file.exists() or not requested_file.is_file():
        raise HTTPException(status_code=404, detail="File non trovato.")
    if get_media_type(requested_file) is None:
        raise HTTPException(status_code=415, detail="Formato non supportato.")
    return requested_file


@app.get("/media/todo/{relative_path:path}")
def get_todo_media(relative_path: str):
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    todo_root = (gallery_root / config.get("todo_folder", ".toDo")).resolve()
    return FileResponse(resolve_media_file(todo_root, relative_path))


@app.get("/media/gallery/{relative_path:path}")
def get_gallery_media(relative_path: str):
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    return FileResponse(resolve_media_file(gallery_root, relative_path))


@app.get("/media/trash/{relative_path:path}")
def get_trash_media(relative_path: str):
    config = load_config()
    gallery_root = Path(config["gallery_root"]).resolve()
    trash_root = (gallery_root / config.get("trash_folder", ".trash")).resolve()
    requested_file = (gallery_root / relative_path).resolve()
    try:
        requested_file.relative_to(trash_root)
    except ValueError as error:
        raise HTTPException(status_code=403, detail="Percorso non consentito.") from error
    if not requested_file.exists() or not requested_file.is_file():
        raise HTTPException(status_code=404, detail="File non trovato.")
    if get_media_type(requested_file) is None:
        raise HTTPException(status_code=415, detail="Formato non supportato.")
    return FileResponse(requested_file)
