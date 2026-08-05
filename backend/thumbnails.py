from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import quote

from PIL import Image, ImageDraw, ImageOps, ImageSequence

from backend.database import get_connection
from backend.scanner import get_media_type, list_todo_files, load_config

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CACHE_ROOT = PROJECT_ROOT / "cache" / "thumbnails"
THUMBNAIL_SIZE = 512
THUMBNAIL_QUALITY = 80
CACHE_VERSION = 1
STATIC_SUFFIX = ".webp"
PREVIEW_SUFFIX = "_preview.webp"
ANIMATED_IMAGE_EXTENSIONS = {".gif"}


@dataclass(frozen=True)
class ThumbnailSource:
    namespace: str
    identifier: str
    source_path: Path
    media_type: str
    extension: str
    size: int
    modified_at: float

    @property
    def token(self) -> str:
        return f"{self.size}_{int(self.modified_at * 1000)}_v{CACHE_VERSION}"

    @property
    def safe_identifier(self) -> str:
        if self.namespace == "gallery" and self.identifier.isdigit():
            return self.identifier
        return hashlib.sha1(self.identifier.encode("utf-8")).hexdigest()[:20]

    @property
    def folder(self) -> Path:
        return CACHE_ROOT / self.namespace

    @property
    def static_path(self) -> Path:
        return self.folder / f"{self.safe_identifier}_{self.token}{STATIC_SUFFIX}"

    @property
    def preview_path(self) -> Path:
        return self.folder / f"{self.safe_identifier}_{self.token}{PREVIEW_SUFFIX}"

    @property
    def supports_animated_preview(self) -> bool:
        return self.media_type == "video" or self.extension.lower() in ANIMATED_IMAGE_EXTENSIONS


def _gallery_root() -> Path:
    return Path(load_config()["gallery_root"]).resolve()


def _ensure_inside(path: Path, root: Path, message: str) -> None:
    try:
        path.relative_to(root)
    except ValueError as error:
        raise PermissionError(message) from error


def _source_from_file(
    *, namespace: str, identifier: str, source_path: Path, media_type: str, extension: str
) -> ThumbnailSource:
    if not source_path.exists() or not source_path.is_file():
        raise FileNotFoundError(f"File non trovato: {source_path}")
    stat = source_path.stat()
    return ThumbnailSource(
        namespace=namespace,
        identifier=identifier,
        source_path=source_path,
        media_type=media_type,
        extension=extension.lower(),
        size=int(stat.st_size),
        modified_at=float(stat.st_mtime),
    )


def get_gallery_source(file_id: int) -> ThumbnailSource:
    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, relative_path, media_type, extension
            FROM files
            WHERE id = ? AND is_trashed = 0
            """,
            (file_id,),
        ).fetchone()
    if row is None:
        raise ValueError("File non trovato nella galleria.")
    root = _gallery_root()
    source = (root / str(row["relative_path"])).resolve()
    _ensure_inside(source, root, "Percorso non consentito.")
    return _source_from_file(
        namespace="gallery",
        identifier=str(file_id),
        source_path=source,
        media_type=str(row["media_type"]),
        extension=str(row["extension"]),
    )


def get_todo_source(relative_path: str) -> ThumbnailSource:
    config = load_config()
    root = _gallery_root()
    todo_root = (root / str(config.get("todo_folder", ".toDo"))).resolve()
    source = (todo_root / relative_path).resolve()
    _ensure_inside(source, todo_root, "Il file non appartiene a New.")
    media_type = get_media_type(source)
    if media_type is None:
        raise ValueError("Formato non supportato.")
    return _source_from_file(
        namespace="new",
        identifier=Path(relative_path).as_posix(),
        source_path=source,
        media_type=media_type,
        extension=source.suffix,
    )


def get_trash_source(trash_id: int) -> ThumbnailSource:
    with get_connection() as connection:
        row = connection.execute(
            """
            SELECT id, trash_relative_path, media_type, extension
            FROM trash_items
            WHERE id = ?
            """,
            (trash_id,),
        ).fetchone()
    if row is None:
        raise ValueError("Elemento del cestino non trovato.")
    root = _gallery_root()
    trash_name = str(load_config().get("trash_folder", ".trash"))
    trash_root = (root / trash_name).resolve()
    source = (root / str(row["trash_relative_path"])).resolve()
    _ensure_inside(source, trash_root, "Il file non appartiene al cestino.")
    return _source_from_file(
        namespace="trash",
        identifier=str(trash_id),
        source_path=source,
        media_type=str(row["media_type"]),
        extension=str(row["extension"]),
    )


def gallery_thumbnail_url(file_id: int, size: int, modified_at: float) -> str:
    token = f"{size}-{int(modified_at * 1000)}-{CACHE_VERSION}"
    return f"/api/thumbnails/gallery/{file_id}?v={token}"


def gallery_preview_url(
    file_id: int, size: int, modified_at: float, media_type: str, extension: str
) -> str | None:
    if media_type == "video" and not ffmpeg_available():
        return None
    if media_type != "video" and extension.lower() not in ANIMATED_IMAGE_EXTENSIONS:
        return None
    token = f"{size}-{int(modified_at * 1000)}-{CACHE_VERSION}"
    return f"/api/thumbnails/gallery/{file_id}/preview?v={token}"


def todo_thumbnail_url(relative_path: str, size: int, modified_at: float) -> str:
    token = f"{size}-{int(modified_at * 1000)}-{CACHE_VERSION}"
    return (
        "/api/thumbnails/new?relative_path="
        + quote(relative_path, safe="")
        + f"&v={token}"
    )


def todo_preview_url(
    relative_path: str, size: int, modified_at: float, media_type: str, extension: str
) -> str | None:
    if media_type == "video" and not ffmpeg_available():
        return None
    if media_type != "video" and extension.lower() not in ANIMATED_IMAGE_EXTENSIONS:
        return None
    token = f"{size}-{int(modified_at * 1000)}-{CACHE_VERSION}"
    return (
        "/api/thumbnails/new/preview?relative_path="
        + quote(relative_path, safe="")
        + f"&v={token}"
    )


def trash_thumbnail_url(trash_id: int, size: int, modified_at: float | None = None) -> str:
    token = f"{size}-{int((modified_at or 0) * 1000)}-{CACHE_VERSION}"
    return f"/api/thumbnails/trash/{trash_id}?v={token}"


def trash_preview_url(
    trash_id: int,
    size: int,
    media_type: str,
    extension: str,
    modified_at: float | None = None,
) -> str | None:
    if media_type == "video" and not ffmpeg_available():
        return None
    if media_type != "video" and extension.lower() not in ANIMATED_IMAGE_EXTENSIONS:
        return None
    token = f"{size}-{int((modified_at or 0) * 1000)}-{CACHE_VERSION}"
    return f"/api/thumbnails/trash/{trash_id}/preview?v={token}"


def _remove_stale_variants(source: ThumbnailSource, keep: set[Path]) -> None:
    source.folder.mkdir(parents=True, exist_ok=True)
    prefix = f"{source.safe_identifier}_"
    for candidate in source.folder.glob(f"{prefix}*.webp"):
        if candidate not in keep:
            try:
                candidate.unlink()
            except OSError:
                pass


def _prepare_image_frame(image: Image.Image) -> Image.Image:
    frame = ImageOps.exif_transpose(image)
    frame.thumbnail((THUMBNAIL_SIZE, THUMBNAIL_SIZE), Image.Resampling.LANCZOS)
    if "A" in frame.getbands() or "transparency" in frame.info:
        return frame.convert("RGBA")
    return frame.convert("RGB")


def _atomic_save_image(image: Image.Image, destination: Path, **save_kwargs: Any) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        suffix=destination.suffix, dir=destination.parent, delete=False
    ) as temp_file:
        temp_path = Path(temp_file.name)
    try:
        image.save(temp_path, **save_kwargs)
        os.replace(temp_path, destination)
    finally:
        if temp_path.exists():
            temp_path.unlink(missing_ok=True)


def _generate_static_image(source: ThumbnailSource) -> Path:
    with Image.open(source.source_path) as image:
        image.seek(0)
        frame = _prepare_image_frame(image.copy())
        _atomic_save_image(
            frame,
            source.static_path,
            format="WEBP",
            quality=THUMBNAIL_QUALITY,
            method=4,
        )
    return source.static_path


def _ffmpeg_executable(name: str) -> str | None:
    return shutil.which(name)


def ffmpeg_available() -> bool:
    return bool(_ffmpeg_executable("ffmpeg"))


def _subprocess_options() -> dict[str, Any]:
    options: dict[str, Any] = {
        "capture_output": True,
        "text": True,
        "check": True,
        "timeout": 180,
    }
    if os.name == "nt":
        options["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    return options


def _video_duration(source_path: Path) -> float | None:
    ffprobe = _ffmpeg_executable("ffprobe")
    if not ffprobe:
        return None
    command = [
        ffprobe,
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "json",
        str(source_path),
    ]
    try:
        completed = subprocess.run(command, **_subprocess_options())
        data = json.loads(completed.stdout)
        duration = float(data.get("format", {}).get("duration", 0))
        return duration if duration > 0 else None
    except (subprocess.SubprocessError, ValueError, json.JSONDecodeError, OSError):
        return None


def _video_start_time(source_path: Path, preview_duration: float = 0.0) -> float:
    duration = _video_duration(source_path)
    if duration is None:
        return 1.0
    usable = max(0.0, duration - preview_duration)
    return min(max(0.0, duration * 0.25), usable)


def _run_ffmpeg(command: list[str], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        suffix=destination.suffix, dir=destination.parent, delete=False
    ) as temp_file:
        temp_path = Path(temp_file.name)
    temp_path.unlink(missing_ok=True)
    command = [str(temp_path) if value == "__OUTPUT__" else value for value in command]
    try:
        subprocess.run(command, **_subprocess_options())
        if not temp_path.exists() or temp_path.stat().st_size == 0:
            raise RuntimeError("FFmpeg non ha prodotto una miniatura valida.")
        os.replace(temp_path, destination)
    finally:
        temp_path.unlink(missing_ok=True)


def _generate_static_video(source: ThumbnailSource) -> Path:
    ffmpeg = _ffmpeg_executable("ffmpeg")
    if not ffmpeg:
        return _generate_placeholder(source.static_path, "VIDEO", play_symbol=True)
    start = _video_start_time(source.source_path)
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{start:.3f}",
        "-i",
        str(source.source_path),
        "-frames:v",
        "1",
        "-vf",
        f"scale={THUMBNAIL_SIZE}:{THUMBNAIL_SIZE}:force_original_aspect_ratio=decrease",
        "-an",
        "-c:v",
        "libwebp",
        "-quality",
        str(THUMBNAIL_QUALITY),
        "-compression_level",
        "4",
        "-y",
        "__OUTPUT__",
    ]
    try:
        _run_ffmpeg(command, source.static_path)
    except (subprocess.SubprocessError, RuntimeError, OSError):
        return _generate_placeholder(source.static_path, "VIDEO", play_symbol=True)
    return source.static_path


def _generate_placeholder(destination: Path, label: str, play_symbol: bool = False) -> Path:
    image = Image.new("RGB", (THUMBNAIL_SIZE, THUMBNAIL_SIZE), (34, 38, 47))
    draw = ImageDraw.Draw(image)
    if play_symbol:
        cx = THUMBNAIL_SIZE // 2
        cy = THUMBNAIL_SIZE // 2 - 20
        draw.polygon([(cx - 38, cy - 50), (cx - 38, cy + 50), (cx + 54, cy)], fill=(205, 213, 225))
    draw.text((THUMBNAIL_SIZE // 2, THUMBNAIL_SIZE - 70), label, anchor="mm", fill=(190, 198, 210))
    _atomic_save_image(
        image,
        destination,
        format="WEBP",
        quality=THUMBNAIL_QUALITY,
        method=4,
    )
    return destination


def ensure_static_thumbnail(source: ThumbnailSource) -> Path:
    if source.static_path.exists() and source.static_path.stat().st_size > 0:
        return source.static_path
    _remove_stale_variants(source, {source.static_path, source.preview_path})
    try:
        if source.media_type == "image":
            return _generate_static_image(source)
        return _generate_static_video(source)
    except Exception:
        return _generate_placeholder(
            source.static_path,
            "IMMAGINE" if source.media_type == "image" else "VIDEO",
            play_symbol=source.media_type == "video",
        )


def _generate_animated_image(source: ThumbnailSource) -> Path | None:
    frames: list[Image.Image] = []
    durations: list[int] = []
    elapsed = 0
    next_sample = 0
    sample_interval = 100  # 10 FPS
    max_duration = 4000

    with Image.open(source.source_path) as image:
        if not bool(getattr(image, "is_animated", False)) or int(getattr(image, "n_frames", 1)) <= 1:
            return None
        for frame in ImageSequence.Iterator(image):
            duration = max(20, int(frame.info.get("duration", image.info.get("duration", 100)) or 100))
            if elapsed >= next_sample:
                prepared = _prepare_image_frame(frame.copy())
                frames.append(prepared)
                durations.append(sample_interval)
                next_sample += sample_interval
            elapsed += duration
            if elapsed >= max_duration:
                break

    if len(frames) < 2:
        return None

    destination = source.preview_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".webp", dir=destination.parent, delete=False) as temp_file:
        temp_path = Path(temp_file.name)
    try:
        frames[0].save(
            temp_path,
            format="WEBP",
            save_all=True,
            append_images=frames[1:],
            duration=durations,
            loop=0,
            quality=THUMBNAIL_QUALITY,
            method=4,
        )
        os.replace(temp_path, destination)
    finally:
        temp_path.unlink(missing_ok=True)
        for frame in frames:
            frame.close()
    return destination


def _generate_animated_video(source: ThumbnailSource) -> Path | None:
    ffmpeg = _ffmpeg_executable("ffmpeg")
    if not ffmpeg:
        return None
    duration = 3.0
    start = _video_start_time(source.source_path, duration)
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{start:.3f}",
        "-t",
        f"{duration:.1f}",
        "-i",
        str(source.source_path),
        "-vf",
        f"fps=8,scale={THUMBNAIL_SIZE}:{THUMBNAIL_SIZE}:force_original_aspect_ratio=decrease:force_divisible_by=2",
        "-an",
        "-loop",
        "0",
        "-c:v",
        "libwebp",
        "-quality",
        str(THUMBNAIL_QUALITY),
        "-compression_level",
        "4",
        "-preset",
        "picture",
        "-y",
        "__OUTPUT__",
    ]
    try:
        _run_ffmpeg(command, source.preview_path)
        return source.preview_path
    except (subprocess.SubprocessError, RuntimeError, OSError):
        return None


def ensure_animated_preview(source: ThumbnailSource) -> Path | None:
    if not source.supports_animated_preview:
        return None
    if source.preview_path.exists() and source.preview_path.stat().st_size > 0:
        return source.preview_path
    _remove_stale_variants(source, {source.static_path, source.preview_path})
    if source.media_type == "video":
        return _generate_animated_video(source)
    try:
        return _generate_animated_image(source)
    except Exception:
        return None


def _iter_gallery_sources() -> Iterable[ThumbnailSource]:
    root = _gallery_root()
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT id, relative_path, media_type, extension
            FROM files
            WHERE is_trashed = 0
            ORDER BY id
            """
        ).fetchall()
    for row in rows:
        source_path = (root / str(row["relative_path"])).resolve()
        if not source_path.exists() or not source_path.is_file():
            continue
        try:
            yield _source_from_file(
                namespace="gallery",
                identifier=str(row["id"]),
                source_path=source_path,
                media_type=str(row["media_type"]),
                extension=str(row["extension"]),
            )
        except OSError:
            continue


def _iter_todo_sources() -> Iterable[ThumbnailSource]:
    for item in list_todo_files()["files"]:
        try:
            yield get_todo_source(str(item["relative_path"]))
        except (OSError, ValueError, PermissionError):
            continue


def _iter_trash_sources() -> Iterable[ThumbnailSource]:
    with get_connection() as connection:
        rows = connection.execute("SELECT id FROM trash_items ORDER BY id").fetchall()
    for row in rows:
        try:
            yield get_trash_source(int(row["id"]))
        except (OSError, ValueError, PermissionError):
            continue


def iter_all_sources() -> Iterable[ThumbnailSource]:
    yield from _iter_gallery_sources()
    yield from _iter_todo_sources()
    yield from _iter_trash_sources()


def cache_stats() -> dict[str, Any]:
    files = [path for path in CACHE_ROOT.rglob("*.webp") if path.is_file()] if CACHE_ROOT.exists() else []
    total_size = sum(path.stat().st_size for path in files if path.exists())
    previews = sum(1 for path in files if path.name.endswith(PREVIEW_SUFFIX))
    return {
        "cache_path": str(CACHE_ROOT),
        "files": len(files),
        "static_thumbnails": len(files) - previews,
        "animated_previews": previews,
        "size": total_size,
        "thumbnail_size": THUMBNAIL_SIZE,
        "quality": THUMBNAIL_QUALITY,
        "ffmpeg_available": ffmpeg_available(),
    }


def clean_unused_cache() -> dict[str, Any]:
    expected: set[Path] = set()
    for source in iter_all_sources():
        expected.add(source.static_path.resolve())
        if source.supports_animated_preview:
            expected.add(source.preview_path.resolve())

    removed = 0
    freed = 0
    if CACHE_ROOT.exists():
        for path in CACHE_ROOT.rglob("*.webp"):
            if not path.is_file() or path.resolve() in expected:
                continue
            try:
                freed += path.stat().st_size
                path.unlink()
                removed += 1
            except OSError:
                continue
        _remove_empty_cache_directories()
    return {"removed": removed, "freed": freed, **cache_stats()}


def _remove_empty_cache_directories() -> None:
    if not CACHE_ROOT.exists():
        return
    for folder in sorted((p for p in CACHE_ROOT.rglob("*") if p.is_dir()), reverse=True):
        try:
            folder.rmdir()
        except OSError:
            pass


def clear_cache() -> dict[str, Any]:
    previous = cache_stats()
    if CACHE_ROOT.exists():
        shutil.rmtree(CACHE_ROOT)
    CACHE_ROOT.mkdir(parents=True, exist_ok=True)
    return {
        "removed": previous["files"],
        "freed": previous["size"],
        **cache_stats(),
    }


def regenerate_cache() -> dict[str, Any]:
    clear_cache()
    generated = 0
    previews = 0
    errors: list[dict[str, str]] = []
    for source in iter_all_sources():
        try:
            ensure_static_thumbnail(source)
            generated += 1
            if source.supports_animated_preview and ensure_animated_preview(source):
                previews += 1
        except Exception as error:
            errors.append({"path": str(source.source_path), "error": str(error)})
    return {
        "generated": generated,
        "animated_previews_generated": previews,
        "errors": errors,
        **cache_stats(),
    }
