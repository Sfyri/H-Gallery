# H-Gallery

Galleria locale per organizzare immagini, GIF e video per serie, personaggi, tag e artisti. I file restano sul computer e l’interfaccia Windows usa `127.0.0.1`.

## Funzioni principali

- area **New** collegata a `.toDo`;
- serie, personaggi, alias, tag, artisti e contenuti IA;
- raccolte `!Multiple`, `!Crossovers` e storie/manga;
- ricerca, filtri, classifica e cestino interno;
- miniature, anteprime animate, backup e ripristino;
- più gallerie indipendenti;
- launcher Windows senza terminale;
- app Android con gallerie locali;
- associazione sicura Windows ↔ Android sulla rete locale;
- sincronizzazione bidirezionale di media, metadata ed eliminazioni;
- retry e ripresa sicura dopo interruzioni.

## Installazione Windows

1. Scarica `H-Gallery-Setup-<versione>.exe` dalla pagina Releases.
2. Installa e avvia H-Gallery dal menu Start.
3. Crea una nuova galleria oppure selezionane una esistente.

La galleria rimane separata dal programma:

```text
E:\H-Gallery\
├── .user\
├── .toDo\
├── .trash\
└── cartelle delle serie\
```

Disinstallare H-Gallery non elimina la galleria.

L’installer configura anche le regole Windows Firewall necessarie alla comunicazione con l’app Android sulla rete locale. La sincronizzazione richiede che Windows e Android possano raggiungersi sulla stessa LAN/Wi-Fi.

## Android e sincronizzazione

La versione Android usa gallerie locali indipendenti che possono essere collegate esplicitamente a una galleria Windows tramite un gruppo di sincronizzazione.

Per collegare i dispositivi:

1. avvia H-Gallery su Windows;
2. collega PC e telefono alla stessa rete locale;
3. su Android apri **Collega PC**;
4. cerca il PC sulla rete e completa l’associazione;
5. collega la galleria Android alla galleria Windows desiderata;
6. usa **Sincronizza** per analizzare e applicare le differenze.

La sincronizzazione gestisce nuovi file, metadata, eliminazioni registrate da H-Gallery, collisioni, retry e ripresa dopo interruzioni. Le operazioni ambigue vengono bloccate invece di scegliere automaticamente una modifica potenzialmente distruttiva.

Durante lo sviluppo l’app Android può essere avviata da sorgente con:

```powershell
cd mobile
flutter run
```

## Primo utilizzo

1. Copia immagini e video in `.toDo`.
2. Apri **New**.
3. Seleziona i file e premi **Organizza**.
4. Assegna almeno un personaggio e conferma **Rinomina e sposta**.

## Aggiornamento dalla versione 1.x

1. Installa H-Gallery 2.
2. Seleziona la vecchia cartella principale della galleria.
3. Verifica immagini, storie e metadati.
4. Elimina la vecchia `.Script` solo dopo il controllo.

## Installazione da sorgente

Richiede Python 3.10 o successivo.

```text
Install.bat
H-Gallery.vbs
```

Sono supportati anche:

```powershell
pipx install "git+https://github.com/Sfyri/H-Gallery.git"
uv tool install "git+https://github.com/Sfyri/H-Gallery.git"
h-gallery launcher
```

Su Linux usa `h-gallery` da terminale; Wine non è necessario.

## Build dell’installer Windows

Installa Inno Setup 6, quindi esegui:

```text
Build-Windows-Installer.bat
```

L’installer viene creato in `dist\installer`.

## FFmpeg

Facoltativo. Serve soltanto per le anteprime animate dei video.

## Licenza

MIT. Consulta `LICENSE`.
