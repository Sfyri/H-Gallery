# H-Gallery

## Requisiti

- Windows 10 o Windows 11
- Python 3.10 o successivo
- FFmpeg facoltativo, necessario solo per le anteprime animate dei video

## Installazione

1. Crea o scegli la cartella principale che conterrà la galleria.
2. Scarica il repository come ZIP oppure clonalo.
3. Inserisci tutto il progetto in una sottocartella chiamata `.Script`.

La struttura iniziale deve essere:

```text
H-Gallery/
└── .Script/
    ├── backend/
    ├── frontend/
    ├── Install.bat
    ├── Start.bat
    └── ...
```

4. Avvia:

```text
.Script/Install.bat
```

L'installazione crea automaticamente l'ambiente Python e le cartelle necessarie.

5. Al termine, avvia:

```text
.Script/Start.bat
```

6. H-Gallery si apre nel browser all'indirizzo:

```text
http://127.0.0.1:8000
```

## Avvii successivi

Per avviare nuovamente H-Gallery è sufficiente eseguire:

```text
.Script/Start.bat
```

Per arrestare il programma, chiudi la finestra del terminale oppure premi `Ctrl + C`.

## Struttura generata

Dopo il primo avvio, la struttura sarà simile a questa:

```text
H-Gallery/
├── .Script/
├── .user/
│   ├── data/
│   └── backups/
├── .toDo/
├── .trash/
└── cartelle delle serie/
```

`.Script` deve restare direttamente dentro la cartella principale della galleria.

## Trasferimento su un altro computer

1. Copia `.user`, `.toDo`, `.trash` e tutte le cartelle contenenti immagini e video.
2. Scarica nuovamente il repository dentro una sottocartella chiamata `.Script`.
3. Avvia `.Script/Install.bat`.
4. Avvia `.Script/Start.bat`.

La cartella `.Script/cache` non è indispensabile e può essere rigenerata.

## FFmpeg facoltativo

Per verificare se FFmpeg è disponibile:

```powershell
ffmpeg -version
```

Senza FFmpeg il programma funziona comunque; mancano soltanto le anteprime animate dei video.

La IA è stata utilizzata per la realizzazione di questo Programma.