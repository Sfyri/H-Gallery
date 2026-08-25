import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../models/story_models.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/story_management_service.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_info_sheet.dart';
import '../widgets/media_thumbnail_tile.dart';
import '../widgets/story_card.dart';
import 'batch_metadata_editor_page.dart';
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
    this.storyService = const PlatformStoryManagementService(),
    this.onChanged,
    super.key,
  });

  final GalleryProfile gallery;
  final int refreshToken;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final TrashService trashService;
  final StoryManagementService storyService;
  final VoidCallback? onChanged;

  @override
  State<GalleryMediaTab> createState() => _GalleryMediaTabState();
}

class _GalleryMediaTabState extends State<GalleryMediaTab> {
  static const int _pageSize = 120;
  static const int _maxStoryPages = 500;
  static const MediaQuerySpec _allQuery = MediaQuerySpec();

  final ScrollController _scrollController = ScrollController();
  final Map<String, Future<Uint8List?>> _coverFutures = {};
  final Set<String> _selectedSyncUuids = <String>{};

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
  bool _selectionBusy = false;

  bool get _selectionMode => _selectedSyncUuids.isNotEmpty;

  List<MediaItem> get _selectedItems => _items
      .where((item) => _selectedSyncUuids.contains(item.syncUuid))
      .toList(growable: false);

  bool get _canCreateStory {
    final selected = _selectedItems;
    return selected.length >= 2 &&
        selected.length <= _maxStoryPages &&
        selected.every((item) => item.isImage);
  }

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
        _pruneSelection();
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
      final loadedLimit = _items.length > _pageSize ? _items.length : _pageSize;
      final stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      final media = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        _allQuery,
        limit: loadedLimit,
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
        _pruneSelection();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _pruneSelection() {
    final available = _items.map((item) => item.syncUuid).toSet();
    _selectedSyncUuids.retainWhere(available.contains);
  }

  void _handleScroll() {
    if (_viewMode != _GalleryViewMode.all) return;
    if (!_scrollController.hasClients || _loadingMore) return;
    if (_scrollController.position.extentAfter < 700) {
      unawaited(_loadMore());
    }
  }

  Future<void> _scan() async {
    if (_scanning || _selectionBusy || _selectionMode) return;
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

  void _startSelection(MediaItem item) {
    if (_selectionBusy) return;
    setState(() {
      _selectedSyncUuids.add(item.syncUuid);
    });
  }

  void _toggleSelection(MediaItem item) {
    if (_selectionBusy) return;
    setState(() {
      if (!_selectedSyncUuids.add(item.syncUuid)) {
        _selectedSyncUuids.remove(item.syncUuid);
      }
    });
  }

  void _clearSelection() {
    if (_selectionBusy || _selectedSyncUuids.isEmpty) return;
    setState(_selectedSyncUuids.clear);
  }

  Future<void> _showSelectedInfo() async {
    if (_selectionBusy) return;
    final selected = _selectedItems;
    if (selected.length != 1) return;
    final item = selected.single;
    await showMediaInfoSheet(
      context: context,
      galleryUuid: widget.gallery.galleryUuid,
      item: item,
      browseService: widget.browseService,
      onTrash: () => _moveToTrash(item),
    );
  }

  Future<void> _editSelectionMetadata() async {
    if (_selectionBusy) return;
    final selected = _selectedItems;
    if (selected.isEmpty) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BatchMetadataEditorPage(
          galleryUuid: widget.gallery.galleryUuid,
          items: List<MediaItem>.unmodifiable(selected),
        ),
      ),
    );
    if (changed != true || !mounted) return;
    setState(_selectedSyncUuids.clear);
    await _refreshFromDatabase();
    widget.onChanged?.call();
    if (!mounted) return;
    _showMessage(
      selected.length == 1
          ? 'Metadati aggiornati.'
          : 'Metadati aggiornati per ${selected.length} media.',
    );
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
      _selectedSyncUuids.remove(item.syncUuid);
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

  Future<void> _moveSelectionToTrash() async {
    if (_selectionBusy) return;
    final selected = _selectedItems;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spostare nel cestino?'),
        content: Text(
          selected.length == 1
              ? selected.single.filename
              : '${selected.length} media selezionati verranno spostati nel cestino.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(selected.length == 1 ? 'Sposta' : 'Sposta tutti'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _selectionBusy = true);
    final failedIds = <String>{};
    final failureMessages = <String>[];
    var moved = 0;
    for (final item in selected) {
      try {
        await widget.trashService.moveMediaToTrash(
          widget.gallery.galleryUuid,
          item.syncUuid,
        );
        moved += 1;
      } on PlatformException catch (error) {
        failedIds.add(item.syncUuid);
        failureMessages.add(error.message ?? item.filename);
      } catch (_) {
        failedIds.add(item.syncUuid);
        failureMessages.add(item.filename);
      }
    }

    if (!mounted) return;
    setState(() {
      _selectionBusy = false;
      _selectedSyncUuids
        ..clear()
        ..addAll(failedIds);
    });
    await _refreshFromDatabase();
    if (moved > 0) widget.onChanged?.call();
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (failureMessages.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            moved == 1
                ? 'Media spostato nel cestino.'
                : '$moved media spostati nel cestino.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$moved spostati, ${failureMessages.length} non riusciti. '
            '${failureMessages.first}',
          ),
        ),
      );
    }
  }

  Future<void> _createStoryFromSelection() async {
    if (_selectionBusy) return;
    final selected = _selectedItems;
    if (selected.length < 2) {
      _showMessage('Seleziona almeno due immagini.');
      return;
    }
    if (selected.length > _maxStoryPages) {
      _showMessage('Una storia può contenere al massimo $_maxStoryPages pagine.');
      return;
    }
    if (selected.any((item) => !item.isImage)) {
      _showMessage('Le storie possono contenere soltanto immagini.');
      return;
    }

    final title = await _askStoryTitle(selected.length);
    if (title == null || !mounted) return;

    setState(() => _selectionBusy = true);
    try {
      final value = await widget.storyService.createFromGallery(
        widget.gallery.galleryUuid,
        title: title,
        syncUuids: selected.map((item) => item.syncUuid).toList(growable: false),
      );
      if (!mounted) return;
      setState(_selectedSyncUuids.clear);
      await _refreshFromDatabase();
      widget.onChanged?.call();
      if (!mounted) return;
      final pageCount = _readInt(value['pageCount'], fallback: selected.length);
      final createdTitle = value['title']?.toString().trim();
      _showMessage(
        'Storia ${createdTitle == null || createdTitle.isEmpty ? title : createdTitle} '
        'creata con $pageCount pagine.',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Creazione della storia non riuscita.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Creazione della storia non riuscita.');
    } finally {
      if (mounted) setState(() => _selectionBusy = false);
    }
  }

  Future<String?> _askStoryTitle(int pageCount) async {
    var draftTitle = '';
    String? validationMessage;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crea storia'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$pageCount immagini verranno usate nell’ordine della galleria.'),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Titolo',
                  errorText: validationMessage,
                ),
                onChanged: (value) => draftTitle = value,
                onSubmitted: (_) {
                  final title = draftTitle.trim();
                  if (title.isEmpty) {
                    setDialogState(() => validationMessage = 'Inserisci un titolo.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(title);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final title = draftTitle.trim();
                if (title.isEmpty) {
                  setDialogState(() => validationMessage = 'Inserisci un titolo.');
                  return;
                }
                Navigator.of(dialogContext).pop(title);
              },
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
  }

  int _readInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    if (_selectionMode) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StoryReaderPage(
          gallery: widget.gallery,
          story: story,
          mediaService: widget.mediaService,
          browseService: widget.browseService,
          storyService: widget.storyService,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshFromDatabase();
    widget.onChanged?.call();
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
                    onSelectionChanged: _selectionBusy
                        ? null
                        : (value) {
                            setState(() {
                              _viewMode = value.first;
                              if (_viewMode != _GalleryViewMode.all) {
                                _selectedSyncUuids.clear();
                              }
                            });
                          },
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
      if (_selectionMode)
        SliverPersistentHeader(
          pinned: true,
          delegate: _SelectionHeaderDelegate(
            child: _SelectionBar(
              count: _selectedSyncUuids.length,
              busy: _selectionBusy,
              canShowInfo: _selectedSyncUuids.length == 1,
              canCreateStory: _canCreateStory,
              onClose: _clearSelection,
              onInfo: _showSelectedInfo,
              onEditMetadata: _editSelectionMetadata,
              onCreateStory: _createStoryFromSelection,
              onTrash: _moveSelectionToTrash,
            ),
          ),
        ),
      if (_stories.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Text(
              'Storie',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
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
                  onTap: _selectionMode ? () {} : () => _openStory(story),
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
              child: Text(
                'Media',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                final selected = _selectedSyncUuids.contains(item.syncUuid);
                return Stack(
                  key: ValueKey(item.syncUuid),
                  fit: StackFit.expand,
                  children: [
                    MediaThumbnailTile(
                      galleryUuid: widget.gallery.galleryUuid,
                      item: item,
                      mediaService: widget.mediaService,
                      onTap: _selectionMode
                          ? () => _toggleSelection(item)
                          : () => _openViewer(index),
                      onLongPress: () => _startSelection(item),
                    ),
                    if (selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.accent, width: 3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        top: 7,
                        right: 7,
                        child: IgnorePointer(
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.panel, width: 2),
                            ),
                            child: const Icon(Icons.check_rounded, size: 18),
                          ),
                        ),
                      ),
                  ],
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

class _SelectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SelectionHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 80;

  @override
  double get maxExtent => 80;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _SelectionHeaderDelegate oldDelegate) => true;
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.canShowInfo,
    required this.canCreateStory,
    required this.onClose,
    required this.onInfo,
    required this.onEditMetadata,
    required this.onCreateStory,
    required this.onTrash,
  });

  final int count;
  final bool busy;
  final bool canShowInfo;
  final bool canCreateStory;
  final VoidCallback onClose;
  final Future<void> Function() onInfo;
  final Future<void> Function() onEditMetadata;
  final Future<void> Function() onCreateStory;
  final Future<void> Function() onTrash;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Material(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Chiudi selezione',
                onPressed: busy ? null : onClose,
                icon: const Icon(Icons.close_rounded),
              ),
              Expanded(
                child: Text(
                  '$count selezionat${count == 1 ? 'o' : 'i'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  tooltip: 'Informazioni',
                  onPressed: canShowInfo ? onInfo : null,
                  icon: const Icon(Icons.info_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Modifica metadati',
                  onPressed: onEditMetadata,
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: canCreateStory
                      ? 'Crea storia'
                      : 'Servono 2–500 immagini',
                  onPressed: canCreateStory ? onCreateStory : null,
                  icon: const Icon(Icons.auto_stories_outlined),
                ),
                IconButton(
                  tooltip: 'Sposta nel cestino',
                  onPressed: onTrash,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
