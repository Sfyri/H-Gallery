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
echo Aggiornamento degli strumenti di installazione...
".venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
if errorlevel 1 goto installation_error

echo.
echo Installazione del pacchetto H-Gallery...
".venv\Scripts\python.exe" -m pip install --editable .
if errorlevel 1 goto installation_error

echo.
echo Configurazione della galleria...
".venv\Scripts\h-gallery.exe" configure --ensure
if errorlevel 1 goto installation_error

echo.
echo ========================================
echo Installazione completata.
echo Avvia il programma con H-Gallery.vbs oppure Start.bat.
echo ========================================
echo.
pause
exit /b 0

:installation_error
echo.
echo Installazione non riuscita.
pause
exit /b 1
