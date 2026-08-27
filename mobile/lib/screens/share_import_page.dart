import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../services/gallery_bridge.dart';
import '../services/shared_media_service.dart';

class ShareImportPage extends StatefulWidget {
  const ShareImportPage({
    required this.batch,
    required this.galleryService,
    required this.sharedMediaService,
    super.key,
  });

  final SharedMediaBatch batch;
  final GalleryService galleryService;
  final SharedMediaService sharedMediaService;

  @override
  State<ShareImportPage> createState() => _ShareImportPageState();
}

class _ShareImportPageState extends State<ShareImportPage> {
  late SharedMediaBatch _batch;
  List<GalleryProfile> _galleries = const [];
  String? _selectedGalleryUuid;
  String _query = '';
  bool _loading = true;
  bool _working = false;
  bool _removeOriginals = true;

  @override
  void initState() {
    super.initState();
    _batch = widget.batch;
    _loadGalleries();
  }

  List<GalleryProfile> get _readyGalleries => _galleries
      .where((gallery) => gallery.accessible && gallery.layoutReady)
      .toList(growable: false);

  List<GalleryProfile> get _visibleGalleries {
    final ready = _readyGalleries;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return ready;
    return ready
        .where(
          (gallery) =>
              gallery.name.toLowerCase().contains(query) ||
              gallery.directoryName.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _loadGalleries({String? preferGalleryUuid}) async {
    try {
      final galleries = await widget.galleryService.listGalleries();
      if (!mounted) return;
      final ready = galleries
          .where((gallery) => gallery.accessible && gallery.layoutReady)
          .toList(growable: false);
      var selection = preferGalleryUuid ?? _selectedGalleryUuid;
      if (!ready.any((gallery) => gallery.galleryUuid == selection)) {
        selection = ready.isEmpty ? null : ready.first.galleryUuid;
      }
      setState(() {
        _galleries = galleries;
        _selectedGalleryUuid = selection;
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error.message ?? 'Impossibile leggere le gallerie.');
    }
  }

  Future<void> _addGallery() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final gallery = await widget.galleryService.addGallery();
      if (!mounted) return;
      await _loadGalleries(preferGalleryUuid: gallery?.galleryUuid);
    } on PlatformException catch (error) {
      if (mounted) {
        _showError(error.message ?? 'Impossibile aggiungere la galleria.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await widget.sharedMediaService.clearPendingShare(_batch.token);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      _showError(error.message ?? 'Impossibile annullare la condivisione.');
    }
  }

  Future<void> _import() async {
    final galleryUuid = _selectedGalleryUuid;
    if (_working || galleryUuid == null || _batch.items.isEmpty) return;

    setState(() => _working = true);
    try {
      final result = await widget.sharedMediaService.importPendingShare(
        token: _batch.token,
        galleryUuid: galleryUuid,
        removeOriginals: _removeOriginals,
      );
      if (!mounted) return;

      await _showResult(result);
      if (!mounted) return;

      if (result.remainingPending > 0) {
        final nextBatch = await widget.sharedMediaService.getPendingShare();
        if (!mounted) return;
        if (nextBatch != null) {
          setState(() {
            _batch = nextBatch;
            _working = false;
          });
          return;
        }
      }
      Navigator.of(context).pop();
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'STALE_SHARE') {
        final latest = await widget.sharedMediaService.getPendingShare();
        if (!mounted) return;
        if (latest != null) {
          setState(() {
            _batch = latest;
            _working = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'È arrivata una nuova condivisione. Ho aggiornato i file ricevuti.',
              ),
            ),
          );
          return;
        }
      }
      setState(() => _working = false);
      _showError(error.message ?? 'Importazione non riuscita.');
    }
  }

  Future<void> _showResult(SharedMediaImportResult result) async {
    final lines = <String>[
      '${result.copied} file copiati in .toDo.',
      if (result.failed > 0) '${result.failed} file non copiati.',
      if (result.removeOriginalsRequested)
        '${result.deletedOriginals} originali eliminati.',
      if (result.removeOriginalsRequested && result.originalsNotDeleted > 0)
        '${result.originalsNotDeleted} originali non eliminabili o mantenuti.',
    ];
    if (result.failures.isNotEmpty) {
      lines.add('');
      lines.addAll(result.failures.take(5));
      if (result.failures.length > 5) {
        lines.add('…e altri ${result.failures.length - 5}.');
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(result.failed == 0 ? 'Importazione completata' : 'Importazione parziale'),
        content: SingleChildScrollView(child: Text(lines.join('\n'))),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ready = _readyGalleries;
    final visible = _visibleGalleries;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Importa in H-Gallery'),
          leading: IconButton(
            tooltip: 'Annulla',
            onPressed: _working ? null : _cancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  _ShareSummary(batch: _batch),
                  const SizedBox(height: 18),
                  Text(
                    'Galleria di destinazione',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  if (ready.isEmpty)
                    _NoGalleryCard(onAdd: _working ? null : _addGallery)
                  else ...[
                    if (ready.length > 6) ...[
                      TextField(
                        enabled: !_working,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'Cerca galleria',
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('Nessuna galleria corrisponde alla ricerca.'),
                      )
                    else
                      ...visible.map(
                        (gallery) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _GalleryChoice(
                            gallery: gallery,
                            selected: gallery.galleryUuid == _selectedGalleryUuid,
                            enabled: !_working,
                            onTap: () => setState(
                              () => _selectedGalleryUuid = gallery.galleryUuid,
                            ),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _working ? null : _addGallery,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Aggiungi galleria'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _removeOriginals,
                    onChanged: _working
                        ? null
                        : (value) => setState(
                              () => _removeOriginals = value ?? false,
                            ),
                    title: const Text('Rimuovi gli originali dopo l’importazione'),
                    subtitle: const Text(
                      'H-Gallery copia e verifica prima i file. Android può chiedere una conferma per eliminare gli originali; i provider che non permettono la cancellazione vengono lasciati intatti.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _working ||
                            _selectedGalleryUuid == null ||
                            _batch.items.isEmpty
                        ? null
                        : _import,
                    icon: _working
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_done_rounded),
                    label: Text(_working ? 'Importazione…' : 'Importa in .toDo'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ShareSummary extends StatelessWidget {
  const _ShareSummary({required this.batch});

  final SharedMediaBatch batch;

  @override
  Widget build(BuildContext context) {
    final preview = batch.items.take(5).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.ios_share_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    batch.count == 1
                        ? '1 file ricevuto'
                        : '${batch.count} file ricevuti',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (batch.totalSizeBytes > 0)
                  Text(_formatBytes(batch.totalSizeBytes)),
              ],
            ),
            if (batch.rejectedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${batch.rejectedCount} elementi ignorati perché non sono formati supportati da H-Gallery.',
              ),
            ],
            if (preview.isNotEmpty) ...[
              const Divider(height: 24),
              ...preview.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(
                        item.mimeType.startsWith('video/')
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (batch.count > preview.length)
                Text('…e altri ${batch.count - preview.length}.'),
            ],
            if (batch.items.isEmpty) ...[
              const Divider(height: 24),
              const Text(
                'Nessuna immagine o video supportato è presente nella condivisione.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoGalleryCard extends StatelessWidget {
  const _NoGalleryCard({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Non ci sono gallerie pronte a ricevere i file.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: const Text('Aggiungi galleria'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryChoice extends StatelessWidget {
  const _GalleryChoice({
    required this.gallery,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final GalleryProfile gallery;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
        title: Text(gallery.name),
        subtitle: Text(
          gallery.locationLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected ? const Icon(Icons.check_rounded) : null,
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
