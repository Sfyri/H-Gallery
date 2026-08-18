
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';
import 'media_viewer_page.dart';

class GalleryReadyPage extends StatefulWidget {
  const GalleryReadyPage({
    required this.gallery,
    this.mediaService = const PlatformMediaService(),
    super.key,
  });

  final GalleryProfile gallery;
  final MediaService mediaService;

  @override
  State<GalleryReadyPage> createState() => _GalleryReadyPageState();
}

class _GalleryReadyPageState extends State<GalleryReadyPage> {
  static const int _pageSize = 120;

  final ScrollController _scrollController = ScrollController();
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};

  GalleryStats _stats = GalleryStats.empty;
  List<MediaItem> _media = const [];
  bool _initialLoading = true;
  bool _scanning = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      if (!mounted) return;
      _stats = stats;

      if (stats.total == 0) {
        setState(() => _initialLoading = false);
        await _scan(showResult: false);
        return;
      }

      await _loadFirstPage();
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _error = error.message ?? 'Impossibile leggere il database della galleria.';
      });
    }
  }

  Future<void> _loadFirstPage() async {
    try {
      final items = await widget.mediaService.listMedia(
        widget.gallery.galleryUuid,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _media = items;
        _hasMore = items.length == _pageSize && items.length < _stats.total;
        _initialLoading = false;
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _error = error.message ?? 'Impossibile leggere i media indicizzati.';
      });
    }
  }

  Future<void> _scan({bool showResult = true}) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      final result = await widget.mediaService.scanGallery(widget.gallery.galleryUuid);
      if (!mounted) return;

      _thumbnailFutures.clear();
      setState(() {
        _stats = result;
        _media = const [];
        _hasMore = result.total > 0;
      });
      await _loadFirstPage();

      if (!mounted || !showResult) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scanMessage(result))),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message ?? 'La scansione della galleria non è riuscita.';
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  String _scanMessage(ScanResult result) {
    if (!result.hasChanges) {
      return 'Rilettura completata: nessuna modifica, ${result.total} media.';
    }
    return 'Rilettura completata: +${result.added} nuovi, '
        '${result.updated} modificati, ${result.moved} spostati, '
        '${result.removed} non più presenti.';
  }

  void _handleScroll() {
    if (!_hasMore || _loadingMore || _initialLoading || _scanning) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter < 900) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.mediaService.listMedia(
        widget.gallery.galleryUuid,
        limit: _pageSize,
        offset: _media.length,
      );
      if (!mounted) return;
      setState(() {
        _media = [..._media, ...next];
        _hasMore = next.length == _pageSize && _media.length < _stats.total;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Impossibile caricare altri media.')),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openViewer(int index) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(
          gallery: widget.gallery,
          initialItems: _media,
          initialIndex: index,
          totalCount: _stats.total,
          mediaService: widget.mediaService,
        ),
      ),
    );
  }

  Future<void> _showMediaInfo(MediaItem item) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.filename,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _InfoRow(label: 'Tipo', value: item.typeLabel),
              _InfoRow(label: 'Dimensione', value: _formatBytes(item.sizeBytes)),
              _InfoRow(label: 'Percorso', value: item.relativePath),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 100 ? 0 : 2)} GB';
  }

  Future<Uint8List?> _thumbnailFor(MediaItem item) {
    return _thumbnailFutures.putIfAbsent(
      item.syncUuid,
      () => widget.mediaService.loadThumbnail(
        widget.gallery.galleryUuid,
        item.syncUuid,
        maxPx: 420,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.gallery.name),
            Text(
              '${_stats.total} media',
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Rileggi cartelle',
            onPressed: _scanning ? null : () => _scan(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _media.isEmpty) {
      return _ErrorState(message: _error!, onRetry: () => _scan());
    }

    if (_stats.total == 0 && !_scanning) {
      return _EmptyGallery(onScan: () => _scan());
    }

    return RefreshIndicator(
      onRefresh: () => _scan(showResult: false),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            sliver: SliverToBoxAdapter(child: _StatsBar(stats: _stats)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.builder(
              itemCount: _media.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final item = _media[index];
                return _MediaTile(
                  item: item,
                  thumbnail: _thumbnailFor(item),
                  onTap: () => _openViewer(index),
                  onLongPress: () => _showMediaInfo(item),
                );
              },
            ),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats});

  final GalleryStats stats;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatChip(icon: Icons.image_rounded, label: '${stats.photos} foto'),
          const SizedBox(width: 8),
          _StatChip(icon: Icons.gif_box_rounded, label: '${stats.animated} GIF'),
          const SizedBox(width: 8),
          _StatChip(icon: Icons.movie_rounded, label: '${stats.videos} video'),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.item,
    required this.thumbnail,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final Future<Uint8List?> thumbnail;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: thumbnail,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null && bytes.isNotEmpty) {
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, _, _) => const _MediaPlaceholder(),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ColoredBox(
                    color: AppTheme.panel2,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return const _MediaPlaceholder();
              },
            ),
            if (item.isVideo || item.isAnimated)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xB8000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isVideo ? Icons.play_arrow_rounded : Icons.gif_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        item.isVideo ? 'VIDEO' : 'GIF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.panel2,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppTheme.muted, size: 30),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 54, color: AppTheme.muted),
            const SizedBox(height: 16),
            const Text(
              'Nessun media indicizzato',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aggiungi immagini, GIF o video nelle cartelle della galleria e usa Rileggi cartelle.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.45),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Rileggi cartelle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(color: AppTheme.muted)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
