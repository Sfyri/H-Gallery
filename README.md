# H-Gallery

Galleria locale per organizzare, cercare e visualizzare raccolte di immagini e video suddivise per serie e personaggi.

Il programma lavora esclusivamente sul computer dell'utente tramite `127.0.0.1`. Non carica i file su servizi esterni.

## Funzioni principali

- galleria organizzata per serie e personaggi;
- area **New** collegata alla cartella fisica `.toDo`;
- organizzazione singola o multipla dei nuovi file;
- ricerca e selezione di uno o più personaggi;
- tag personalizzati e tag automatico `AI`;
- gestione di `.AI`, `!Multiple` e `!Crossovers`;
- controllo dei duplicati identici tramite SHA-256;
- cestino interno `.trash` con ripristino;
- miniature WebP e anteprime animate per GIF e video;
- classifica dei personaggi con punteggi `+1` e `-1`;
- backup, ripristino ed esportazione JSON;
- codici delle serie generati automaticamente;
- pulizia automatica delle cartelle vuote.

## Struttura obbligatoria e portabile

`.Script` deve trovarsi direttamente nella radice della galleria. H-Gallery usa sempre la cartella padre di `.Script`, quindi non salva più un percorso assoluto.

```text
H-Gallery/
├── .Script/             # codice, repository Git, ambiente Python e cache
│   ├── backend/
│   ├── frontend/
│   ├── cache/           # miniature ricostruibili
│   ├── config.json
│   └── Start.bat
├── .user/
│   ├── data/            # database, tag, associazioni e punteggi
│   └── backups/         # backup ed esportazioni
├── .toDo/
├── .trash/
├── !Crossovers/
└── cartelle delle serie/
```

La cartella principale può essere rinominata, spostata o trasferita su un'altra unità senza cambiare `config.json`, purché `.Script` resti direttamente al suo interno.

## Installazione rapida

1. Crea o scegli la cartella principale della galleria.
2. Estrai o clona il repository dentro una sottocartella chiamata `.Script`.
3. Avvia `.Script/Install.bat`.
4. Avvia `.Script/Start.bat`.

`Install.bat` rileva automaticamente la cartella padre, crea `.user`, `.toDo`, `.trash` e la configurazione locale.

Per gli avvii successivi è sufficiente usare `Start.bat`.

## Trasferimento su un altro computer

Conserva:

- `.user`;
- `.toDo` e `.trash`;
- tutte le cartelle delle serie e i file multimediali.

`.Script` può essere riscaricata dal repository. La cache in `.Script/cache` è facoltativa e può essere rigenerata.

Dopo aver scaricato nuovamente il repository dentro `.Script`, esegui `Install.bat` e poi `Start.bat`.

## Migrazione dalle versioni precedenti

Al primo avvio vengono spostati automaticamente:

```text
.Script/data      → .user/data
.Script/backups   → .user/backups
```

La cache resta in `.Script/cache`. `gallery_root`, se presente nel vecchio `config.json`, viene rimosso automaticamente senza alterare le altre impostazioni.

## Codici automatici delle serie

Per una serie composta da più parole vengono usate le iniziali:

```text
The Legend of Zelda → TLOZ
Super Mario         → SM
Fire Emblem         → FE
```

Per una serie composta da una sola parola vengono usate le prime quattro consonanti:

```text
Konosuba → KNSB
Pokémon  → PKMN
Metroid  → MTRD
```

Se un codice è già occupato, viene aggiunto il primo suffisso disponibile: `SM`, `SM01`, `SM02`.

I codici già presenti nel database non vengono modificati automaticamente.

## Requisiti

- Windows 10 o Windows 11;
- Python 3.10 o successivo;
- FFmpeg facoltativo, necessario solo per le anteprime animate dei video.

## File locali non pubblicati su GitHub

Questi elementi sono locali:

```text
config.json
.venv/
cache/
```

`data` e `backups` non si trovano nel repository: sono conservati nella cartella sorella `.user`.

`config.example.json` è il modello pubblico usato per creare o aggiornare `config.json`.

## Configurazione

`config.json` contiene solo i nomi delle cartelle speciali e altre preferenze. Non contiene il percorso della galleria.

`Reconfigure.bat` aggiorna la configurazione usando i valori disponibili senza chiedere una directory.

## Avvio manuale per lo sviluppo

Da `.Script`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python configure.py
fastapi dev main.py
```

Poi apri `http://127.0.0.1:8000`.

## FFmpeg

FFmpeg è facoltativo. Senza FFmpeg la galleria funziona normalmente, ma i video non mostrano l'anteprima animata al passaggio del mouse.

```powershell
ffmpeg -version
```

## Sicurezza

- conserva una copia esterna delle immagini e dei video;
- crea periodicamente backup dall'applicazione;
- durante un trasferimento non dimenticare `.user/data/gallery.db`;
- non pubblicare `config.json`, `.user`, `.venv` o la cache.

## Licenza

Distribuito con licenza MIT. Consulta `LICENSE`.
