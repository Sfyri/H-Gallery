@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo H-Gallery - Build EXE Windows
echo ============================================
echo.

set "ROOT=%~dp0"
set "PYTHON=%ROOT%.venv\Scripts\python.exe"
set "PACKAGING=%ROOT%packaging\windows"
set "WORK=%ROOT%build\windows"
set "DIST=%ROOT%dist\windows"
set "EXE=%DIST%\H-Gallery\H-Gallery.exe"

if not exist "%PYTHON%" (
    echo ERRORE: ambiente Python .venv non trovato.
    echo Esegui prima Install.bat nella cartella del progetto.
    echo.
    pause
    exit /b 1
)

if not exist "%PACKAGING%\h_gallery.spec" (
    echo ERRORE: packaging\windows\h_gallery.spec non trovato.
    echo Metti questo BAT nella cartella principale del progetto H-Gallery.
    echo.
    pause
    exit /b 1
)

echo [1/4] Verifica PyInstaller...
"%PYTHON%" -m pip install --disable-pip-version-check --upgrade "pyinstaller>=6.11,<7"
if errorlevel 1 goto :error

echo.
echo [2/4] Generazione versione e icona...
"%PYTHON%" "%PACKAGING%\generate_build_metadata.py" --project-root "%ROOT%" --output "%PACKAGING%"
if errorlevel 1 goto :error

echo.
echo [3/4] Pulizia build Windows precedente...
if exist "%WORK%" rmdir /s /q "%WORK%"
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%WORK%" >nul 2>nul

echo.
echo [4/4] Compilazione H-Gallery.exe...
pushd "%ROOT%"
"%PYTHON%" -m PyInstaller --noconfirm --clean --workpath "%WORK%" --distpath "%DIST%" "%PACKAGING%\h_gallery.spec"
set "BUILD_EXIT=%ERRORLEVEL%"
popd

if not "%BUILD_EXIT%"=="0" goto :error

if not exist "%EXE%" (
    echo.
    echo ERRORE: H-Gallery.exe non e' stato generato.
    goto :error
)

echo.
echo ============================================
echo BUILD COMPLETATA
echo ============================================
echo EXE:
echo %EXE%
echo.
explorer /select,"%EXE%"
pause
exit /b 0

:error
echo.
echo ============================================
echo BUILD FALLITA
echo ============================================
echo Controlla gli errori mostrati sopra.
echo.
pause
exit /b 1
