import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../models/story_models.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_info_sheet.dart';
import '../widgets/media_thumbnail_tile.dart';
import '../widgets/story_card.dart';
import 'filtered_media_page.dart';
import 'media_viewer_page.dart';
import 'series_browser_page.dart';
import 'story_reader_page.dart';

enum _GalleryViewMode { series, all }

class GalleryMediaTab extends StatefulWidget {
  const GalleryMediaTab({
    required this.gallery,
    this.refreshToken = 0,
    this.mediaService = const PlatformMediaService(),
    this.browseService = const PlatformGalleryBrowseService(),
    this.trashService = const PlatformTrashService(),
    this.onChanged,
    super.key,
  });

  final GalleryProfile gallery;
  final int refreshToken;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final TrashService trashService;
  final VoidCallback? onChanged;

  @override
  State<GalleryMediaTab> createState() => _GalleryMediaTabState();
}

class _GalleryMediaTabState extends State<GalleryMediaTab> {
  static const int _pageSize = 120;
  static const MediaQuerySpec _allQuery = MediaQuerySpec();

  final ScrollController _scrollController = ScrollController();
  final Map<String, Future<Uint8List?>> _coverFutures = {};

  GalleryStats _stats = GalleryStats.empty;
  GalleryBrowseCatalog? _browseCatalog;
  List<MediaItem> _items = const [];
  List<GalleryStorySummary> _stories = const [];
  int _mediaTotal = 0;
  _GalleryViewMode _viewMode = _GalleryViewMode.series;
  Object? _error;
  bool _initialLoading = true;
  bool _scanning = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadInitial());
  }

  @override
  void didUpdateWidget(covariant GalleryMediaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_refreshFromDatabase());
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      var stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      if (stats.total == 0) {
        stats = await widget.mediaService.scanGallery(widget.gallery.galleryUuid);
      }
      final media = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        _allQuery,
        limit: _pageSize,
      );
      final stories = await widget.browseService.queryStories(
        widget.gallery.galleryUuid,
        _allQuery,
      );
      final catalog = await widget.browseService.getBrowseCatalog(
        widget.gallery.galleryUuid,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _items = media.items;
        _mediaTotal = media.total;
        _stories = stories;
        _browseCatalog = catalog;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  Future<void> _refreshFromDatabase() async {
    try {
      final stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      final media = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        _allQuery,
        limit: _pageSize,
      );
      final stories = await widget.browseService.queryStories(
        widget.gallery.galleryUuid,
        _allQuery,
      );
      final catalog = await widget.browseService.getBrowseCatalog(
        widget.gallery.galleryUuid,
      );
      if (!mounted) return;
      _coverFutures.clear();
      setState(() {
        _stats = stats;
        _items = media.items;
        _mediaTotal = media.total;
        _stories = stories;
        _browseCatalog = catalog;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _handleScroll() {
    if (_viewMode != _GalleryViewMode.all) return;
    if (!_scrollController.hasClients || _loadingMore) return;
    if (_scrollController.position.extentAfter < 700) {
      unawaited(_loadMore());
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final scan = await widget.mediaService.scanGallery(widget.gallery.galleryUuid);
      final stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      final media = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        _allQuery,
        limit: _pageSize,
      );
      final stories = await widget.browseService.queryStories(
        widget.gallery.galleryUuid,
        _allQuery,
      );
      final catalog = await widget.browseService.getBrowseCatalog(
        widget.gallery.galleryUuid,
      );
      if (!mounted) return;
      _coverFutures.clear();
      setState(() {
        _stats = stats;
        _items = media.items;
        _mediaTotal = media.total;
        _stories = stories;
        _browseCatalog = catalog;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_scanSummary(scan))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _mediaTotal) return;
    _loadingMore = true;
    try {
      final next = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        _allQuery,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted || next.items.isEmpty) return;
      final known = _items.map((item) => item.syncUuid).toSet();
      final unique = next.items.where((item) => known.add(item.syncUuid)).toList();
      if (unique.isEmpty) return;
      setState(() {
        _items = [..._items, ...unique];
        _mediaTotal = next.total;
      });
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _moveToTrash(MediaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spostare nel cestino?'),
        content: Text(item.filename),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sposta'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.trashService.moveMediaToTrash(
        widget.gallery.galleryUuid,
        item.syncUuid,
      );
      if (!mounted) return;
      await _refreshFromDatabase();
      widget.onChanged?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Media spostato nel cestino.')),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Operazione non riuscita.')),
      );
    }
  }

  Future<void> _handleNestedChange() async {
    widget.onChanged?.call();
    await _refreshFromDatabase();
  }

  Future<void> _openViewer(int index) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(
          gallery: widget.gallery,
          initialItems: List<MediaItem>.of(_items),
          initialIndex: index,
          totalCount: _mediaTotal,
          mediaService: FilteredMediaService(
            base: widget.mediaService,
            browse: widget.browseService,
            query: _allQuery,
          ),
        ),
      ),
    );
  }

  Future<void> _openStory(GalleryStorySummary story) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StoryReaderPage(
          gallery: widget.gallery,
          story: story,
          mediaService: widget.mediaService,
          browseService: widget.browseService,
        ),
      ),
    );
  }

  Future<Uint8List?> _coverFor(GalleryCollection collection) {
    if (collection.coverSyncUuid.isEmpty) return Future.value(null);
    return _coverFutures.putIfAbsent(
      collection.relativePath,
      () => widget.mediaService.loadThumbnail(
        widget.gallery.galleryUuid,
        collection.coverSyncUuid,
        maxPx: 520,
      ),
    );
  }

  void _openCollection(GalleryCollection collection) {
    if (collection.isSeries) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => SeriesBrowserPage(
            gallery: widget.gallery,
            series: collection,
            mediaService: widget.mediaService,
            browseService: widget.browseService,
            onChanged: _handleNestedChange,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => FilteredMediaPage(
          gallery: widget.gallery,
          title: collection.name,
          query: MediaQuerySpec(relativePrefix: collection.relativePath),
          mediaService: widget.mediaService,
          browseService: widget.browseService,
          onChanged: _handleNestedChange,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty && _stories.isEmpty) {
      return _ErrorState(message: _errorMessage(_error), onRetry: _loadInitial);
    }

    return RefreshIndicator(
      onRefresh: _scan,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatsCard(stats: _stats),
                  const SizedBox(height: 12),
                  SegmentedButton<_GalleryViewMode>(
                    segments: const [
                      ButtonSegment<_GalleryViewMode>(
                        value: _GalleryViewMode.series,
                        icon: Icon(Icons.folder_copy_outlined),
                        label: Text('Serie'),
                      ),
                      ButtonSegment<_GalleryViewMode>(
                        value: _GalleryViewMode.all,
                        icon: Icon(Icons.grid_view_rounded),
                        label: Text('Tutti'),
                      ),
                    ],
                    selected: <_GalleryViewMode>{_viewMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) {
                      setState(() => _viewMode = value.first);
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(_scanning ? 'Rilettura in corso…' : 'Rileggi cartelle'),
                  ),
                ],
              ),
            ),
          ),
          if (_viewMode == _GalleryViewMode.series)
            ..._buildSeriesSlivers()
          else
            ..._buildAllMediaSlivers(),
        ],
      ),
    );
  }

  List<Widget> _buildSeriesSlivers() {
    final catalog = _browseCatalog;
    final collections = catalog == null
        ? const <GalleryCollection>[]
        : <GalleryCollection>[...catalog.series, ...catalog.special];

    if (collections.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptySeriesState(),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final collection = collections[index];
              return _SeriesCard(
                collection: collection,
                cover: _coverFor(collection),
                onTap: () => _openCollection(collection),
              );
            },
            childCount: collections.length,
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.86,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAllMediaSlivers() {
    if (_items.isEmpty && _stories.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyGalleryState(),
        ),
      ];
    }

    return [
      if (_stories.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Text('Storie', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final story = _stories[index];
                return StoryCard(
                  key: ValueKey('story:${story.relativePath}'),
                  galleryUuid: widget.gallery.galleryUuid,
                  story: story,
                  mediaService: widget.mediaService,
                  onTap: () => _openStory(story),
                );
              },
              childCount: _stories.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
          ),
        ),
      ],
      if (_items.isNotEmpty) ...[
        if (_stories.isNotEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 6),
              child: Text('Media', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                return MediaThumbnailTile(
                  key: ValueKey(item.syncUuid),
                  galleryUuid: widget.gallery.galleryUuid,
                  item: item,
                  mediaService: widget.mediaService,
                  onTap: () => _openViewer(index),
                  onLongPress: () => showMediaInfoSheet(
                    context: context,
                    galleryUuid: widget.gallery.galleryUuid,
                    item: item,
                    browseService: widget.browseService,
                    onTrash: () => _moveToTrash(item),
                  ),
                );
              },
              childCount: _items.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
          ),
        ),
      ],
      if (_items.length < _mediaTotal)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: 28),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
    ];
  }

  String _scanSummary(ScanResult result) {
    return 'Rilettura completata: +${result.added} nuovi, '
        '${result.updated} modificati, ${result.moved} spostati, '
        '${result.removed} non più presenti.';
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Operazione non riuscita.';
    }
    return 'Operazione non riuscita.';
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final GalleryStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _StatChip(icon: Icons.folder_copy_outlined, label: 'Serie ${stats.series}'),
          _StatChip(icon: Icons.insert_drive_file_outlined, label: 'File ${stats.total}'),
          _StatChip(icon: Icons.image_outlined, label: 'Immagini ${stats.images}'),
          _StatChip(icon: Icons.movie_outlined, label: 'Video ${stats.videos}'),
          _StatChip(icon: Icons.auto_stories_outlined, label: 'Storie ${stats.stories}'),
          _StatChip(icon: Icons.auto_awesome_outlined, label: 'IA ${stats.ai}'),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.panel2,
        borderRadius: BorderRadius.circular(999),
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

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.collection,
    required this.cover,
    required this.onTap,
  });

  final GalleryCollection collection;
  final Future<Uint8List?> cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  future: cover,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes != null && bytes.isNotEmpty) {
                      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                    }
                    return ColoredBox(
                      color: AppTheme.panel2,
                      child: Center(
                        child: Icon(
                          collection.isSpecial
                              ? Icons.auto_awesome_mosaic_outlined
                              : Icons.folder_copy_outlined,
                          size: 48,
                          color: AppTheme.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${collection.mediaCount} media',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySeriesState extends StatelessWidget {
  const _EmptySeriesState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 54, color: AppTheme.muted),
            SizedBox(height: 14),
            Text(
              'Nessuna serie trovata',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 7),
            Text(
              'I media senza una struttura Serie/Personaggio restano disponibili in “Tutti”.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGalleryState extends StatelessWidget {
  const _EmptyGalleryState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 54, color: AppTheme.muted),
            SizedBox(height: 14),
            Text(
              'Nessun media organizzato',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 7),
            Text(
              'I file in .toDo non compaiono qui finché non vengono organizzati.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.4),
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
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 50, color: AppTheme.error),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
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
