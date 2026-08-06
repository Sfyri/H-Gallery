@echo off
setlocal
cd /d "%~dp0"
title Gestione gallerie H-Gallery

if not exist ".venv\Scripts\h-gallery.exe" (
    echo Il pacchetto non e' installato. Avvia prima Install.bat.
    pause
    exit /b 1
)

".venv\Scripts\h-gallery.exe" configure
if errorlevel 1 pause
