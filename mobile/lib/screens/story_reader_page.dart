import 'dart:io';

import 'package:flutter/material.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/story_models.dart';
import '../models/viewer_source.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../services/story_management_service.dart';
import '../theme/app_theme.dart';
import 'story_editor_page.dart';

enum _StoryReaderMode { normal, manga, vertical }

class StoryReaderPage extends StatefulWidget {
  const StoryReaderPage({
    required this.gallery,
    required this.story,
    required this.mediaService,
    required this.browseService,
    this.storyService = const PlatformStoryManagementService(),
    super.key,
  });

  final GalleryProfile gallery;
  final GalleryStorySummary story;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final StoryManagementService storyService;

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  late final PageController _pageController;
  late final ScrollController _verticalController;
  late GalleryStorySummary _story;
  List<MediaItem> _pages = const [];
  _StoryReaderMode _mode = _StoryReaderMode.normal;
  int _currentIndex = 0;
  bool _loading = true;
  bool _editing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _story = widget.story;
    _pageController = PageController();
    _verticalController = ScrollController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
        _currentIndex = 0;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mode == _StoryReaderMode.vertical) {
          if (_verticalController.hasClients) _verticalController.jumpTo(0);
        } else if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editStory() async {
    if (_editing || _loading) return;
    setState(() => _editing = true);
    try {
      final updated = await Navigator.of(context).push<GalleryStorySummary>(
        MaterialPageRoute<GalleryStorySummary>(
          builder: (context) => StoryEditorPage(
            gallery: widget.gallery,
            story: _story,
            mediaService: widget.mediaService,
            browseService: widget.browseService,
            storyService: widget.storyService,
          ),
        ),
      );
      if (!mounted || updated == null) return;
      setState(() => _story = updated);
      await _load();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  void _setMode(_StoryReaderMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _currentIndex = 0;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (mode == _StoryReaderMode.vertical) {
        if (_verticalController.hasClients) {
          _verticalController.jumpTo(0);
        }
      } else if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  IconData get _modeIcon {
    switch (_mode) {
      case _StoryReaderMode.normal:
        return Icons.menu_book_rounded;
      case _StoryReaderMode.manga:
        return Icons.swap_horiz_rounded;
      case _StoryReaderMode.vertical:
        return Icons.view_day_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _story.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              '${_story.pageCount} pagine',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Modifica storia',
            onPressed: _loading || _editing ? null : _editStory,
            icon: _editing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<_StoryReaderMode>(
            tooltip: 'Modalità di lettura',
            initialValue: _mode,
            icon: Icon(_modeIcon),
            onSelected: _setMode,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _StoryReaderMode.normal,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded),
                  title: Text('Normale'),
                  subtitle: Text('Sinistra → destra'),
                ),
              ),
              PopupMenuItem(
                value: _StoryReaderMode.manga,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_horiz_rounded),
                  title: Text('Manga'),
                  subtitle: Text('Destra → sinistra'),
                ),
              ),
              PopupMenuItem(
                value: _StoryReaderMode.vertical,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.view_day_rounded),
                  title: Text('Verticale'),
                  subtitle: Text('Scorrimento continuo dall’alto'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'Impossibile aprire la storia.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Text(
          'La storia non contiene pagine disponibili.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (_mode == _StoryReaderMode.vertical) {
      return _buildVerticalReader();
    }
    return _buildPagedReader();
  }

  Widget _buildVerticalReader() {
    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
    return Scrollbar(
      controller: _verticalController,
      child: CustomScrollView(
        controller: _verticalController,
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _StoryPageImage(
                key: ValueKey('vertical-${_pages[index].syncUuid}'),
                galleryUuid: widget.gallery.galleryUuid,
                item: _pages[index],
                mediaService: widget.mediaService,
                fitWidth: true,
              ),
              childCount: _pages.length,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: bottomSafeArea + 56),
          ),
        ],
      ),
    );
  }

  Widget _buildPagedReader() {
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          // L'ordine logico resta sempre pagina 1, 2, 3...;
          // in modalità Manga cambia soltanto il verso dello swipe.
          reverse: _mode == _StoryReaderMode.manga,
          itemCount: _pages.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (context, index) => _StoryPageImage(
            key: ValueKey('${_mode.name}-${_pages[index].syncUuid}'),
            galleryUuid: widget.gallery.galleryUuid,
            item: _pages[index],
            mediaService: widget.mediaService,
            fitWidth: false,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: SafeArea(
            top: false,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${_pages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StoryPageImage extends StatefulWidget {
  const _StoryPageImage({
    required this.galleryUuid,
    required this.item,
    required this.mediaService,
    required this.fitWidth,
    super.key,
  });

  final String galleryUuid;
  final MediaItem item;
  final MediaService mediaService;
  final bool fitWidth;

  @override
  State<_StoryPageImage> createState() => _StoryPageImageState();
}

class _StoryPageImageState extends State<_StoryPageImage>
    with AutomaticKeepAliveClientMixin<_StoryPageImage> {
  late Future<ViewerSource> _sourceFuture;

  @override
  void initState() {
    super.initState();
    _sourceFuture = widget.mediaService.prepareViewerSource(
      widget.galleryUuid,
      widget.item.syncUuid,
    );
  }

  @override
  bool get wantKeepAlive => widget.fitWidth;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<ViewerSource>(
      future: _sourceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            height: widget.fitWidth ? 420 : null,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final source = snapshot.data;
        if (snapshot.hasError || source == null || !source.isImageFile) {
          return SizedBox(
            height: widget.fitWidth ? 260 : null,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 44,
              ),
            ),
          );
        }
        final image = Image.file(
          File(source.value),
          width: widget.fitWidth ? double.infinity : null,
          fit: widget.fitWidth ? BoxFit.fitWidth : BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 44,
            ),
          ),
        );
        if (widget.fitWidth) return image;
        return Center(child: image);
      },
    );
  }
}
