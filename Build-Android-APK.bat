@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo H-Gallery - Build APK Android Release
echo ============================================
echo.

if not exist "mobile\pubspec.yaml" (
    echo ERRORE: cartella mobile non trovata.
    echo Metti questo BAT nella cartella principale del progetto H-Gallery.
    echo.
    pause
    exit /b 1
)

where flutter >nul 2>nul
if errorlevel 1 (
    echo ERRORE: Flutter non e' disponibile nel PATH.
    echo.
    pause
    exit /b 1
)

cd /d "%~dp0mobile"

echo [1/2] Aggiornamento dipendenze...
call flutter pub get
if errorlevel 1 goto :error

echo.
echo [2/2] Compilazione APK release...
call flutter build apk --release
if errorlevel 1 goto :error

set "APK=%CD%\build\app\outputs\flutter-apk\app-release.apk"

if not exist "%APK%" (
    echo.
    echo ERRORE: APK non trovato dopo la build.
    goto :error
)

echo.
echo ============================================
echo BUILD COMPLETATA
echo ============================================
echo APK:
echo %APK%
echo.
explorer /select,"%APK%"
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
