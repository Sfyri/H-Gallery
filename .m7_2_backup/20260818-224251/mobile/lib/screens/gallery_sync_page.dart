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
  StreamSubscription<GallerySyncProgress>? _progressSubscription;

  List<GalleryProfile> _galleries = const [];
  GalleryProfile? _selected;
  GallerySyncPlan? _plan;
  GallerySyncResult? _result;
  GallerySyncProgress? _progress;
  bool _loading = true;
  bool _analyzing = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _progressSubscription = _syncService.progress.listen((value) {
      if (mounted) setState(() => _progress = value);
    });
    _loadGalleries();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _loadGalleries() async {
    try {
      final galleries = (await _galleryService.listGalleries())
          .where((gallery) => gallery.accessible && gallery.layoutReady)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _galleries = galleries;
        _selected = galleries.length == 1 ? galleries.first : null;
        _loading = false;
      });
      if (galleries.length == 1) await _analyze();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error.message ?? 'Impossibile leggere le gallerie Android.');
    }
  }

  Future<void> _analyze() async {
    final gallery = _selected;
    if (gallery == null || _analyzing || _syncing) return;
    setState(() {
      _analyzing = true;
      _plan = null;
      _result = null;
      _progress = null;
    });
    try {
      final plan = await _syncService.analyze(gallery);
      if (!mounted) return;
      setState(() => _plan = plan);
    } on PlatformException catch (error) {
      _showError(error.message ?? 'Analisi delle gallerie non riuscita.');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _sync() async {
    final gallery = _selected;
    final plan = _plan;
    if (gallery == null || plan == null || _syncing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizzare le gallerie?'),
        content: Text(
          'M7 eseguirà un merge additivo. Verranno copiati ${plan.toAndroid} media sul telefono '
          'e ${plan.toWindows} sul PC. I file con lo stesso SHA-256 non saranno duplicati. '
          'In caso di stesso percorso ma contenuto diverso, entrambi i file saranno conservati con un nome alternativo. '
          'Le eliminazioni non vengono propagate in questa versione.',
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
      _result = null;
      _progress = const GallerySyncProgress(
        phase: 'start',
        processed: 0,
        total: 1,
        current: 'Preparazione sincronizzazione',
      );
    });
    try {
      final result = await _syncService.run(gallery);
      if (!mounted) return;
      setState(() => _result = result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merge M7 completato.')),
      );
      final refreshed = await _syncService.analyze(gallery);
      if (mounted) setState(() => _plan = refreshed);
    } on PlatformException catch (error) {
      _showError(error.message ?? 'Sincronizzazione non riuscita. Puoi rilanciarla: M7 riparte dai file mancanti.');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _showError(String message) {
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
      case 'metadata_android':
        return 'Merge metadata Android';
      case 'metadata_windows':
        return 'Merge metadata Windows';
      case 'finalize_windows':
        return 'Aggiornamento Windows';
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
      appBar: AppBar(title: const Text('Sincronizza gallerie')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'M7 · Merge bidirezionale',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scegli la galleria Android da unire alla galleria attiva su Windows. '
            'Il confronto usa SHA-256: i contenuti già presenti non vengono copiati di nuovo.',
            style: TextStyle(color: AppTheme.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (_galleries.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Non ci sono gallerie Android accessibili da sincronizzare.'),
              ),
            )
          else ...[
            DropdownButtonFormField<GalleryProfile>(
              initialValue: _selected,
              decoration: const InputDecoration(
                labelText: 'Galleria Android',
                prefixIcon: Icon(Icons.folder_rounded),
              ),
              items: _galleries
                  .map(
                    (gallery) => DropdownMenuItem<GalleryProfile>(
                      value: gallery,
                      child: Text(gallery.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _syncing || _analyzing
                  ? null
                  : (value) {
                      setState(() {
                        _selected = value;
                        _plan = null;
                        _result = null;
                      });
                    },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _selected == null || _syncing || _analyzing ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.manage_search_rounded),
              label: Text(_analyzing ? 'Analisi…' : 'Analizza gallerie'),
            ),
          ],
          if (plan != null) ...[
            const SizedBox(height: 22),
            _PlanCard(plan: plan, bytes: _bytes),
            if (plan.pathConflicts > 0) ...[
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.call_split_rounded, color: AppTheme.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${plan.pathConflicts} collisioni di percorso: M7 conserverà entrambe le versioni rinominando solo quella in arrivo.',
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ],
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
            if (plan.toAndroid == 0 && plan.toWindows == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'I file sono già allineati. Puoi comunque avviare la sincronizzazione per unire tag, artisti, personaggi e stato AI.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
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
                    Text(_phaseLabel(progress), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: progress.fraction),
                    const SizedBox(height: 10),
                    Text(progress.current, style: const TextStyle(color: AppTheme.muted)),
                    if (progress.total > 1)
                      Text('${progress.processed}/${progress.total}', style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                    const SizedBox(height: 10),
                    const Text(
                      'Non chiudere H-Gallery durante il trasferimento. Se la rete cade, rilancia il merge: i file già completati verranno riconosciuti dall’hash.',
                      style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.success),
                        SizedBox(width: 9),
                        Text('Ultimo merge completato', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Windows → Android: ${_result!.downloaded}'),
                    Text('Android → Windows: ${_result!.uploaded}'),
                    Text('Già presenti: ${_result!.alreadyPresent}'),
                    Text('Totale Android: ${_result!.androidCount}'),
                    Text('Totale Windows: ${_result!.windowsCount}'),
                    if (_result!.unresolvedWindowsCharacters > 0)
                      Text(
                        'Collegamenti personaggio non risolti su Windows: ${_result!.unresolvedWindowsCharacters}',
                        style: const TextStyle(color: AppTheme.error),
                      ),
                  ],
                ),
              ),
            ),
          ],
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
          ],
        ),
      ),
    );
  }
}
