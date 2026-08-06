# H-Gallery

Galleria locale per organizzare, cercare e visualizzare raccolte di immagini e video suddivise per serie e personaggi.

Il programma lavora sul computer dell’utente tramite `127.0.0.1`. Non carica i file su servizi esterni.

> **Versione 2.0.0-alpha.4** — quarta fase della nuova struttura: aggiunti la build autonoma Windows e lo script Inno Setup per produrre un normale installer `H-Gallery-Setup.exe`.

## Funzioni principali

- galleria organizzata per serie e personaggi;
- area **New** collegata alla cartella `.toDo`;
- organizzazione singola o multipla;
- tag, artisti, alias e contenuti IA;
- gestione di `.AI`, `!Multiple` e `!Crossovers`;
- controllo dei duplicati identici tramite SHA-256;
- cestino interno `.trash`;
- miniature e anteprime animate;
- classifica dei personaggi;
- backup, ripristino ed esportazione JSON;
- storie e manga con copertina, ordine, lettore e modifica delle pagine;
- gestione di più gallerie indipendenti;
- launcher Windows in background con icona nell’area di notifica;
- build autonoma e installer Windows che non richiedono Python sul computer dell’utente.

## Struttura

Il programma e la galleria possono trovarsi in directory diverse.

### Programma

Esempio di installazione locale:

```text
D:\software\H-Gallery\.Script\
├── backend\
├── frontend\
├── .venv\
├── pyproject.toml
├── H-Gallery.vbs
├── Start.bat
└── Reconfigure.bat
```

Con `pipx` o `uv tool`, il programma viene installato nell’ambiente gestito dallo strumento e non deve restare dentro la galleria.

### Galleria

```text
E:\H-Gallery\
├── .user\
│   ├── config.json
│   ├── data\
│   └── backups\
├── .toDo\
├── .trash\
├── !Crossovers\
└── cartelle delle serie\
```

La cache ricostruibile viene salvata fuori dalla galleria. Su Windows si trova normalmente in `%LOCALAPPDATA%\H-Gallery\cache`.

L’elenco delle gallerie registrate viene salvato in `%APPDATA%\H-Gallery\galleries.json`.

## Aggiornamento dalla 2.0.0-alpha.3

Per aggiornare l'installazione locale usata per lo sviluppo:

1. arresta H-Gallery dall'icona nell'area di notifica;
2. copia i file dell'aggiornamento nella cartella del programma;
3. sostituisci i file esistenti;
4. esegui nuovamente `Install.bat`;
5. avvia `H-Gallery.vbs` e verifica la galleria attiva.

Questa fase aggiunge gli strumenti per creare l'installer, ma non obbliga a sostituire subito l'installazione locale funzionante.

## Installer Windows per l'utente finale

La distribuzione creata nella fase 4 installa H-Gallery come normale applicazione in:

```text
%LOCALAPPDATA%\Programs\H-Gallery
```

L'utente finale non deve installare Python, eseguire file `.bat` o mantenere il progetto sorgente. L'installer crea collegamenti nel menu Start e può creare facoltativamente un collegamento sul desktop.

L'installer e il disinstallatore non cancellano le gallerie, `.user`, `.toDo`, `.trash`, il registro delle gallerie, la cache o i log.

## Creare `H-Gallery-Setup.exe`

La compilazione deve essere eseguita su Windows. Servono:

- l'ambiente locale preparato con `Install.bat`;
- Inno Setup 6.

Dalla cartella del programma esegui:

```text
Build-Windows-Installer.bat
```

Lo script installa PyInstaller nell'ambiente locale, crea l'applicazione autonoma e poi compila l'installer. Il risultato viene salvato in:

```text
dist\installer\H-Gallery-Setup-2.0.0-alpha.4.exe
```

Prima della pubblicazione, prova l'installer su un computer o una macchina virtuale Windows che non abbia Python e non contenga la cartella sorgente di H-Gallery.

## Installazione locale su Windows

Richiede Python 3.10 o successivo.

1. estrai o clona il progetto in una cartella separata dalla galleria;
2. esegui `Install.bat`;
3. seleziona o crea una galleria se richiesto;
4. usa `H-Gallery.vbs` per gli avvii normali;
5. in alternativa usa `Start.bat`;
6. usa `Reconfigure.bat` oppure **Cambia galleria...** dall’icona nell’area di notifica.

## Launcher Windows

Dopo l’avvio compare un’icona di H-Gallery vicino all’orologio di Windows. Il relativo menu contiene:

- **Apri H-Gallery**;
- **Apri cartella della galleria**;
- **Cambia galleria...**;
- **Apri cartella dei log**;
- **Arresta H-Gallery**.

Un secondo avvio non crea un altro server: riapre nel browser l’istanza già attiva.

I log vengono salvati in:

```text
%LOCALAPPDATA%\H-Gallery\logs\h-gallery.log
```

Il file viene ruotato automaticamente per evitare una crescita illimitata.

## Installazione standard con pipx

Dalla cartella del progetto:

```powershell
pipx install .
h-gallery launcher
```

Direttamente dal repository GitHub:

```powershell
pipx install "git+https://github.com/Sfyri/H-Gallery.git"
h-gallery launcher
```

Aggiornamento da GitHub:

```powershell
pipx upgrade h-gallery
```

## Installazione standard con uv

Installazione persistente:

```powershell
uv tool install "git+https://github.com/Sfyri/H-Gallery.git"
h-gallery launcher
```

Aggiornamento:

```powershell
uv tool upgrade h-gallery
```

Esecuzione temporanea senza installazione permanente:

```powershell
uvx --from "git+https://github.com/Sfyri/H-Gallery.git" h-gallery
```

## Comando `h-gallery`

Avvio tradizionale in primo piano:

```powershell
h-gallery
h-gallery start
```

Avvio Windows in background:

```powershell
h-gallery launcher
```

Controllo del launcher:

```powershell
h-gallery open
h-gallery status
h-gallery stop
```

Opzioni del server tradizionale:

```powershell
h-gallery start --gallery "E:\H-Gallery"
h-gallery start --no-browser
h-gallery start --host 127.0.0.1 --port 8000
```

Gestione delle gallerie:

```powershell
h-gallery configure
h-gallery configure --gallery "E:\H-Gallery"
h-gallery configure --create "D:\Nuova Galleria"
h-gallery list
```

Versione installata:

```powershell
h-gallery --version
```

## Linux

Il pacchetto può essere installato nativamente con `pipx` o `uv tool`. Non è necessario Wine.

Esempio:

```bash
uv tool install "git+https://github.com/Sfyri/H-Gallery.git"
h-gallery
```

Su Linux il metodo principale rimane l’avvio da terminale. Il launcher con area di notifica di questa fase è rivolto a Windows.

Per evitare l’apertura automatica del browser:

```bash
h-gallery start --no-browser
```

Se l’ambiente Linux non dispone di Tk, la prima configurazione usa una procedura testuale nel terminale.

## Gestire più gallerie

Il gestore permette di:

- aggiungere una galleria esistente;
- creare una nuova galleria;
- scegliere quale usare al prossimo avvio;
- rimuovere una voce dall’elenco senza cancellare i file.

Esempio:

```text
E:\Galleria principale\
D:\Galleria test\
F:\Archivio vecchio\
```

Ogni galleria mantiene autonomamente `.user`, database, tag, artisti, storie, backup, `.toDo` e `.trash`.

Con il launcher Windows, usa **Cambia galleria...** dal menu dell’icona. Il server viene riavviato automaticamente soltanto se la galleria attiva cambia.

Con il comando installato:

```powershell
h-gallery configure
h-gallery launcher
```

## Primo utilizzo

H-Gallery non importa automaticamente i file trascinati nella finestra del browser.

1. copia o sposta immagini e video nella cartella `.toDo` della galleria attiva;
2. apri la sezione **New**;
3. seleziona uno o più file;
4. usa **Organizza** o **Organizza insieme**;
5. assegna almeno un personaggio e conferma **Rinomina e sposta**.

Quando non esistono file organizzati, la schermata principale mostra una guida iniziale e un pulsante per aprire **New**.

## Trasferimento su un altro computer

Copia l’intera cartella della galleria, inclusi:

- `.user`;
- `.toDo` e `.trash`;
- cartelle delle serie e file multimediali.

Sul nuovo computer installa H-Gallery e registra la cartella copiata con:

```powershell
h-gallery configure --gallery "E:\H-Gallery"
```

Il registro delle gallerie può essere ricreato: i dati importanti restano nella cartella della galleria.

## Sviluppo e build

Installazione modificabile:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --editable ".[dev]"
h-gallery --version
```

Creazione dei pacchetti `wheel` e `sdist`:

```powershell
python -m build
```

Creazione dell'installer Windows:

```text
Build-Windows-Installer.bat
```

I pacchetti Python e l'installer vengono creati nelle sottocartelle di `dist`. La documentazione specifica della build Windows è in `packaging/windows/README.md`.

## FFmpeg

FFmpeg è facoltativo. Senza FFmpeg la galleria funziona normalmente, ma i video non mostrano l’anteprima animata al passaggio del mouse.

```powershell
ffmpeg -version
```

## Sicurezza

- conserva una copia esterna delle immagini e dei video;
- crea periodicamente backup dall’applicazione;
- non cancellare `.user/data/gallery.db`;
- rimuovere una galleria dal gestore non elimina mai i suoi file;
- prima di eliminare una vecchia copia del programma, verifica che la nuova installazione apra correttamente la galleria;
- usa **Arresta H-Gallery** dall’icona prima di aggiornare i file del programma.

## Licenza

Distribuito con licenza MIT. Consulta `LICENSE`.
