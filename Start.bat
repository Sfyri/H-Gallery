@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Installazione del pacchetto non trovata. Avvio Install.bat...
    call Install.bat
    if errorlevel 1 exit /b 1
)

".venv\Scripts\python.exe" -m h_gallery_cli launcher
if errorlevel 1 (
    echo.
    echo Il launcher non e' riuscito ad avviarsi.
    echo Controlla i log in %%LOCALAPPDATA%%\H-Gallery\logs.
    pause
    exit /b 1
)
exit /b 0
