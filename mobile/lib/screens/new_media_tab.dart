import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/organization_models.dart';
import '../models/scan_result.dart';
import '../services/media_bridge.dart';
import '../services/todo_media_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail_tile.dart';
import 'media_viewer_page.dart';
import 'organization_page.dart';

class NewMediaTab extends StatefulWidget {
  const NewMediaTab({
    required this.gallery,
    this.mediaService = const TodoMediaService(),
    this.onOrganized,
    super.key,
  });

  final GalleryProfile gallery;
  final MediaService mediaService;
  final VoidCallback? onOrganized;

  @override
  State<NewMediaTab> createState() => _NewMediaTabState();
}

class _NewMediaTabState extends State<NewMediaTab> {
  static const int _pageSize = 120;
  static const int _selectAllPageSize = 500;

  final ScrollController _scrollController = ScrollController();
  GalleryStats _stats = GalleryStats.empty;
  List<MediaItem> _items = const [];
  final Set<String> _selected = <String>{};
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _selectingAll = false;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 700) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload({bool showFeedback = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_items.isEmpty) _loading = true;
      _error = null;
    });
    try {
      final stats = await widget.mediaService.getStats(widget.gallery.galleryUuid);
      final items = await widget.mediaService.listMedia(
        widget.gallery.galleryUuid,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _items = items;
        _selected.removeWhere(
          (id) => !_items.any((item) => item.syncUuid == id),
        );
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('.toDo riletta: ${stats.total} media trovati.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _stats.total) return;
    _loadingMore = true;
    try {
      final next = await widget.mediaService.listMedia(
        widget.gallery.galleryUuid,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted || next.isEmpty) return;
      final known = _items.map((item) => item.syncUuid).toSet();
      final unique = next.where((item) => known.add(item.syncUuid)).toList();
      if (unique.isEmpty) return;
      setState(() => _items = [..._items, ...unique]);
    } finally {
      _loadingMore = false;
    }
  }

  void _toggleSelection(MediaItem item) {
    setState(() {
      if (!_selected.add(item.syncUuid)) {
        _selected.remove(item.syncUuid);
      }
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  Future<void> _selectAll() async {
    if (_selectingAll || _stats.total == 0) return;
    setState(() => _selectingAll = true);
    try {
      final all = <MediaItem>[];
      var offset = 0;
      while (offset < _stats.total) {
        final page = await widget.mediaService.listMedia(
          widget.gallery.galleryUuid,
          limit: _selectAllPageSize,
          offset: offset,
        );
        if (page.isEmpty) break;
        all.addAll(page);
        offset += page.length;
      }
      if (!mounted) return;
      final byId = <String, MediaItem>{
        for (final item in _items) item.syncUuid: item,
        for (final item in all) item.syncUuid: item,
      };
      setState(() {
        _items = byId.values.toList(growable: false)
          ..sort((a, b) => a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
        _selected
          ..clear()
          ..addAll(byId.keys);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  Future<void> _openViewer(int index) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(
          gallery: widget.gallery,
          initialItems: List<MediaItem>.of(_items),
          initialIndex: index,
          totalCount: _stats.total,
          mediaService: widget.mediaService,
        ),
      ),
    );
  }

  Future<void> _organizeSelected() async {
    if (_selected.isEmpty) return;

    final selectedItems = _items
        .where((item) => _selected.contains(item.syncUuid))
        .toList(growable: false);
    if (selectedItems.isEmpty) return;

    final result = await Navigator.of(context).push<OrganizationBatchResult>(
      MaterialPageRoute<OrganizationBatchResult>(
        builder: (context) => OrganizationPage(
          gallery: widget.gallery,
          items: selectedItems,
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result.hasChanges) {
      widget.onOrganized?.call();
    }
    _clearSelection();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return _ErrorState(message: _errorMessage(_error), onRetry: _reload);
    }

    return Column(
      children: [
        _TodoHeader(
          stats: _stats,
          selectedCount: _selected.length,
          selectionMode: _selectionMode,
          refreshing: _refreshing,
          selectingAll: _selectingAll,
          onRefresh: () => _reload(showFeedback: true),
          onSelectAll: _selectAll,
          onClearSelection: _clearSelection,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _reload(showFeedback: true),
            child: _items.isEmpty
                ? const _EmptyTodoState()
                : GridView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 104),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final selected = _selected.contains(item.syncUuid);
                      return MediaThumbnailTile(
                        key: ValueKey(item.syncUuid),
                        galleryUuid: widget.gallery.galleryUuid,
                        item: item,
                        mediaService: widget.mediaService,
                        selected: selected,
                        selectionMode: _selectionMode,
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(item);
                          } else {
                            _openViewer(index);
                          }
                        },
                        onLongPress: () => _toggleSelection(item),
                      );
                    },
                  ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _selectionMode
              ? SafeArea(
                  key: const ValueKey('selection-bar'),
                  top: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: const BoxDecoration(
                      color: AppTheme.panel,
                      border: Border(top: BorderSide(color: AppTheme.border)),
                    ),
                    child: FilledButton.icon(
                      onPressed: _organizeSelected,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: Text('Organizza (${_selected.length})'),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-selection-bar')),
        ),
      ],
    );
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile leggere .toDo.';
    }
    return 'Impossibile leggere .toDo.';
  }
}

class _TodoHeader extends StatelessWidget {
  const _TodoHeader({
    required this.stats,
    required this.selectedCount,
    required this.selectionMode,
    required this.refreshing,
    required this.selectingAll,
    required this.onRefresh,
    required this.onSelectAll,
    required this.onClearSelection,
  });

  final GalleryStats stats;
  final int selectedCount;
  final bool selectionMode;
  final bool refreshing;
  final bool selectingAll;
  final VoidCallback onRefresh;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inbox_outlined, color: AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectionMode ? '$selectedCount selezionati' : '.toDo',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${stats.total} media · ${stats.photos} foto · ${stats.animated} GIF · ${stats.videos} video',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rileggi .toDo',
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (stats.total > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: selectingAll ? null : onSelectAll,
                    icon: selectingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.select_all_rounded),
                    label: const Text('Seleziona tutto'),
                  ),
                  if (selectionMode) ...[
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: onClearSelection,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Annulla'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyTodoState extends StatelessWidget {
  const _EmptyTodoState();

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 58, color: AppTheme.muted),
                  SizedBox(height: 14),
                  Text(
                    '.toDo è vuota',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Metti manualmente foto, GIF o video nella cartella .toDo della galleria e poi usa Rileggi .toDo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted, height: 1.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function({bool showFeedback}) onRetry;

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
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}
