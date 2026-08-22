import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/story_models.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/story_management_service.dart';
import '../theme/app_theme.dart';
import 'media_metadata_editor_page.dart';

class StoryEditorPage extends StatefulWidget {
  const StoryEditorPage({
    super.key,
    required this.gallery,
    required this.story,
    required this.mediaService,
    required this.browseService,
    required this.storyService,
  });

  final GalleryProfile gallery;
  final GalleryStorySummary story;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final StoryManagementService storyService;

  @override
  State<StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends State<StoryEditorPage> {
  static const int _maxPages = 500;

  late final TextEditingController _titleController;
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};

  late GalleryStorySummary _story;
  List<MediaItem> _pages = const [];
  String _coverSyncUuid = '';
  bool _loading = true;
  bool _saving = false;
  bool _structureDirty = false;
  bool _allowPop = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _coverSyncUuid = widget.story.coverSyncUuid;
    _titleController = TextEditingController(text: widget.story.title);
    _loadPages();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pages = await widget.browseService.getStoryPages(
        widget.gallery.galleryUuid,
        _story.relativePath,
      );
      if (!mounted) return;
      setState(() {
        _pages = pages;
        if (_coverSyncUuid.isEmpty ||
            !_pages.any((page) => page.syncUuid == _coverSyncUuid)) {
          _coverSyncUuid = _pages.isEmpty ? '' : _pages.first.syncUuid;
        }
        _thumbnailFutures.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPages() async {
    if (_saving || _pages.length >= _maxPages) return;
    final selected = await Navigator.of(context).push<List<MediaItem>>(
      MaterialPageRoute<List<MediaItem>>(
        builder: (context) => _StoryPagePickerPage(
          galleryUuid: widget.gallery.galleryUuid,
          mediaService: widget.mediaService,
          browseService: widget.browseService,
          excludedSyncUuids: _pages.map((page) => page.syncUuid).toSet(),
          maxSelection: _maxPages - _pages.length,
        ),
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    final known = _pages.map((page) => page.syncUuid).toSet();
    final additions = selected.where((page) => known.add(page.syncUuid)).toList();
    if (additions.isEmpty) return;
    setState(() {
      _pages = [..._pages, ...additions];
      _structureDirty = true;
      if (_coverSyncUuid.isEmpty) _coverSyncUuid = _pages.first.syncUuid;
    });
  }

  void _removePage(MediaItem page) {
    if (_saving) return;
    if (_pages.length <= 2) {
      _showMessage('Una storia deve mantenere almeno due pagine.');
      return;
    }
    setState(() {
      _pages = _pages.where((item) => item.syncUuid != page.syncUuid).toList();
      if (_coverSyncUuid == page.syncUuid) {
        _coverSyncUuid = _pages.first.syncUuid;
      }
      _structureDirty = true;
    });
  }

  void _setCover(String syncUuid) {
    if (_saving || _coverSyncUuid == syncUuid) return;
    setState(() {
      _coverSyncUuid = syncUuid;
      _structureDirty = true;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_saving) return;
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
      _structureDirty = true;
    });
  }

  Future<void> _editMetadata(MediaItem page) async {
    if (_saving) return;
    if (_structureDirty) {
      _showMessage('Salva prima le modifiche a titolo, ordine, copertina o pagine.');
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => MediaMetadataEditorPage(
          galleryUuid: widget.gallery.galleryUuid,
          item: page,
        ),
      ),
    );
    if (!mounted || changed != true) return;

    // I metadata della storia sono l'unione di quelli delle pagine. Dopo la
    // modifica riallineiamo subito anche cartella, AI e copertina della storia.
    await _save(closeAfter: false, successMessage: 'Metadati aggiornati.');
  }

  Future<GalleryStorySummary?> _save({
    required bool closeAfter,
    String? successMessage,
  }) async {
    if (_saving) return null;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showMessage('Inserisci un titolo per la storia.');
      return null;
    }
    if (_pages.length < 2) {
      _showMessage('Una storia deve contenere almeno due pagine.');
      return null;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.storyService.updateStory(
        widget.gallery.galleryUuid,
        currentRelativePath: _story.relativePath,
        title: title,
        orderedSyncUuids: _pages.map((page) => page.syncUuid).toList(growable: false),
        coverSyncUuid: _coverSyncUuid,
      );
      final updated = GalleryStorySummary.fromPlatform(result);
      if (!mounted) return updated;
      _story = updated;
      _titleController.text = updated.title;
      _coverSyncUuid = updated.coverSyncUuid;
      _structureDirty = false;
      _thumbnailFutures.clear();
      if (closeAfter) {
        Navigator.of(context).pop(updated);
        return updated;
      }
      await _loadPages();
      if (!mounted) return updated;
      if (successMessage != null) _showMessage(successMessage);
      return updated;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _error = error);
      _showMessage(error.toString());
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_structureDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annullare le modifiche?'),
        content: const Text(
          'Le modifiche a titolo, ordine, copertina e pagine non sono ancora state salvate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continua a modificare'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Annulla modifiche'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Uint8List?> _thumbnailFor(MediaItem page) {
    return _thumbnailFutures.putIfAbsent(
      page.syncUuid,
      () => widget.mediaService.loadThumbnail(
        widget.gallery.galleryUuid,
        page.syncUuid,
        maxPx: 220,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_structureDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && mounted) {
          setState(() => _allowPop = true);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Modifica storia'),
          actions: [
            TextButton(
              onPressed: _loading || _saving ? null : () => _save(closeAfter: true),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salva'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _pages.isEmpty
                ? _EditorError(error: _error!, onRetry: _loadPages)
                : _buildEditor(),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                enabled: !_saving,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _structureDirty = true),
                decoration: const InputDecoration(
                  labelText: 'Titolo',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.panel,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'I metadata della storia derivano dalle sue pagine. Usa la matita su una pagina per modificarli; le pagine rimosse tornano nella galleria e non vengono eliminate.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_pages.length} pagine',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving || _pages.length >= _maxPages ? null : _addPages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Aggiungi'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
            itemCount: _pages.length,
            onReorder: _reorder,
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final page = _pages[index];
              final isCover = page.syncUuid == _coverSyncUuid;
              return Card(
                key: ValueKey(page.syncUuid),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                  leading: SizedBox(
                    width: 58,
                    height: 58,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: FutureBuilder<Uint8List?>(
                        future: _thumbnailFor(page),
                        builder: (context, snapshot) {
                          final bytes = snapshot.data;
                          if (bytes == null) {
                            return Container(
                              color: AppTheme.panel,
                              child: const Icon(Icons.image_outlined, color: AppTheme.muted),
                            );
                          }
                          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                        },
                      ),
                    ),
                  ),
                  title: Text(
                    '${index + 1}. ${page.filename}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    isCover ? 'Copertina' : page.relativePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCover ? Theme.of(context).colorScheme.primary : AppTheme.muted,
                    ),
                  ),
                  trailing: SizedBox(
                    width: 144,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: isCover ? 'Copertina attuale' : 'Imposta copertina',
                          onPressed: _saving ? null : () => _setCover(page.syncUuid),
                          icon: Icon(isCover ? Icons.star_rounded : Icons.star_border_rounded),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Azioni pagina',
                          enabled: !_saving,
                          onSelected: (value) {
                            if (value == 'metadata') {
                              _editMetadata(page);
                            } else if (value == 'remove') {
                              _removePage(page);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'metadata',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Modifica metadata'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.remove_circle_outline_rounded),
                                title: Text('Rimuovi dalla storia'),
                              ),
                            ),
                          ],
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StoryPagePickerPage extends StatefulWidget {
  const _StoryPagePickerPage({
    required this.galleryUuid,
    required this.mediaService,
    required this.browseService,
    required this.excludedSyncUuids,
    required this.maxSelection,
  });

  final String galleryUuid;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final Set<String> excludedSyncUuids;
  final int maxSelection;

  @override
  State<_StoryPagePickerPage> createState() => _StoryPagePickerPageState();
}

class _StoryPagePickerPageState extends State<_StoryPagePickerPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selected = <String>{};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  Timer? _debounce;
  List<MediaItem> _items = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.browseService.queryMedia(
        widget.galleryUuid,
        MediaQuerySpec(text: _searchController.text),
        limit: 500,
      );
      final items = result.items
          .where((item) => item.isImage && !widget.excludedSyncUuids.contains(item.syncUuid))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _items = items;
        final available = items.map((item) => item.syncUuid).toSet();
        _selected.retainWhere(available.contains);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(MediaItem item) {
    setState(() {
      if (!_selected.remove(item.syncUuid)) {
        if (_selected.length >= widget.maxSelection) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Puoi aggiungere al massimo ${widget.maxSelection} pagine.')),
          );
          return;
        }
        _selected.add(item.syncUuid);
      }
    });
  }

  Future<Uint8List?> _thumbnailFor(MediaItem item) {
    return _thumbnailFutures.putIfAbsent(
      item.syncUuid,
      () => widget.mediaService.loadThumbnail(widget.galleryUuid, item.syncUuid, maxPx: 180),
    );
  }

  void _confirm() {
    final selectedItems = _items.where((item) => _selected.contains(item.syncUuid)).toList();
    Navigator.of(context).pop(selectedItems);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty ? 'Aggiungi pagine' : '${_selected.length} selezionate'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : _confirm,
            child: const Text('Aggiungi'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Cerca immagini libere…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _load();
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _EditorError(error: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                'Nessuna immagine libera disponibile.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppTheme.muted),
                              ),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final selected = _selected.contains(item.syncUuid);
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _toggle(item),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: selected
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).dividerColor,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            FutureBuilder<Uint8List?>(
                                              future: _thumbnailFor(item),
                                              builder: (context, snapshot) {
                                                final bytes = snapshot.data;
                                                if (bytes == null) {
                                                  return Container(
                                                    color: AppTheme.panel,
                                                    child: const Icon(Icons.image_outlined),
                                                  );
                                                }
                                                return Image.memory(bytes, fit: BoxFit.cover);
                                              },
                                            ),
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: CircleAvatar(
                                                radius: 15,
                                                child: Icon(
                                                  selected ? Icons.check_rounded : Icons.add_rounded,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          item.filename,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _EditorError extends StatelessWidget {
  const _EditorError({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 14),
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
