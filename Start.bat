@echo off
setlocal
cd /d "%~dp0"
title H-Gallery

if not exist ".venv\Scripts\python.exe" (
    echo Installazione locale non trovata. Avvio Install.bat...
    call Install.bat
    if errorlevel 1 exit /b 1
)

if not exist "config.json" (
    echo Configurazione mancante.
    ".venv\Scripts\python.exe" configure.py
    if errorlevel 1 (
        pause
        exit /b 1
    )
)

start "" powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process 'http://127.0.0.1:8000'"

".venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000

if errorlevel 1 (
    echo.
    echo Il server si e' arrestato a causa di un errore.
    pause
)
