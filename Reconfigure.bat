@echo off
setlocal
cd /d "%~dp0"
title Configurazione Galleria HDD

if not exist ".venv\Scripts\python.exe" (
    echo Il programma non e' installato. Avvia prima Install.bat.
    pause
    exit /b 1
)

".venv\Scripts\python.exe" configure.py
pause
