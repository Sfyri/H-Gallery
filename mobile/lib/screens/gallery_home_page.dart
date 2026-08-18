import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../services/gallery_bridge.dart';
import '../theme/app_theme.dart';
import 'gallery_ready_page.dart';

class GalleryHomePage extends StatefulWidget {
  const GalleryHomePage({required this.galleryService, super.key});

  final GalleryService galleryService;

  @override
  State<GalleryHomePage> createState() => _GalleryHomePageState();
}

class _GalleryHomePageState extends State<GalleryHomePage> {
  List<GalleryProfile> _galleries = const [];
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final galleries = await widget.galleryService.listGalleries();
      if (!mounted) return;
      setState(() {
        _galleries = galleries;
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

    var pendingName = '';
    final nameHint = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aggiungi galleria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Puoi assegnarle un nome oppure lasciare il campo vuoto e usare il nome della cartella.',
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextFormField(
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Nome galleria (opzionale)',
                hintText: 'Main Gallery',
              ),
              onChanged: (value) => pendingName = value,
              onFieldSubmitted: (value) {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(value.trim());
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            onPressed: () {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop(pendingName.trim());
            },
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Scegli cartella'),
          ),
        ],
      ),
    );

    if (nameHint == null || !mounted) return;

    setState(() => _working = true);
    try {
      final gallery = await widget.galleryService.addGallery(nameHint: nameHint);
      if (gallery == null || !mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${gallery.name} è pronta.')),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showError(error.message ?? 'Impossibile collegare la cartella scelta.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect(GalleryProfile gallery) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Scollegare ${gallery.name}?'),
        content: const Text(
          'H-Gallery dimenticherà questa directory sul telefono. Nessun file o cartella verrà eliminato.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Scollega'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.galleryService.disconnectGallery(gallery.galleryUuid);
      await _reload();
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showError(error.message ?? 'Impossibile scollegare la galleria.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openGallery(GalleryProfile gallery) {
    if (!gallery.accessible || !gallery.layoutReady) {
      _showError(
        'La directory non è più accessibile o la struttura è incompleta. Selezionala nuovamente con “Aggiungi galleria”.',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GalleryReadyPage(gallery: gallery),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: _Header(
                    busy: _working,
                    onAdd: _working ? null : _addGallery,
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_galleries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(onAdd: _working ? null : _addGallery),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                  sliver: SliverList.separated(
                    itemCount: _galleries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final gallery = _galleries[index];
                      return _GalleryCard(
                        gallery: gallery,
                        onTap: () => _openGallery(gallery),
                        onDisconnect: () => _disconnect(gallery),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.busy, required this.onAdd});

  final bool busy;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'H-Gallery',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Le tue gallerie',
                style: TextStyle(color: AppTheme.muted, fontSize: 15),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Aggiungi galleria',
          onPressed: onAdd,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.panel,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Nessuna galleria collegata',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            const Text(
              'Scegli una cartella del telefono. H-Gallery creerà al suo interno la stessa struttura usata su Windows e ricorderà l’accesso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
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

class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.gallery,
    required this.onTap,
    required this.onDisconnect,
  });

  final GalleryProfile gallery;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final ready = gallery.accessible && gallery.layoutReady;
    final statusText = ready
        ? 'Pronta'
        : gallery.accessible
            ? 'Struttura incompleta'
            : 'Accesso richiesto';
    final statusColor = ready ? AppTheme.success : AppTheme.error;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.panel2,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: AppTheme.accent,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gallery.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      gallery.locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opzioni',
                onSelected: (value) {
                  if (value == 'disconnect') onDisconnect();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'disconnect',
                    child: Row(
                      children: [
                        Icon(Icons.link_off_rounded),
                        SizedBox(width: 10),
                        Text('Scollega'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
