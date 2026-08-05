@echo off
setlocal
cd /d "%~dp0"
title Installazione H-Gallery

echo ========================================
echo       INSTALLAZIONE H-Gallery
echo ========================================
echo.

where python >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON=python"
) else (
    where py >nul 2>nul
    if errorlevel 1 (
        echo Python non e' installato oppure non e' nel PATH.
        echo Installa Python 3.10 o successivo e riprova.
        echo.
        pause
        exit /b 1
    )
    set "PYTHON=py -3"
)

%PYTHON% -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)"
if errorlevel 1 (
    echo E' necessario Python 3.10 o successivo.
    pause
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo Creazione dell'ambiente virtuale...
    %PYTHON% -m venv .venv
    if errorlevel 1 goto installation_error
)

echo.
echo Installazione delle dipendenze...
".venv\Scripts\python.exe" -m pip install --upgrade pip
if errorlevel 1 goto installation_error

".venv\Scripts\python.exe" -m pip install -r requirements.txt
if errorlevel 1 goto installation_error

if not exist "config.json" (
    echo.
    echo Configurazione iniziale...
    ".venv\Scripts\python.exe" configure.py
    if errorlevel 1 goto installation_error
)

echo.
echo ========================================
echo Installazione completata.
echo Avvia il programma con Start.bat.
echo ========================================
echo.
pause
exit /b 0

:installation_error
echo.
echo Installazione non riuscita.
pause
exit /b 1
