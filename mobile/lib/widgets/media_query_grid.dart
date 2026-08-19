import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/story_models.dart';
import '../screens/media_viewer_page.dart';
import '../screens/story_reader_page.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';
import 'media_info_sheet.dart';
import 'media_thumbnail_tile.dart';
import 'story_card.dart';

class MediaQueryGrid extends StatefulWidget {
  const MediaQueryGrid({
    required this.gallery,
    required this.query,
    this.refreshToken = 0,
    this.mediaService = const PlatformMediaService(),
    this.browseService = const PlatformGalleryBrowseService(),
    this.trashService = const PlatformTrashService(),
    this.onChanged,
    this.emptyTitle = 'Nessun risultato',
    this.emptyMessage = 'Nessun media corrisponde ai filtri selezionati.',
    this.onTotalChanged,
    super.key,
  });

  final GalleryProfile gallery;
  final MediaQuerySpec query;
  final int refreshToken;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final TrashService trashService;
  final Future<void> Function()? onChanged;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<int>? onTotalChanged;

  @override
  State<MediaQueryGrid> createState() => _MediaQueryGridState();
}

class _MediaQueryGridState extends State<MediaQueryGrid> {
  static const int _pageSize = 120;

  final ScrollController _scrollController = ScrollController();
  List<MediaItem> _items = const [];
  List<GalleryStorySummary> _stories = const [];
  int _mediaTotal = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_loadFirstPage());
  }

  @override
  void didUpdateWidget(covariant MediaQueryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.gallery.galleryUuid != widget.gallery.galleryUuid) {
      unawaited(_loadFirstPage());
    }
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingMore || _loading) return;
    if (_scrollController.position.extentAfter < 700) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _items = const [];
      _stories = const [];
      _mediaTotal = 0;
    });

    try {
      final mediaFuture = widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        widget.query,
        limit: _pageSize,
      );
      final storiesFuture = widget.browseService.queryStories(
        widget.gallery.galleryUuid,
        widget.query,
      );

      final mediaResult = await mediaFuture;
      final stories = await storiesFuture;
      if (!mounted || generation != _requestGeneration) return;

      setState(() {
        _items = mediaResult.items;
        _stories = stories;
        _mediaTotal = mediaResult.total;
      });
      widget.onTotalChanged?.call(mediaResult.total + stories.length);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error);
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _mediaTotal) return;
    final generation = _requestGeneration;
    _loadingMore = true;
    try {
      final result = await widget.browseService.queryMedia(
        widget.gallery.galleryUuid,
        widget.query,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted || generation != _requestGeneration || result.items.isEmpty) return;
      final known = _items.map((item) => item.syncUuid).toSet();
      final unique = result.items.where((item) => known.add(item.syncUuid)).toList();
      if (unique.isEmpty) return;
      setState(() {
        _items = [..._items, ...unique];
        _mediaTotal = result.total;
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
      await _loadFirstPage();
      await widget.onChanged?.call();
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

  Future<void> _openViewer(int index) async {
    final filteredService = FilteredMediaService(
      base: widget.mediaService,
      browse: widget.browseService,
      query: widget.query,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(
          gallery: widget.gallery,
          initialItems: List<MediaItem>.of(_items),
          initialIndex: index,
          totalCount: _mediaTotal,
          mediaService: filteredService,
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty && _stories.isEmpty) {
      return _QueryErrorState(
        message: _errorMessage(_error),
        onRetry: _loadFirstPage,
      );
    }
    if (_items.isEmpty && _stories.isEmpty) {
      return _EmptyQueryState(
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_stories.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
                child: Text(
                  'Storie',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                  padding: EdgeInsets.fromLTRB(14, 4, 14, 6),
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
        ],
      ),
    );
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile leggere i risultati.';
    }
    return 'Impossibile leggere i risultati.';
  }
}

class _EmptyQueryState extends StatelessWidget {
  const _EmptyQueryState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 52, color: AppTheme.muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueryErrorState extends StatelessWidget {
  const _QueryErrorState({required this.message, required this.onRetry});

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
