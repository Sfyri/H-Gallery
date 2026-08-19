from __future__ import annotations

import argparse
import re
from pathlib import Path

from PIL import Image


VERSION_PATTERN = re.compile(
    r"^(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)"
    r"(?:-(?P<label>alpha|beta|rc)\.(?P<serial>\d+))?$",
    re.IGNORECASE,
)


def parse_version(value: str) -> tuple[str, tuple[int, int, int, int]]:
    display = value.strip()
    match = VERSION_PATTERN.fullmatch(display)
    if match is None:
        raise ValueError(
            "VERSION.txt deve usare un formato come 2.0.0, 2.0.0-alpha.4, "
            "2.0.0-beta.1 oppure 2.0.0-rc.1."
        )
    numeric = (
        int(match.group("major")),
        int(match.group("minor")),
        int(match.group("patch")),
        int(match.group("serial") or 0),
    )
    return display, numeric


def escape_version_text(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def write_pyinstaller_version(path: Path, display: str, numeric: tuple[int, int, int, int]) -> None:
    text = escape_version_text(display)
    tuple_text = ", ".join(str(part) for part in numeric)
    content = f"""VSVersionInfo(
  ffi=FixedFileInfo(
    filevers=({tuple_text}),
    prodvers=({tuple_text}),
    mask=0x3f,
    flags=0x0,
    OS=0x40004,
    fileType=0x1,
    subtype=0x0,
    date=(0, 0)
  ),
  kids=[
    StringFileInfo([
      StringTable(
        '040904B0',
        [StringStruct('CompanyName', 'Sfyri'),
         StringStruct('FileDescription', 'H-Gallery'),
         StringStruct('FileVersion', '{text}'),
         StringStruct('InternalName', 'H-Gallery'),
         StringStruct('LegalCopyright', 'Copyright (c) Sfyri'),
         StringStruct('OriginalFilename', 'H-Gallery.exe'),
         StringStruct('ProductName', 'H-Gallery'),
         StringStruct('ProductVersion', '{text}')])
    ]),
    VarFileInfo([VarStruct('Translation', [1033, 1200])])
  ]
)
"""
    path.write_text(content, encoding="utf-8")


def write_inno_version(path: Path, display: str, numeric: tuple[int, int, int, int]) -> None:
    numeric_text = ".".join(str(part) for part in numeric)
    path.write_text(
        f'#define MyAppVersion "{display}"\n'
        f'#define MyAppVersionInfo "{numeric_text}"\n',
        encoding="utf-8",
    )


def write_icon(path: Path, source: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(f"Icona sorgente non trovata: {source}")

    image = Image.open(source).convert("RGBA")

    if image.size != (1024, 1024):
        raise ValueError(
            f"L'icona sorgente deve essere 1024x1024, trovata {image.size[0]}x{image.size[1]}"
        )

    path.parent.mkdir(parents=True, exist_ok=True)

    image.save(
        path,
        format="ICO",
        sizes=[
            (16, 16),
            (24, 24),
            (32, 32),
            (48, 48),
            (64, 64),
            (128, 128),
            (256, 256),
        ],
    )

def main() -> int:
    parser = argparse.ArgumentParser(description="Genera i metadati della build Windows.")
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    display, numeric = parse_version(
        (project_root / "VERSION.txt").read_text(encoding="utf-8")
    )
    write_pyinstaller_version(output / "version_info.txt", display, numeric)
    write_inno_version(output / "version.iss", display, numeric)
    write_icon(
        output / "assets" / "h-gallery.ico",
        project_root / "assets" / "icons" / "hgallery_icon_master.png",
    )
    print(f"Metadati Windows generati per H-Gallery {display}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
