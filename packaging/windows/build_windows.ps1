[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Python = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
$SpecFile = Join-Path $PSScriptRoot "h_gallery.spec"
$InstallerScript = Join-Path $PSScriptRoot "installer.iss"
$WorkDir = Join-Path $ProjectRoot "build\windows"
$DistRoot = Join-Path $ProjectRoot "dist"
$BundleDir = Join-Path $DistRoot "windows\H-Gallery"
$InstallerDir = Join-Path $DistRoot "installer"

function Find-InnoCompiler {
    $command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }

    $firstCandidate = @($candidates) | Select-Object -First 1
    if ($firstCandidate) { return [string]$firstCandidate }
    throw "Inno Setup 6 non trovato. Installalo e riesegui Build-Windows-Installer.bat."
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "La build dell'installer Windows deve essere eseguita su Windows."
}
if (-not (Test-Path $Python)) {
    throw "Ambiente Python non trovato. Esegui prima Install.bat nella cartella del progetto."
}

Write-Host "[1/6] Verifica di Inno Setup..."
$Iscc = Find-InnoCompiler
Write-Host "      $Iscc"

Write-Host "[2/6] Installazione degli strumenti di build..."
& $Python -m pip install --disable-pip-version-check --upgrade "pyinstaller>=6.11,<7"
if ($LASTEXITCODE -ne 0) { throw "Installazione di PyInstaller non riuscita." }

Write-Host "[3/6] Generazione di versione e icona..."
& $Python (Join-Path $PSScriptRoot "generate_build_metadata.py") --project-root $ProjectRoot --output $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "Generazione dei metadati non riuscita." }

Write-Host "[4/6] Pulizia delle build precedenti..."
Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $DistRoot "windows") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $InstallerDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item $WorkDir -ItemType Directory -Force | Out-Null
New-Item $InstallerDir -ItemType Directory -Force | Out-Null

Write-Host "[5/6] Creazione dell'applicazione Windows..."
Push-Location $ProjectRoot
try {
    & $Python -m PyInstaller --noconfirm --clean --workpath $WorkDir --distpath (Join-Path $DistRoot "windows") $SpecFile
    if ($LASTEXITCODE -ne 0) { throw "Build PyInstaller non riuscita." }
}
finally {
    Pop-Location
}
if (-not (Test-Path (Join-Path $BundleDir "H-Gallery.exe"))) {
    throw "H-Gallery.exe non è stato generato."
}

Write-Host "[6/6] Creazione dell'installer..."
& $Iscc "/DSourceDir=$BundleDir" "/DOutputDir=$InstallerDir" $InstallerScript
if ($LASTEXITCODE -ne 0) { throw "Compilazione Inno Setup non riuscita." }

$Version = (Get-Content (Join-Path $ProjectRoot "VERSION.txt") -Raw).Trim()
$Installer = Join-Path $InstallerDir "H-Gallery-Setup-$Version.exe"
if (-not (Test-Path $Installer)) {
    throw "Installer atteso non trovato: $Installer"
}

Write-Host ""
Write-Host "Build completata:" -ForegroundColor Green
Write-Host "  $Installer"
Write-Host ""
Write-Host "Prima di pubblicarlo, provalo su un PC o una macchina virtuale Windows pulita."
