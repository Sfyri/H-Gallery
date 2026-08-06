from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

PACKAGE_NAME = "h-gallery"
DISPLAY_VERSION = "2.0.0-alpha.6"
PACKAGE_VERSION = "2.0.0a6"


def get_package_version() -> str:
    """Restituisce la versione PEP 440 del pacchetto installato."""

    try:
        return version(PACKAGE_NAME)
    except PackageNotFoundError:
        return PACKAGE_VERSION


def get_display_version() -> str:
    """Restituisce la versione leggibile mostrata nell'interfaccia e nei backup."""

    root_version = Path(__file__).resolve().parent.parent / "VERSION.txt"
    try:
        value = root_version.read_text(encoding="utf-8").strip()
        if value:
            return value
    except OSError:
        pass
    return DISPLAY_VERSION
