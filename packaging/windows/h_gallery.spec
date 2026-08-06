# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

from PyInstaller.utils.hooks import collect_submodules


SPEC_ROOT = Path(SPECPATH).resolve()
PROJECT_ROOT = SPEC_ROOT.parents[1]
ICON_PATH = SPEC_ROOT / "assets" / "h-gallery.ico"
VERSION_PATH = SPEC_ROOT / "version_info.txt"

hidden_imports = collect_submodules("uvicorn")
hidden_imports += [
    "pystray._win32",
]

analysis = Analysis(
    [str(PROJECT_ROOT / "h_gallery_launcher.py")],
    pathex=[str(PROJECT_ROOT)],
    binaries=[],
    datas=[
        (str(PROJECT_ROOT / "frontend"), "frontend"),
        (str(PROJECT_ROOT / "backend" / "resources"), "backend/resources"),
        (str(PROJECT_ROOT / "VERSION.txt"), "."),
    ],
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(analysis.pure)

executable = EXE(
    pyz,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name="H-Gallery",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(ICON_PATH),
    version=str(VERSION_PATH),
)

bundle = COLLECT(
    executable,
    analysis.binaries,
    analysis.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="H-Gallery",
)
