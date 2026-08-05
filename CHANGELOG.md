# Changelog

## 1.2.0

- Radice della galleria rilevata automaticamente come cartella padre di `.Script`.
- Rimosso il percorso assoluto `gallery_root` da `config.json`.
- Nuova cartella portabile `.user` nella radice della galleria.
- Database spostato in `.user/data/gallery.db`.
- Backup ed esportazioni spostati in `.user/backups`.
- Cache mantenuta in `.Script/cache` perché ricostruibile.
- Migrazione automatica e non distruttiva da `.Script/data` e `.Script/backups`.
- L'intera cartella H-Gallery può essere rinominata o spostata senza riconfigurazione.

## 1.1.0

- selezione multipla dei file nella sezione **New**;
- organizzazione collettiva con personaggi, tag comuni e stato IA;
- selezione di intervalli tramite `Shift + clic`;
- comandi **Seleziona tutto**, **Deseleziona** e spostamento multiplo nel cestino;
- gestione separata di duplicati ed errori senza bloccare l’intero gruppo;
- backup automatico prima delle organizzazioni multiple.

## 1.0.1

- eliminazione automatica delle cartelle vuote di serie e personaggi;
- conservazione dei dati necessari quando i file si trovano nel cestino;
- rimozione dal database di serie e personaggi senza file attivi o cestinati;
- cartelle e raccolte vuote nascoste nella galleria;
- pulizia automatica dopo organizzazione, spostamenti, cestino e sincronizzazione.

## 0.9.0

- codici automatici basati sulle iniziali o sulle prime quattro consonanti;
- risoluzione automatica delle collisioni con suffissi `01`, `02`, `03`;
- configurazione generica senza percorsi personali;
- aggiunti `Install.bat`, `Start.bat`, `Reconfigure.bat` e `configure.py`;
- aggiunti `.gitignore`, `.gitattributes`, `README.md` e licenza MIT;
- programma utilizzabile anche quando il repository si trova fuori dalla galleria;
- nessuna modifica retroattiva ai codici già salvati.

## 0.8.0

- backup manuali e automatici;
- ripristino controllato;
- esportazione dei metadati in JSON.

## 0.7.0

- miniature e cache;
- anteprime animate;
- sezione Impostazioni.

## 0.6.0

- cestino interno `.trash`;
- ripristino ed eliminazione definitiva;
- `.toDo` mostrata come **New** nell'interfaccia.
