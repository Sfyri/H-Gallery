# Changelog

## 2.0.0

- README riscritto e ridotto per installazione, primo utilizzo e build.
- Allineata la versione del progetto prima della pubblicazione su GitHub.

## 2.0.0-alpha.5

- Corretto il rilevamento di Inno Setup quando è presente un solo percorso valido.
- Evitato che PowerShell interpreti soltanto la lettera `C` come comando durante la build Windows.

## 2.0.0-alpha.4

- Aggiunta la configurazione PyInstaller per creare un'applicazione Windows autonoma senza Python installato.
- Aggiunta la configurazione Inno Setup per generare `H-Gallery-Setup-<versione>.exe`.
- Aggiunti collegamenti per avvio, configurazione delle gallerie e arresto dal menu Start.
- L'installer usa un'installazione per utente, non richiede privilegi amministrativi e non modifica le gallerie.
- Aggiunto `Build-Windows-Installer.bat` con generazione automatica di icona e metadati di versione.
- Il launcher riconosce l'esecuzione PyInstaller e riavvia o apre la configurazione usando lo stesso eseguibile.
- La disinstallazione arresta il server ma conserva gallerie, configurazione, cache e log.

## 2.0.0-alpha.3

- Aggiunto il launcher Windows in background senza terminale persistente.
- Aggiunta un’icona nell’area di notifica con apertura, cartella galleria, cambio archivio, log e arresto.
- Impedito l’avvio di più istanze: un secondo avvio riapre la finestra nel browser.
- Aggiunti i comandi `h-gallery launcher`, `open`, `stop` e `status`.
- Aggiunti `H-Gallery.vbs` e `Stop-H-Gallery.vbs` per l’avvio e l’arresto senza console.
- Aggiunto un log rotante in `%LOCALAPPDATA%\H-Gallery\logs`.
- Aggiornato `Start.bat` per avviare il nuovo launcher e chiudere subito il terminale.

## 2.0.0-alpha.2

- Aggiunto `pyproject.toml` con pacchetto Python standard e dipendenze dichiarate.
- Aggiunto il comando multipiattaforma `h-gallery` per avvio, configurazione ed elenco delle gallerie.
- Supportate installazioni con `pipx`, `uv tool`, `uvx` e `pip`.
- Inclusi frontend e configurazione predefinita nel pacchetto installato.
- Aggiornati `Install.bat`, `Start.bat` e `Reconfigure.bat` per usare il comando installato.
- Centralizzata la versione usata da API e manifest dei backup.
- Mantenuta la compatibilità con l'installazione locale nella cartella del programma.

## 2.0.0-alpha.1

- Separato il percorso del programma da quello della galleria.
- Aggiunto un registro utente delle gallerie con archivio attivo.
- Aggiunta la creazione, registrazione e selezione di più gallerie tramite `Reconfigure.bat`.
- Spostata la configurazione specifica dell'archivio in `.user/config.json`.
- Spostata la cache ricostruibile nella cartella locale dell'utente e separata per galleria.
- Mantenuta la rilevazione automatica della vecchia struttura `.Script` per la prima migrazione.
- Aggiunto il riepilogo della galleria attiva nella pagina Impostazioni.
- Aggiornati avvio, installazione e README per la nuova struttura.

## 1.7.1

- Aggiunta una guida iniziale mostrata solo quando la galleria non contiene file organizzati.
- La guida indica il flusso `.toDo` → New → Organizza e permette di aprire direttamente New.
- README aggiornato con una sezione dedicata al primo utilizzo.

## 1.7.0

- Modifica avanzata delle storie con aggiunta, rimozione e riordino delle pagine.
- Le pagine mantengono personaggi, tag, artisti e stato IA individuali.
- I metadati della storia vengono ricavati automaticamente dall’unione delle pagine.
- Le pagine rimosse tornano nella propria cartella e la numerazione resta continua.
- Copertina di riserva automatica e salvataggio unico con ripristino in caso di errore.
- Migrazione automatica e compatibile delle storie create con versioni precedenti.

## 1.6.4

- Alias dei personaggi mostrati su una riga separata.
- Ricerca personaggi sovrapposta in Dettagli file e Crea storia.
- Rimosso il pannello Destinazione automatica dall’organizzazione.
- Rimosso il messaggio rapido “Caricamento personaggi”.

## 1.6.3

- Griglia Storie limitata a quattro pagine per riga.
- Copertina su una riga separata e nomi file rimossi dalle pagine.
- Allineati correttamente i checkbox IA e duplicati.
- Rimosso il pannello della destinazione automatica.
- Le pagine mancanti vengono segnalate senza bloccare il lettore o l’editor.

## 1.6.2

- New mantiene il punto di lavoro dopo organizzazione o cestino.
- Viene mostrato il file successivo, oppure il precedente se era l’ultimo.

## 1.6.1

- Anteprime della griglia senza sfondo a scacchi.
- Ricerca personaggi sovrapposta durante l’organizzazione.
- Rimossi pannelli dei checkbox e testi informativi superflui.

## 1.6.0

- Migliorati pannello media, navigazione, dettagli e modifica dei personaggi.
- Aggiunta la trasparenza reale per PNG e GIF, senza sfondo sui file opachi.
- Rifinite etichette, testi e anteprime dell’interfaccia.

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
