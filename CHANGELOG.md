# Changelog

## 1.5.0

- Aggiunta la creazione di storie e manga da New e dalla galleria.
- Riordino delle pagine tramite trascinamento o numero progressivo.
- Aggiunti inversione dell’ordine e scelta della copertina.
- Titolo, personaggi, tag, artista, IA e direzione di lettura per ogni storia.
- Cartelle automatiche `!Stories` per personaggi, `!Multiple` e `!Crossovers`.
- Rinomina automatica delle pagine con numerazione a tre cifre.
- Lettore integrato a pagina singola o scorrimento verticale.
- Modifica successiva dell’ordine e dei metadati.
- Comando Sciogli storia che conserva le immagini e le riporta nella galleria normale.
- Ricerca globale e filtri estesi alle storie.
- Backup ed esportazione JSON estesi alle nuove tabelle delle storie.

## 1.4.0

- Aggiunti tre tipi di tag con colori distinti: generali arancioni, artisti viola e AI verde.
- Aggiunto il campo Artista facoltativo nell'organizzazione singola e multipla e nella modifica dei file.
- I nomi degli artisti già salvati vengono suggeriti automaticamente.
- Un tag generale inserito come artista viene convertito senza perdere le associazioni esistenti.
- Aggiunti alias multipli ai personaggi, ricercabili senza modificare cartelle o nomi dei file.
- Gli alias possono essere inseriti durante la creazione e modificati dalla pagina del personaggio.
- Backup ed esportazione JSON includono gli alias.
- Migrazione automatica e non distruttiva del database esistente.

## 1.3.0

- suggerimenti automatici per i tag già esistenti;
- selezione dei suggerimenti con clic, frecce e Invio;
- autocomplete disponibile in New, organizzazione multipla, modifica file e filtro della galleria;
- ordinamento dei suggerimenti per corrispondenza e frequenza di utilizzo;
- normalizzazione degli spazi e riutilizzo della grafia già presente nel database;
- prevenzione di tag duplicati dovuti a maiuscole, minuscole o spazi multipli.

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
