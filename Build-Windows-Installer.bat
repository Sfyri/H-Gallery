@echo off
setlocal
cd /d "%~dp0"

echo H-Gallery - Creazione installer Windows
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0packaging\windows\build_windows.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo La build non e' stata completata. Controlla il messaggio sopra.
) else (
    echo Operazione completata.
)
echo.
pause
exit /b %EXIT_CODE%
