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
      for (final gallery in android) {
        groups[gallery.galleryUuid] = await _syncService.getSyncGroupUuid(gallery.galleryUuid);
      }
      if (!mounted) return;
      setState(() {
        _android = android;
        _windows = windows;
        _androidGroups = groups;
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
                const Text('M7 · Gruppi di sincronizzazione', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'Ogni galleria possiede già un ID univoco. M7.2 aggiunge un secondo ID per il gruppo: '
                  'solo gallerie con lo stesso ID di gruppo possono essere confrontate e unite.',
                  style: TextStyle(color: AppTheme.muted, height: 1.45),
                ),
                const SizedBox(height: 22),
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
    required this.busy,
    required this.onSync,
    required this.onUnlink,
  });

  final _LinkedPair pair;
  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onUnlink;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizzare il gruppo?'),
        content: Text(
          'Verranno copiati ${plan.toAndroid} media su Android e ${plan.toWindows} su Windows. '
          'M7.3 ritenta automaticamente gli errori di rete e, se il trasferimento viene interrotto, '
          'al prossimo avvio salta i file già completati tramite SHA-256. Le eliminazioni non vengono propagate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Avvia merge'),
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
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.complete) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronizzazione completata.')),
        );
      } else if (result.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sincronizzazione interrotta. I file completati sono già al sicuro.'),
          ),
        );
      } else if (result.interrupted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connessione interrotta. Puoi riprendere il merge quando il PC torna raggiungibile.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merge parziale: alcuni file richiedono un nuovo tentativo.')),
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
          // Il risultato del merge rimane visibile; l'utente può rilanciare Analizza.
        }
      }
    } on PlatformException catch (error) {
      _error(
        error.message ??
            'Sincronizzazione non avviata. I file già completati in precedenza verranno comunque riconosciuti dall’hash.',
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
      case 'finalize_windows':
        return 'Aggiornamento Windows';
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
          const Text(
            'Merge bidirezionale',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                plan.toAndroid == 0 && plan.toWindows == 0
                    ? 'Sincronizza metadata'
                    : 'Sincronizza gallerie',
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

class _SyncResultCard extends StatelessWidget {
  const _SyncResultCard({required this.result});

  final GallerySyncResult result;

  @override
  Widget build(BuildContext context) {
    final title = result.complete
        ? 'Ultimo merge completato'
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
            Text('Già presenti all’avvio: ${result.alreadyPresent}'),
            if (result.failed > 0) Text('Trasferimenti falliti: ${result.failed}'),
            if (result.pending > 0) Text('Non ancora tentati: ${result.pending}'),
            Text('Totale Android: ${result.androidCount}'),
            Text('Totale Windows: ${result.windowsCount}'),
            if (!result.complete) ...[
              const SizedBox(height: 12),
              const Text(
                'Nessun trasferimento completato viene perso: esegui di nuovo “Analizza gallerie” e poi “Sincronizza”. '
                'Gli SHA-256 già presenti verranno esclusi automaticamente dal nuovo piano.',
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
          ],
        ),
      ),
    );
  }
}
