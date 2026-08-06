# Build dell'installer Windows

Questa cartella contiene la configurazione per creare la distribuzione Windows di H-Gallery.

## Requisiti

- Windows 10 o 11 a 64 bit;
- ambiente `.venv` preparato tramite `Install.bat`;
- Inno Setup 6 installato.

## Creazione

Dalla radice del progetto esegui:

```text
Build-Windows-Installer.bat
```

Lo script:

1. installa o aggiorna PyInstaller nell'ambiente locale;
2. genera icona e metadati partendo da `VERSION.txt`;
3. crea la distribuzione `onedir` con PyInstaller;
4. compila l'installer con Inno Setup.

Il risultato viene salvato in:

```text
dist\installer\H-Gallery-Setup-<versione>.exe
```

## File persistenti

L'installer installa soltanto il programma in `%LOCALAPPDATA%\Programs\H-Gallery`.

Non modifica e non elimina:

- le cartelle delle gallerie;
- `.user`, `.toDo` e `.trash`;
- il registro delle gallerie in `%APPDATA%\H-Gallery`;
- cache e log in `%LOCALAPPDATA%\H-Gallery`.

Anche la disinstallazione lascia intatti questi dati.
