import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../models/trash_models.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';
import '../widgets/media_thumbnail_tile.dart';
import 'media_viewer_page.dart';

class TrashMediaTab extends StatefulWidget {
  const TrashMediaTab({
    required this.gallery,
    this.refreshToken = 0,
    this.trashService = const PlatformTrashService(),
    this.mediaService = const TrashMediaService(),
    this.onChanged,
    super.key,
  });

  final GalleryProfile gallery;
  final int refreshToken;
  final TrashService trashService;
  final TrashMediaService mediaService;
  final VoidCallback? onChanged;

  @override
  State<TrashMediaTab> createState() => _TrashMediaTabState();
}

class _TrashMediaTabState extends State<TrashMediaTab> {
  static const int _pageSize = 120;

  final ScrollController _scrollController = ScrollController();
  final Set<int> _selectedTrashIds = <int>{};

  TrashStats _stats = const TrashStats(total: 0, totalBytes: 0);
  List<TrashItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  Object? _error;

  bool get _selectionMode => _selectedTrashIds.isNotEmpty;

  List<TrashItem> get _selectedItems => _items
      .where((item) => _selectedTrashIds.contains(item.trashId))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant TrashMediaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
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

  void _pruneSelection() {
    final available = _items.map((item) => item.trashId).toSet();
    _selectedTrashIds.retainWhere(available.contains);
  }

  void _startSelection(TrashItem item) {
    if (_busy) return;
    setState(() => _selectedTrashIds.add(item.trashId));
  }

  void _toggleSelection(TrashItem item) {
    if (_busy) return;
    setState(() {
      if (!_selectedTrashIds.add(item.trashId)) {
        _selectedTrashIds.remove(item.trashId);
      }
    });
  }

  void _clearSelection() {
    if (_busy || _selectedTrashIds.isEmpty) return;
    setState(_selectedTrashIds.clear);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await widget.trashService.getStats(widget.gallery.galleryUuid);
      final items = await widget.trashService.listItems(
        widget.gallery.galleryUuid,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _items = items;
        _pruneSelection();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _stats.total) return;
    _loadingMore = true;
    try {
      final next = await widget.trashService.listItems(
        widget.gallery.galleryUuid,
        limit: _pageSize,
        offset: _items.length,
      );
      if (!mounted || next.isEmpty) return;
      final known = _items.map((item) => item.trashId).toSet();
      final unique = next.where((item) => known.add(item.trashId)).toList();
      if (unique.isEmpty) return;
      setState(() => _items = [..._items, ...unique]);
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _openViewer(int index) async {
    if (_selectionMode) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(
          gallery: widget.gallery,
          initialItems: _items.map((item) => item.media).toList(growable: false),
          initialIndex: index,
          totalCount: _stats.total,
          mediaService: widget.mediaService,
        ),
      ),
    );
  }

  Future<void> _restore(TrashItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var result = await widget.trashService.restore(
        widget.gallery.galleryUuid,
        item.trashId,
      );
      if (!mounted) return;
      if (result.isConflict) {
        final rename = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Destinazione occupata'),
            content: const Text(
              'Esiste già un file nel percorso originale. Vuoi ripristinare questo media con un nome diverso?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Rinomina e ripristina'),
              ),
            ],
          ),
        );
        if (rename != true || !mounted) return;
        result = await widget.trashService.restore(
          widget.gallery.galleryUuid,
          item.trashId,
          autoRename: true,
        );
      }
      if (!mounted || !result.isRestored) return;
      widget.onChanged?.call();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.renamed
                ? 'Media ripristinato con un nuovo nome.'
                : 'Media ripristinato.',
          ),
        ),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showError(error.message ?? 'Ripristino non riuscito.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _deleteSelectionPermanently() async {
    if (_busy) return;
    final selected = _selectedItems;
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare definitivamente?'),
        content: Text(
          selected.length == 1
              ? '${selected.single.media.filename}\n\n'
                  'Questa operazione non può essere annullata.'
              : 'Verranno eliminati definitivamente ${selected.length} media selezionati. '
                  'Questa operazione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final failedIds = <int>{};
    final failureMessages = <String>[];
    var deleted = 0;

    for (final item in selected) {
      try {
        await widget.trashService.permanentlyDelete(
          widget.gallery.galleryUuid,
          item.trashId,
        );
        deleted += 1;
      } on PlatformException catch (error) {
        failedIds.add(item.trashId);
        failureMessages.add(error.message ?? item.media.filename);
      } catch (_) {
        failedIds.add(item.trashId);
        failureMessages.add(item.media.filename);
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectedTrashIds
        ..clear()
        ..addAll(failedIds);
    });

    if (deleted > 0) widget.onChanged?.call();
    await _reload();
    if (!mounted) return;

    if (failureMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted == 1
                ? 'Media eliminato definitivamente.'
                : '$deleted media eliminati definitivamente.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$deleted eliminati, ${failureMessages.length} non riusciti. '
            '${failureMessages.first}',
          ),
        ),
      );
    }
  }

  Future<void> _emptyTrash() async {
    if (_stats.total == 0 || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Svuota cestino'),
        content: Text(
          'Verranno eliminati definitivamente ${_stats.total} media. '
          'Questa operazione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await widget.trashService.emptyTrash(widget.gallery.galleryUuid);
      if (!mounted) return;
      widget.onChanged?.call();
      await _reload();
      if (!mounted) return;
      final suffix = result.errors.isEmpty ? '' : ' (${result.errors.length} errori)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.deleted} media eliminati$suffix.')),
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showError(error.message ?? 'Svuotamento del cestino non riuscito.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _ErrorState(message: _errorMessage(_error), onRetry: _reload);
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: _TrashHeader(
                stats: _stats,
                busy: _busy || _selectionMode,
                onEmpty: _emptyTrash,
              ),
            ),
          ),
          if (_selectionMode)
            SliverToBoxAdapter(
              child: _TrashSelectionBar(
                count: _selectedTrashIds.length,
                busy: _busy,
                canRestore: _selectedTrashIds.length == 1,
                onClose: _clearSelection,
                onRestore: () => _restore(_selectedItems.single),
                onDelete: _deleteSelectionPermanently,
              ),
            ),
          if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyTrashState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = _items[index];
                    final selected = _selectedTrashIds.contains(item.trashId);
                    return MediaThumbnailTile(
                      key: ValueKey(item.media.syncUuid),
                      galleryUuid: widget.gallery.galleryUuid,
                      item: item.media,
                      mediaService: widget.mediaService,
                      selected: selected,
                      selectionMode: _selectionMode,
                      onTap: _selectionMode
                          ? () => _toggleSelection(item)
                          : () => _openViewer(index),
                      onLongPress: () => _startSelection(item),
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
          if (_items.length < _stats.total)
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
      return error.message ?? 'Impossibile leggere il cestino.';
    }
    return 'Impossibile leggere il cestino.';
  }

}

class _TrashSelectionBar extends StatelessWidget {
  const _TrashSelectionBar({
    required this.count,
    required this.busy,
    required this.canRestore,
    required this.onClose,
    required this.onRestore,
    required this.onDelete,
  });

  final int count;
  final bool busy;
  final bool canRestore;
  final VoidCallback onClose;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                  tooltip: 'Ripristina',
                  onPressed: canRestore ? onRestore : null,
                  icon: const Icon(Icons.restore_rounded),
                ),
                IconButton(
                  tooltip: 'Elimina definitivamente',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    color: AppTheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrashHeader extends StatelessWidget {
  const _TrashHeader({
    required this.stats,
    required this.busy,
    required this.onEmpty,
  });

  final TrashStats stats;
  final bool busy;
  final VoidCallback onEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.delete_outline_rounded, color: AppTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.total} media',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatBytes(stats.totalBytes),
                  style: const TextStyle(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          if (stats.total > 0)
            TextButton.icon(
              onPressed: busy ? null : onEmpty,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Svuota'),
            ),
        ],
      ),
    );
  }
}

class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline_rounded, size: 54, color: AppTheme.muted),
            SizedBox(height: 14),
            Text(
              'Il cestino è vuoto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 7),
            Text(
              'I media spostati nel cestino resteranno qui finché non li ripristini o li elimini definitivamente.',
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
