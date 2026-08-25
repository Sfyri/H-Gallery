import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../services/gallery_bridge.dart';
import '../services/gallery_sync_service.dart';
import '../theme/app_theme.dart';

class GallerySyncPage extends StatefulWidget {
  const GallerySyncPage({super.key});

  @override
  State<GallerySyncPage> createState() => _GallerySyncPageState();
}

class _GallerySyncPageState extends State<GallerySyncPage> {
  final PlatformGalleryService _galleryService = const PlatformGalleryService();
  final GallerySyncService _syncService = GallerySyncService();

  List<GalleryProfile> _android = const [];
  List<WindowsGalleryProfile> _windows = const [];
  Map<String, String> _androidGroups = const {};
  Map<String, GallerySyncStatus> _statuses = const {};
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final android = (await _galleryService.listGalleries())
          .where((gallery) => gallery.accessible && gallery.layoutReady)
          .toList(growable: false);
      final windows = await _syncService.listWindowsGalleries();
      final groups = <String, String>{};
      final statuses = <String, GallerySyncStatus>{};
      for (final gallery in android) {
        final group = await _syncService.getSyncGroupUuid(gallery.galleryUuid);
        groups[gallery.galleryUuid] = group;
        if (group.isNotEmpty) {
          statuses[gallery.galleryUuid] = await _syncService.getSyncStatus(gallery.galleryUuid);
        }
      }
      if (!mounted) return;
      setState(() {
        _android = android;
        _windows = windows;
        _androidGroups = groups;
        _statuses = statuses;
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _loading = false);
      _error(error.message ?? 'Impossibile leggere i collegamenti delle gallerie.');
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _error('Impossibile leggere i collegamenti: $error');
    }
  }

  List<_LinkedPair> get _pairs {
    final pairs = <_LinkedPair>[];
    for (final gallery in _android) {
      final group = _androidGroups[gallery.galleryUuid] ?? '';
      if (group.isEmpty) continue;
      WindowsGalleryProfile? windows;
      for (final candidate in _windows) {
        if (candidate.syncGroupUuid == group) {
          windows = candidate;
          break;
        }
      }
      pairs.add(_LinkedPair(android: gallery, windows: windows, groupUuid: group));
    }
    return pairs;
  }

  Future<void> _link() async {
    if (_working) return;
    final unlinkedAndroid = _android
        .where((gallery) => (_androidGroups[gallery.galleryUuid] ?? '').isEmpty)
        .toList(growable: false);
    final localGroups = _androidGroups.values.where((value) => value.isNotEmpty).toSet();
    final windowsCandidates = _windows.where((gallery) {
      if (!gallery.available || !gallery.syncReady) return false;
      // Sullo stesso telefono non colleghiamo due gallerie Android allo stesso gruppo.
      return gallery.syncGroupUuid.isEmpty || !localGroups.contains(gallery.syncGroupUuid);
    }).toList(growable: false);

    if (unlinkedAndroid.isEmpty) {
      _error('Tutte le gallerie Android disponibili sono già collegate.');
      return;
    }
    if (windowsCandidates.isEmpty) {
      _error('Non ci sono gallerie Windows disponibili da collegare. Aprile almeno una volta su Windows.');
      return;
    }

    GalleryProfile android = unlinkedAndroid.first;
    WindowsGalleryProfile windows = windowsCandidates.first;
    final selected = await showDialog<_LinkSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Collega una galleria'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Le due gallerie diventeranno membri dello stesso gruppo di sincronizzazione. '
                  'Solo gallerie appartenenti allo stesso gruppo possono fare merge.',
                  style: TextStyle(color: AppTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 18),
                const Text('Android', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButton<GalleryProfile>(
                  value: android,
                  isExpanded: true,
                  items: unlinkedAndroid
                      .map((gallery) => DropdownMenuItem(value: gallery, child: Text(gallery.name)))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => android = value);
                  },
                ),
                const SizedBox(height: 14),
                const Text('Windows', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButton<WindowsGalleryProfile>(
                  value: windows,
                  isExpanded: true,
                  items: windowsCandidates
                      .map(
                        (gallery) => DropdownMenuItem(
                          value: gallery,
                          child: Text(
                            '${gallery.name}${gallery.linked ? ' · gruppo esistente' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => windows = value);
                  },
                ),
                if (!windows.active) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Puoi creare il collegamento anche se questa galleria Windows non è attiva. '
                    'Per sincronizzarla dovrai poi aprirla su Windows e riavviare H-Gallery.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Annulla')),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(_LinkSelection(android, windows)),
              child: const Text('Collega'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _working = true);
    try {
      await _syncService.linkGalleries(selected.android, selected.windows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.android.name} ↔ ${selected.windows.name} collegate.')),
      );
      await _reload();
    } on PlatformException catch (error) {
      _error(error.message ?? 'Collegamento delle gallerie non riuscito.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _unlink(_LinkedPair pair) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scollegare la galleria Android?'),
        content: Text(
          '${pair.android.name} non farà più parte di questo gruppo e non potrà fare merge con '
          '${pair.windows?.name ?? 'la galleria Windows'} finché non verrà collegata di nuovo. '
          'Nessun file verrà eliminato.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Scollega')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      await _syncService.unlinkAndroidGallery(pair.android);
      await _reload();
    } on PlatformException catch (error) {
      _error(error.message ?? 'Impossibile scollegare la galleria.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _openMerge(_LinkedPair pair) {
    final windows = pair.windows;
    if (windows == null) {
      _error('Il gruppo collegato non è presente tra le gallerie di questo PC.');
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => GalleryMergePage(
              androidGallery: pair.android,
              windowsGallery: windows,
              syncGroupUuid: pair.groupUuid,
            ),
          ),
        )
        .then((_) => _reload());
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final pairs = _pairs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallerie collegate'),
        actions: [
          IconButton(onPressed: _loading || _working ? null : _reload, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _working ? null : _link,
        icon: const Icon(Icons.add_link_rounded),
        label: const Text('Collega galleria'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                if (pairs.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Nessuna galleria collegata. Premi “Collega galleria” per creare il primo gruppo.'),
                    ),
                  )
                else
                  ...pairs.map(
                    (pair) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _LinkedGalleryCard(
                        pair: pair,
                        status: _statuses[pair.android.galleryUuid],
                        busy: _working,
                        onSync: () => _openMerge(pair),
                        onUnlink: () => _unlink(pair),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                _InventoryCard(android: _android, windows: _windows, androidGroups: _androidGroups),
              ],
            ),
    );
  }
}

class _LinkedGalleryCard extends StatelessWidget {
  const _LinkedGalleryCard({
    required this.pair,
    required this.status,
    required this.busy,
    required this.onSync,
    required this.onUnlink,
  });

  final _LinkedPair pair;
  final GallerySyncStatus? status;
  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onUnlink;

  String _lastSyncLabel(GallerySyncStatus value) {
    final date = DateTime.fromMillisecondsSinceEpoch(value.lastSyncEpochMs).toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final windows = pair.windows;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_rounded, color: AppTheme.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${pair.android.name} ↔ ${windows?.name ?? 'PC non disponibile'}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Android · ${pair.android.name}'),
            Text('Windows · ${windows?.name ?? 'gruppo non trovato su questo PC'}'),
            const SizedBox(height: 8),
            Text(
              'Gruppo ${pair.groupUuid.length > 12 ? '${pair.groupUuid.substring(0, 12)}…' : pair.groupUuid}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
            if (status != null && status!.hasHistory) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 17, color: AppTheme.success),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Ultima sincronizzazione verificata: ${_lastSyncLabel(status!)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Ultimo conteggio: Android ${status!.androidCount} · Windows ${status!.windowsCount}',
                style: const TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Text(
                'Nessuna sincronizzazione verificata per questo gruppo.',
                style: TextStyle(fontSize: 12, color: AppTheme.muted),
              ),
            ],
            if (windows != null && !windows.active) ...[
              const SizedBox(height: 10),
              const Text(
                'La galleria Windows collegata non è quella attualmente caricata dal server. '
                'Aprila su Windows e riavvia H-Gallery prima del merge.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy || windows == null ? null : onSync,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Sincronizza'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Scollega',
                  onPressed: busy ? null : onUnlink,
                  icon: const Icon(Icons.link_off_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.android, required this.windows, required this.androidGroups});

  final List<GalleryProfile> android;
  final List<WindowsGalleryProfile> windows;
  final Map<String, String> androidGroups;

  @override
  Widget build(BuildContext context) {
    final unlinkedAndroid = android.where((g) => (androidGroups[g.galleryUuid] ?? '').isEmpty).length;
    final unlinkedWindows = windows.where((g) => g.syncGroupUuid.isEmpty).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Disponibili', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Android: ${android.length} gallerie · $unlinkedAndroid non collegate'),
            Text('Windows: ${windows.length} gallerie · $unlinkedWindows senza gruppo'),
          ],
        ),
      ),
    );
  }
}

class _LinkSelection {
  const _LinkSelection(this.android, this.windows);
  final GalleryProfile android;
  final WindowsGalleryProfile windows;
}

class _LinkedPair {
  const _LinkedPair({required this.android, required this.windows, required this.groupUuid});
  final GalleryProfile android;
  final WindowsGalleryProfile? windows;
  final String groupUuid;
}

class GalleryMergePage extends StatefulWidget {
  const GalleryMergePage({
    super.key,
    required this.androidGallery,
    required this.windowsGallery,
    required this.syncGroupUuid,
  });

  final GalleryProfile androidGallery;
  final WindowsGalleryProfile windowsGallery;
  final String syncGroupUuid;

  @override
  State<GalleryMergePage> createState() => _GalleryMergePageState();
}

class _GalleryMergePageState extends State<GalleryMergePage> {
  final GallerySyncService _syncService = GallerySyncService();
  StreamSubscription<GallerySyncProgress>? _progressSubscription;
  GallerySyncPlan? _plan;
  GallerySyncResult? _result;
  GallerySyncProgress? _progress;
  bool _analyzing = false;
  bool _syncing = false;
  bool _cancelling = false;
  bool _syncFiles = true;
  bool _syncDeletions = true;
  bool _syncMetadata = true;

  @override
  void initState() {
    super.initState();
    _progressSubscription = _syncService.progress.listen((value) {
      if (mounted) setState(() => _progress = value);
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_analyzing || _syncing) return;
    setState(() {
      _analyzing = true;
      _plan = null;
      _result = null;
      _progress = null;
    });
    try {
      final plan = await _syncService.analyze(
        widget.androidGallery,
        widget.windowsGallery,
        widget.syncGroupUuid,
      );
      if (mounted) setState(() => _plan = plan);
    } on PlatformException catch (error) {
      _error(error.message ?? 'Analisi delle gallerie non riuscita.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _sync() async {
    final plan = _plan;
    if (plan == null || _syncing) return;

    if (!_hasSyncSelection) {
      _error('Seleziona almeno una categoria da sincronizzare.');
      return;
    }
    if (_syncDeletions && plan.deletionConflicts > 0) {
      _error(
        'M7.5 ha bloccato ${plan.deletionConflicts} cancellazioni ambigue. '
        'Deseleziona “Eliminazioni” oppure apri “Dettaglio eliminazioni” e risolvi i conflitti.',
      );
      return;
    }
    if (_syncMetadata && plan.metadataResolutionConflicts > 0) {
      _error(
        'M7.6 ha bloccato ${plan.metadataResolutionConflicts} modifiche metadata concorrenti. '
        'Deseleziona “Metadata e classifica” oppure risolvi manualmente il conflitto.',
      );
      return;
    }

    final selectedFileCount = plan.toAndroid + plan.toWindows;
    final hasSkippedWork =
        (!_syncFiles && selectedFileCount > 0) ||
        (!_syncDeletions &&
            (plan.pendingDeletions > 0 || plan.deletionConflicts > 0)) ||
        (!_syncMetadata &&
            (plan.metadataDifferences > 0 ||
                plan.metadataBaselinePending > 0 ||
                plan.metadataResolutionConflicts > 0));

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eseguire le operazioni selezionate?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_syncFiles)
                Text(
                  'File: ${plan.toAndroid} verso Android · '
                  '${plan.toWindows} verso Windows.',
                  style: const TextStyle(height: 1.4),
                ),
              if (_syncDeletions) ...[
                if (_syncFiles) const SizedBox(height: 8),
                Text(
                  'Eliminazioni: ${plan.pendingDeletions} da propagare '
                  '(${plan.deleteOnAndroid} su Android · '
                  '${plan.deleteOnWindows} su Windows).',
                  style: const TextStyle(height: 1.4),
                ),
              ],
              if (_syncMetadata) ...[
                if (_syncFiles || _syncDeletions) const SizedBox(height: 8),
                Text(
                  'Metadata e classifica: ${plan.metadataDifferences} media differenti · '
                  '${plan.metadataBaselinePending} baseline da inizializzare.',
                  style: const TextStyle(height: 1.4),
                ),
              ],
              if (hasSkippedWork) ...[
                const SizedBox(height: 14),
                const Text(
                  'Le categorie deselezionate non verranno applicate e resteranno '
                  'in attesa per una sincronizzazione successiva.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              if (!_syncMetadata && selectedFileCount > 0) ...[
                const SizedBox(height: 10),
                const Text(
                  'Con Metadata deselezionato, i file gia presenti non ricevono '
                  'modifiche metadata come effetto collaterale dei trasferimenti.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
              if (!_syncDeletions &&
                  (plan.pendingDeletions > 0 || plan.deletionConflicts > 0)) ...[
                const SizedBox(height: 10),
                const Text(
                  'Le tombstone restano comunque protette: un media in attesa di '
                  'eliminazione non viene ricopiato per errore da un altro dispositivo.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Esegui selezionate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _syncing = true;
      _cancelling = false;
      _result = null;
      _progress = const GallerySyncProgress(
        phase: 'start',
        processed: 0,
        total: 1,
        current: 'Preparazione sincronizzazione',
      );
    });

    try {
      final result = await _syncService.run(
        widget.androidGallery,
        widget.windowsGallery,
        widget.syncGroupUuid,
        selection: GallerySyncSelection(
          files: _syncFiles,
          deletions: _syncDeletions,
          metadata: _syncMetadata,
        ),
      );
      if (!mounted) return;
      setState(() => _result = result);

      if (result.complete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.verifiedSynced
                  ? 'Sincronizzazione completata e verificata.'
                  : 'Operazioni selezionate completate. Restano categorie non allineate.',
            ),
          ),
        );
      } else if (result.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sincronizzazione interrotta. Le operazioni gia confermate sono al sicuro.',
            ),
          ),
        );
      } else if (result.interrupted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Connessione interrotta. Puoi riprendere il merge quando il PC torna raggiungibile.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Merge parziale: restano operazioni selezionate da verificare o ripetere.',
            ),
          ),
        );
      }

      if (!result.interrupted) {
        try {
          final refreshed = await _syncService.analyze(
            widget.androidGallery,
            widget.windowsGallery,
            widget.syncGroupUuid,
          );
          if (mounted) setState(() => _plan = refreshed);
        } on PlatformException {
          // Il risultato rimane visibile; l'utente puo rilanciare Analizza.
        }
      }
    } on PlatformException catch (error) {
      _error(
        error.message ??
            'Sincronizzazione non avviata: controlla le categorie selezionate e riprova.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _cancelSync() async {
    if (!_syncing || _cancelling) return;
    setState(() => _cancelling = true);
    try {
      await _syncService.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interruzione richiesta: terminerà il file corrente.')),
      );
    } on PlatformException catch (error) {
      if (mounted) setState(() => _cancelling = false);
      _error(error.message ?? 'Impossibile richiedere l’interruzione.');
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasSyncSelection =>
      _syncFiles || _syncDeletions || _syncMetadata;

  bool _selectedBlockingConflicts(GallerySyncPlan plan) =>
      (_syncDeletions && plan.deletionConflicts > 0) ||
      (_syncMetadata && plan.metadataResolutionConflicts > 0);

  String _selectionStatus(GallerySyncPlan plan) {
    if (!_hasSyncSelection) {
      return 'Seleziona almeno una categoria.';
    }
    if (_syncDeletions && plan.deletionConflicts > 0) {
      return '${plan.deletionConflicts} cancellazioni selezionate sono bloccate per sicurezza.';
    }
    if (_syncMetadata && plan.metadataResolutionConflicts > 0) {
      return '${plan.metadataResolutionConflicts} conflitti metadata selezionati richiedono una risoluzione manuale.';
    }
    if (plan.synchronized) {
      return 'Gallerie e baseline metadata gia allineati.';
    }
    return 'Verranno eseguite solo le categorie selezionate.';
  }

  String _bytes(int value) {
    if (value < 1024) return '$value B';
    final kb = value / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  String _phaseLabel(GallerySyncProgress progress) {
    switch (progress.phase) {
      case 'scan':
        return 'Indicizzazione';
      case 'compare':
        return 'Confronto gallerie';
      case 'deletions':
        return 'Allineamento eliminazioni';
      case 'deletions_windows':
        return 'Eliminazioni su Windows';
      case 'download':
        return 'Windows → Android';
      case 'upload':
        return 'Android → Windows';
      case 'retry':
        return 'Nuovo tentativo';
      case 'metadata_android':
        return 'Merge metadata Android';
      case 'metadata_windows':
        return 'Merge metadata Windows';
      case 'metadata_baseline':
        return 'Verifica baseline metadata';
      case 'finalize_windows':
        return 'Aggiornamento Windows';
      case 'verify':
        return 'Verifica finale';
      case 'cancelled':
        return 'Interrotta';
      case 'interrupted':
        return 'Connessione interrotta';
      case 'partial':
        return 'Merge parziale';
      case 'done':
        return 'Completato';
      default:
        return 'Preparazione';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronizza gruppo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Android · ${widget.androidGallery.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Windows · ${widget.windowsGallery.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gruppo ${widget.syncGroupUuid}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                  if (!widget.windowsGallery.active) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Questa galleria non è attiva sul server Windows. Aprila su Windows e riavvia H-Gallery, poi torna qui.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _syncing || _analyzing ? null : _analyze,
            icon: _analyzing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(_analyzing ? 'Analisi…' : 'Analizza gallerie'),
          ),
          if (plan != null) ...[
            const SizedBox(height: 22),
            _PlanCard(plan: plan, bytes: _bytes),
            const SizedBox(height: 10),
            _SyncSelectionCard(
              plan: plan,
              files: _syncFiles,
              deletions: _syncDeletions,
              metadata: _syncMetadata,
              enabled: !_syncing,
              onFilesChanged: (value) => setState(() => _syncFiles = value),
              onDeletionsChanged: (value) =>
                  setState(() => _syncDeletions = value),
              onMetadataChanged: (value) =>
                  setState(() => _syncMetadata = value),
            ),
            if (plan.metadataDifferences > 0 ||
                plan.metadataBaselinePending > 0 ||
                plan.metadataResolutionConflicts > 0) ...[
              const SizedBox(height: 10),
              _MetadataDetailsCard(plan: plan),
            ],
            if (plan.pendingDeletions > 0 || plan.deletionConflicts > 0) ...[
              const SizedBox(height: 10),
              _DeletionDetailsCard(plan: plan),
            ],
            if (plan.pathConflicts > 0) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${plan.pathConflicts} collisioni di percorso: entrambe le versioni saranno conservate.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ),
            ],
            if (plan.metadataTypeConflicts > 0) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${plan.metadataTypeConflicts} differenze tag/artista rilevate. Senza baseline condiviso prevale Artista; con baseline verificato M7.6 applica solo modifiche non ambigue.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _selectedBlockingConflicts(plan)
                      ? Icons.block_rounded
                      : plan.synchronized
                          ? Icons.check_circle_rounded
                          : Icons.tune_rounded,
                  color: _selectedBlockingConflicts(plan)
                      ? Theme.of(context).colorScheme.error
                      : plan.synchronized
                          ? AppTheme.success
                          : AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectionStatus(plan),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _syncing ||
                      !_hasSyncSelection ||
                      _selectedBlockingConflicts(plan)
                  ? null
                  : _sync,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                !_hasSyncSelection
                    ? 'Seleziona almeno una categoria'
                    : _selectedBlockingConflicts(plan)
                        ? 'Risolvi i conflitti selezionati'
                        : plan.synchronized
                            ? 'Verifica sincronizzazione'
                            : 'Esegui operazioni selezionate',
              ),
            ),
          ],
          if (_syncing && progress != null) ...[
            const SizedBox(height: 22),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _phaseLabel(progress),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: progress.fraction),
                    const SizedBox(height: 10),
                    Text(progress.current, style: const TextStyle(color: AppTheme.muted)),
                    if (progress.total > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${progress.processed}/${progress.total} elaborati · '
                        '${progress.succeeded} riusciti · ${progress.failed} errori',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                    if (progress.maxAttempts > 1 && progress.attempt > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tentativo ${progress.attempt}/${progress.maxAttempts}',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _cancelling ? null : _cancelSync,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        _cancelling
                            ? 'Interruzione richiesta…'
                            : 'Interrompi dopo il file corrente',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 18),
            _SyncResultCard(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _SyncSelectionCard extends StatelessWidget {
  const _SyncSelectionCard({
    required this.plan,
    required this.files,
    required this.deletions,
    required this.metadata,
    required this.enabled,
    required this.onFilesChanged,
    required this.onDeletionsChanged,
    required this.onMetadataChanged,
  });

  final GallerySyncPlan plan;
  final bool files;
  final bool deletions;
  final bool metadata;
  final bool enabled;
  final ValueChanged<bool> onFilesChanged;
  final ValueChanged<bool> onDeletionsChanged;
  final ValueChanged<bool> onMetadataChanged;

  @override
  Widget build(BuildContext context) {
    final fileCount = plan.toAndroid + plan.toWindows;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text(
                'Operazioni da eseguire',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            CheckboxListTile(
              value: files,
              onChanged: enabled
                  ? (value) => onFilesChanged(value ?? false)
                  : null,
              title: Text('File · $fileCount'),
              subtitle: Text(
                '${plan.toAndroid} verso Android · '
                '${plan.toWindows} verso Windows',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: deletions,
              onChanged: enabled
                  ? (value) => onDeletionsChanged(value ?? false)
                  : null,
              title: Text('Eliminazioni · ${plan.pendingDeletions}'),
              subtitle: Text(
                '${plan.deleteOnAndroid} su Android · '
                '${plan.deleteOnWindows} su Windows'
                '${plan.deletionConflicts > 0 ? ' · ${plan.deletionConflicts} conflitti' : ''}',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: metadata,
              onChanged: enabled
                  ? (value) => onMetadataChanged(value ?? false)
                  : null,
              title: Text(
                'Metadata e classifica · ${plan.metadataDifferences}',
              ),
              subtitle: Text(
                '${plan.metadataBaselinePending} baseline da inizializzare'
                '${plan.metadataResolutionConflicts > 0 ? ' · ${plan.metadataResolutionConflicts} conflitti' : ''}',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncResultCard extends StatelessWidget {
  const _SyncResultCard({required this.result});

  final GallerySyncResult result;

  @override
  Widget build(BuildContext context) {
    final title = result.complete
        ? (result.verifiedSynced
            ? 'Sincronizzazione completata'
            : 'Operazioni selezionate completate')
        : result.cancelled
            ? 'Merge interrotto'
            : result.interrupted
                ? 'Connessione interrotta'
                : 'Merge parziale';
    final icon = result.complete ? Icons.check_circle_rounded : Icons.warning_amber_rounded;
    final shownFailures = result.failures.take(5).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Windows → Android completati: ${result.downloaded}'),
            Text('Android → Windows completati: ${result.uploaded}'),
            if (result.deletedOnAndroid > 0)
              Text('Spostati nel Cestino Android: ${result.deletedOnAndroid}'),
            if (result.deletedOnWindows > 0)
              Text('Spostati nel Cestino Windows: ${result.deletedOnWindows}'),
            if (result.deletionAlreadyAbsentAndroid > 0 ||
                result.deletionAlreadyAbsentWindows > 0)
              Text(
                'Eliminazioni registrate su media già assenti: '
                '${result.deletionAlreadyAbsentAndroid + result.deletionAlreadyAbsentWindows}',
              ),
            if (result.deletionPendingAfter > 0)
              Text('Eliminazioni ancora da propagare: ${result.deletionPendingAfter}'),
            if (result.deletionConflictsAfter > 0)
              Text(
                'Conflitti eliminazione ancora presenti: ${result.deletionConflictsAfter}',
              ),
            Text('Già presenti all’avvio: ${result.alreadyPresent}'),
            Text('Metadata differenti all’avvio: ${result.metadataDifferencesBefore}'),
            if (result.metadataBaselinePendingBefore > 0)
              Text('Baseline metadata da inizializzare all’avvio: ${result.metadataBaselinePendingBefore}'),
            if (result.metadataResolutionConflictsBefore > 0)
              Text('Conflitti metadata all’avvio: ${result.metadataResolutionConflictsBefore}'),
            Text('Metadata modificati su Android: ${result.metadataChangedAndroid}'),
            Text('Metadata modificati su Windows: ${result.metadataChangedWindows}'),
            if (result.createdCharactersAndroid > 0 || result.createdFranchisesAndroid > 0)
              Text(
                'Creati su Android: ${result.createdFranchisesAndroid} serie · ${result.createdCharactersAndroid} personaggi',
              ),
            if (result.createdCharactersWindows > 0 || result.createdFranchisesWindows > 0)
              Text(
                'Creati su Windows: ${result.createdFranchisesWindows} serie · ${result.createdCharactersWindows} personaggi',
              ),
            Text(
              result.verifiedSynced
                  ? 'Verifica finale: file, metadata, baseline ed eliminazioni allineati'
                  : result.complete
                      ? 'Le operazioni selezionate sono complete; le categorie deselezionate restano in attesa.'
                      : 'Verifica finale: ${result.metadataDifferencesAfter} differenze metadata, '
                          '${result.metadataBaselinePendingAfter} baseline da inizializzare, '
                          '${result.metadataResolutionConflictsAfter} conflitti metadata e '
                          '${result.deletionPendingAfter} eliminazioni ancora da allineare',
            ),
            if (result.failed > 0) Text('Trasferimenti falliti: ${result.failed}'),
            if (result.pending > 0) Text('Non ancora tentati: ${result.pending}'),
            Text('Totale Android: ${result.androidCount}'),
            Text('Totale Windows: ${result.windowsCount}'),
            if (!result.complete) ...[
              const SizedBox(height: 12),
              const Text(
                'Nessun trasferimento o tombstone già confermata viene perso: esegui di nuovo “Analizza gallerie” e poi “Sincronizza”. '
                'Le operazioni già completate verranno escluse automaticamente dal nuovo piano.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
              ),
            ],
            if (shownFailures.isNotEmpty) ...[
              const Divider(height: 26),
              const Text('Errori', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ...shownFailures.map(
                (failure) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '• ${failure.filename}: ${failure.message}',
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ),
              if (result.failures.length > shownFailures.length)
                Text(
                  '+ ${result.failures.length - shownFailures.length} altri errori',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeletionDetailsCard extends StatelessWidget {
  const _DeletionDetailsCard({required this.plan});

  final GallerySyncPlan plan;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          plan.deletionConflicts > 0
              ? Icons.gpp_bad_rounded
              : Icons.delete_sweep_rounded,
          color: plan.deletionConflicts > 0 ? errorColor : AppTheme.accent,
        ),
        title: const Text(
          'Dettaglio eliminazioni',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${plan.pendingDeletions} da propagare'
          '${plan.deletionConflicts > 0 ? ' · ${plan.deletionConflicts} bloccate' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'M7.5 propaga solo eliminazioni definitive registrate da H-Gallery. '
              'Sul dispositivo ricevente il media viene spostato nel Cestino, '
              'non distrutto definitivamente. File mancanti per modifiche esterne '
              'non vengono interpretati come cancellazioni.',
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ),
          if (plan.deletionConflictDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Operazioni bloccate',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: errorColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final conflict in plan.deletionConflictDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded, size: 18, color: errorColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${conflict.targetLabel} · '
                            '${conflict.filename.isEmpty ? conflict.relativePath : conflict.filename}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (conflict.relativePath.isNotEmpty)
                            Text(
                              conflict.relativePath,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          Text(
                            conflict.message,
                            style: TextStyle(
                              color: errorColor,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'Finché esiste anche un solo conflitto, il pulsante di sincronizzazione resta disabilitato.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
            ),
          ],
          if (plan.deletionDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (var index = 0; index < plan.deletionDetails.length; index++) ...[
              _DeletionDetailTile(detail: plan.deletionDetails[index]),
              if (index != plan.deletionDetails.length - 1)
                const Divider(height: 18),
            ],
          ],
          if (plan.deletionDetailsTruncated) ...[
            const SizedBox(height: 10),
            const Text(
              'L’anteprima mostra le prime 200 operazioni di eliminazione; il conteggio totale comprende anche le restanti.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'M7.6 gestisce separatamente le rimozioni metadata tramite un baseline verificato: '
            'una semplice assenza non viene mai interpretata come eliminazione.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _DeletionDetailTile extends StatelessWidget {
  const _DeletionDetailTile({required this.detail});

  final GalleryDeletionDetail detail;

  @override
  Widget build(BuildContext context) {
    final title = detail.action == 'record'
        ? 'Su ${detail.targetLabel}: registra eliminazione'
        : 'Su ${detail.targetLabel}: sposta nel Cestino';
    final matchNote = switch (detail.matchKind) {
      'uuid' => 'Identità media verificata con UUID + SHA-256.',
      'sha256' => 'Identità compatibile verificata tramite SHA-256 univoco.',
      'sha256+path' => 'Identità compatibile verificata tramite SHA-256 + percorso.',
      'absent' => 'Il file è già assente; verrà replicata solo la tombstone.',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            detail.action == 'record'
                ? Icons.fact_check_outlined
                : Icons.delete_outline_rounded,
            size: 19,
            color: AppTheme.accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  detail.filename.isEmpty ? detail.relativePath : detail.filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail.relativePath.isNotEmpty)
                  Text(
                    detail.relativePath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
                if (matchNote.isNotEmpty)
                  Text(
                    matchNote,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataDetailsCard extends StatelessWidget {
  const _MetadataDetailsCard({required this.plan});

  final GallerySyncPlan plan;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final subtitle = <String>[
      '${plan.metadataDifferences} media',
      '${plan.metadataChangeCount} modifiche',
      if (plan.metadataBaselinePending > 0)
        '${plan.metadataBaselinePending} baseline da inizializzare',
      if (plan.metadataResolutionConflicts > 0)
        '${plan.metadataResolutionConflicts} conflitti',
    ].join(' · ');

    return Card(
      child: ExpansionTile(
        leading: Icon(
          plan.metadataResolutionConflicts > 0
              ? Icons.gpp_bad_rounded
              : Icons.rule_folder_rounded,
          color: plan.metadataResolutionConflicts > 0
              ? errorColor
              : AppTheme.accent,
        ),
        title: const Text(
          'Dettaglio metadata',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'M7.6 usa un confronto a tre vie con l’ultimo baseline verificato. '
              'Aggiunte e rimozioni vengono propagate solo quando la direzione '
              'della modifica è certa. Senza un baseline condiviso il merge resta '
              'additivo e non deduce cancellazioni dalla sola assenza.',
              style: TextStyle(color: AppTheme.muted, height: 1.35),
            ),
          ),
          if (plan.metadataBaselinePending > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${plan.metadataBaselinePending} media non hanno ancora un baseline '
                'metadata identico sui due dispositivi. La prossima sincronizzazione '
                'allineerà i metadata senza rimozioni e, dopo la verifica, salverà '
                'un baseline condiviso.',
                style: const TextStyle(color: AppTheme.muted, height: 1.35),
              ),
            ),
          ],
          if (plan.metadataResolutionConflictDetails.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Conflitti bloccanti',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: errorColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final conflict in plan.metadataResolutionConflictDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.block_rounded, size: 18, color: errorColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conflict.filename.isEmpty
                                ? conflict.relativePath
                                : conflict.filename,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (conflict.relativePath.isNotEmpty)
                            Text(
                              conflict.relativePath,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          Text(
                            conflict.message,
                            style: TextStyle(
                              color: errorColor,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              'M7.6 non sceglie automaticamente tra due modifiche concorrenti incompatibili. '
              'Uniforma manualmente il metadata sui due dispositivi e analizza di nuovo.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
            ),
          ],
          if (plan.metadataDetails.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var index = 0; index < plan.metadataDetails.length; index++) ...[
              _MetadataDifferenceTile(detail: plan.metadataDetails[index]),
              if (index != plan.metadataDetails.length - 1)
                const Divider(height: 18),
            ],
          ],
          if (plan.metadataDetailsTruncated) ...[
            const SizedBox(height: 12),
            const Text(
              'L’anteprima mostra i primi 200 media con differenze. Il conteggio totale sopra comprende comunque tutte le modifiche rilevate.',
              style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetadataDifferenceTile extends StatelessWidget {
  const _MetadataDifferenceTile({required this.detail});

  final GalleryMetadataDifference detail;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      title: Text(
        detail.filename.isEmpty ? detail.relativePath : detail.filename,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detail.relativePath.isNotEmpty)
            Text(
              detail.relativePath,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          Text(
            '${detail.changeCount} modifiche',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ],
      ),
      children: [
        if (detail.toAndroid.isNotEmpty)
          _MetadataDirection(
            icon: Icons.phone_android_rounded,
            title: 'Su Android verrà modificato',
            changes: detail.toAndroid,
          ),
        if (detail.toWindows.isNotEmpty)
          _MetadataDirection(
            icon: Icons.computer_rounded,
            title: 'Su Windows verrà modificato',
            changes: detail.toWindows,
          ),
        if (detail.typeConflict)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Differenza di classificazione tag/artista rilevata. M7.6 la gestisce solo se la direzione è determinabile dal baseline.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _MetadataDirection extends StatelessWidget {
  const _MetadataDirection({
    required this.icon,
    required this.title,
    required this.changes,
  });

  final IconData icon;
  final String title;
  final List<GalleryMetadataChange> changes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppTheme.accent),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          for (final change in changes)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${change.symbol} ${change.label}'),
                  if (change.note.isNotEmpty)
                    Text(
                      change.note,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.bytes});
  final GallerySyncPlan plan;
  final String Function(int) bytes;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 19, color: AppTheme.accent),
              const SizedBox(width: 9),
              Expanded(child: Text(label)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.windowsGalleryName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            line(Icons.computer_rounded, 'Media su Windows', '${plan.windowsCount}'),
            line(Icons.phone_android_rounded, 'Media su Android', '${plan.androidCount}'),
            const Divider(height: 22),
            line(Icons.download_rounded, 'Da copiare su Android', '${plan.toAndroid} · ${bytes(plan.bytesToAndroid)}'),
            line(Icons.upload_rounded, 'Da copiare su Windows', '${plan.toWindows} · ${bytes(plan.bytesToWindows)}'),
            line(Icons.done_all_rounded, 'Già presenti', '${plan.alreadyPresent}'),
            line(Icons.sell_rounded, 'Media con metadata differenti', '${plan.metadataDifferences} · ${plan.metadataChangeCount} modifiche'),
            if (plan.metadataBaselinePending > 0)
              line(
                Icons.shield_outlined,
                'Baseline metadata da inizializzare',
                '${plan.metadataBaselinePending}',
              ),
            if (plan.metadataResolutionConflicts > 0)
              line(
                Icons.block_rounded,
                'Conflitti metadata bloccanti',
                '${plan.metadataResolutionConflicts}',
              ),
            if (plan.deletionPendingAndroid > 0)
              line(
                Icons.delete_sweep_rounded,
                'Eliminazioni da propagare su Android',
                '${plan.deletionPendingAndroid}',
              ),
            if (plan.deletionPendingWindows > 0)
              line(
                Icons.delete_sweep_rounded,
                'Eliminazioni da propagare su Windows',
                '${plan.deletionPendingWindows}',
              ),
            if (plan.deletionConflicts > 0)
              line(
                Icons.block_rounded,
                'Cancellazioni bloccate per sicurezza',
                '${plan.deletionConflicts}',
              ),
          ],
        ),
      ),
    );
  }
}
