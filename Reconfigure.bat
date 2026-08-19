@echo off
setlocal
cd /d "%~dp0"
title Gestione gallerie H-Gallery

if not exist ".venv\Scripts\python.exe" (
    echo Il pacchetto non e' installato. Avvia prima Install.bat.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" -m h_gallery_cli configure
if errorlevel 1 pause
