import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/story_models.dart';
import '../screens/batch_metadata_editor_page.dart';
import '../screens/media_viewer_page.dart';
import '../screens/story_reader_page.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/story_management_service.dart';
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
    this.storyService = const PlatformStoryManagementService(),
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
  final StoryManagementService storyService;
  final Future<void> Function()? onChanged;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<int>? onTotalChanged;

  @override
  State<MediaQueryGrid> createState() => _MediaQueryGridState();
}

class _MediaQueryGridState extends State<MediaQueryGrid> {
  static const int _pageSize = 120;
  static const int _maxStoryPages = 500;

  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedSyncUuids = <String>{};

  List<MediaItem> _items = const [];
  List<GalleryStorySummary> _stories = const [];
  int _mediaTotal = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _selectionBusy = false;
  Object? _error;
  int _requestGeneration = 0;

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
    unawaited(_loadFirstPage());
  }

  @override
  void didUpdateWidget(covariant MediaQueryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.gallery.galleryUuid != widget.gallery.galleryUuid) {
      _selectedSyncUuids.clear();
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
        final available = _items.map((item) => item.syncUuid).toSet();
        _selectedSyncUuids.retainWhere(available.contains);
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
      if (!mounted || generation != _requestGeneration || result.items.isEmpty) {
        return;
      }
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

  void _startSelection(MediaItem item) {
    if (_selectionBusy) return;
    setState(() => _selectedSyncUuids.add(item.syncUuid));
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
    await _loadFirstPage();
    await widget.onChanged?.call();
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
      setState(() => _selectedSyncUuids.remove(item.syncUuid));
      await _loadFirstPage();
      await widget.onChanged?.call();
      if (!mounted) return;
      _showMessage('Media spostato nel cestino.');
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(error.message ?? 'Operazione non riuscita.');
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
      _selectedSyncUuids.clear();
      _selectionBusy = false;
    });
    await _loadFirstPage();
    if (!mounted) return;
    setState(() {
      final available = _items.map((item) => item.syncUuid).toSet();
      _selectedSyncUuids.addAll(failedIds.where(available.contains));
    });
    if (moved > 0) await widget.onChanged?.call();
    if (!mounted) return;

    if (failureMessages.isEmpty) {
      _showMessage(
        moved == 1
            ? 'Media spostato nel cestino.'
            : '$moved media spostati nel cestino.',
      );
    } else {
      _showMessage(
        '$moved spostati, ${failureMessages.length} non riusciti. '
        '${failureMessages.first}',
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
      await _loadFirstPage();
      await widget.onChanged?.call();
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

  Future<void> _openViewer(int index) async {
    if (_selectionMode) return;
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
    await _loadFirstPage();
    await widget.onChanged?.call();
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

    return Column(
      children: [
        if (_selectionMode)
          _SelectionBar(
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _selectionBusy ? () async {} : _loadFirstPage,
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
                                        border: Border.all(
                                          color: AppTheme.accent,
                                          width: 3,
                                        ),
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
                                        border: Border.all(
                                          color: AppTheme.panel,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                        childCount: _items.length,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
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
          ),
        ),
      ],
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

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile leggere i risultati.';
    }
    return 'Impossibile leggere i risultati.';
  }
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
            const Icon(
              Icons.error_outline_rounded,
              size: 50,
              color: AppTheme.error,
            ),
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
