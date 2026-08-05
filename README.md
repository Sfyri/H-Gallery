# H-Gallery

Galleria locale per organizzare, cercare e visualizzare raccolte di immagini e video suddivise per serie e personaggi.

Il programma lavora esclusivamente sul computer dell'utente tramite `127.0.0.1`. Non carica i file su servizi esterni.

## Funzioni principali

- galleria organizzata per serie e personaggi;
- area **New** collegata alla cartella fisica `.toDo`;
- ricerca e selezione di uno o più personaggi;
- tag personalizzati e tag automatico `AI`;
- gestione di `.AI`, `!Multiple` e `!Crossovers`;
- controllo dei duplicati identici tramite SHA-256;
- cestino interno `.trash` con ripristino;
- miniature WebP e anteprime animate per GIF e video;
- classifica dei personaggi con punteggi `+1` e `-1`;
- backup, ripristino ed esportazione JSON;
- codici delle serie generati automaticamente.

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

Se un codice è già occupato, viene aggiunto il primo suffisso disponibile:

```text
SM
SM01
SM02
```

I codici già presenti nel database non vengono modificati automaticamente.

## Requisiti

- Windows 10 o Windows 11;
- Python 3.10 o successivo;
- FFmpeg facoltativo, necessario solo per le anteprime animate dei video.

## Installazione rapida

1. Scarica il repository o una Release e decomprimilo.
2. Avvia `Install.bat`.
3. Inserisci il percorso della tua galleria quando richiesto.
4. Avvia `Start.bat`.

Per gli avvii successivi è sufficiente usare `Start.bat`.

## Struttura consigliata della galleria

Il programma può trovarsi in una cartella diversa dall'archivio multimediale.

```text
C:\Applicazioni\H-Gallery\
    backend\
    frontend\
    Start.bat
    ...

E:\ArchivioPersonaggi\
    .toDo\
    .trash\
    !Crossovers\
    Fire Emblem\
        !Multiple\
        Charlotte\
        Lucina\
    Pokémon\
        !Multiple\
        Misty\
```

Il percorso effettivo viene salvato localmente in `config.json` e può essere diverso per ogni utente.

## Riconfigurare il percorso

Avvia `Reconfigure.bat` e conferma la sostituzione della configurazione.

Dopo aver cambiato archivio, usa nell'applicazione:

1. **Rileggi cartelle**;
2. **Sincronizza archivio**.

## File locali non pubblicati su GitHub

Questi elementi vengono creati sul computer dell'utente e sono esclusi da Git tramite `.gitignore`:

```text
config.json
.venv\
data\
cache\
backups\
```

- `config.json`: percorso e nomi delle cartelle speciali;
- `data/gallery.db`: tag, associazioni, punteggi e metadati;
- `cache/`: miniature rigenerabili;
- `backups/`: copie di sicurezza locali.

`config.example.json` è soltanto il modello pubblico usato per creare `config.json`.

## Avvio manuale per lo sviluppo

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python configure.py
fastapi dev main.py
```

Poi apri:

```text
http://127.0.0.1:8000
```

## FFmpeg

FFmpeg è facoltativo. Senza FFmpeg la galleria funziona normalmente, ma i video non mostrano l'anteprima animata al passaggio del mouse.

Per verificare l'installazione:

```powershell
ffmpeg -version
```

## Sicurezza

Prima di usare il programma su un archivio importante:

- conserva una copia esterna delle immagini e dei video;
- crea periodicamente backup dall'applicazione;
- non pubblicare `config.json`, `gallery.db` o la cartella `backups`.

## Licenza

Distribuito con licenza MIT. Consulta `LICENSE`.
