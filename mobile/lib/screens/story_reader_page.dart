import 'dart:io';

import 'package:flutter/material.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/story_models.dart';
import '../models/viewer_source.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';

enum _StoryReaderMode { single, vertical }

class StoryReaderPage extends StatefulWidget {
  const StoryReaderPage({
    required this.gallery,
    required this.story,
    required this.mediaService,
    required this.browseService,
    super.key,
  });

  final GalleryProfile gallery;
  final GalleryStorySummary story;
  final MediaService mediaService;
  final GalleryBrowseService browseService;

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  late final PageController _pageController;
  List<MediaItem> _pages = const [];
  _StoryReaderMode _mode = _StoryReaderMode.single;
  int _currentIndex = 0;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        widget.story.relativePath,
      );
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _currentIndex = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setMode(_StoryReaderMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
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
              widget.story.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.story.isRtl ? 'Lettura RTL' : 'Lettura LTR',
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_StoryReaderMode>(
            tooltip: 'Modalità di lettura',
            initialValue: _mode,
            icon: Icon(
              _mode == _StoryReaderMode.single
                  ? Icons.menu_book_rounded
                  : Icons.view_day_rounded,
            ),
            onSelected: _setMode,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _StoryReaderMode.single,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded),
                  title: Text('Pagina singola'),
                ),
              ),
              PopupMenuItem(
                value: _StoryReaderMode.vertical,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.view_day_rounded),
                  title: Text('Scorrimento verticale'),
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
              const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 48),
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
        child: Text('La storia non contiene pagine disponibili.', style: TextStyle(color: Colors.white70)),
      );
    }
    if (_mode == _StoryReaderMode.vertical) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _pages.length,
        itemBuilder: (context, index) => _StoryPageImage(
          key: ValueKey('vertical-${_pages[index].syncUuid}'),
          galleryUuid: widget.gallery.galleryUuid,
          item: _pages[index],
          mediaService: widget.mediaService,
          fitWidth: true,
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          reverse: widget.story.isRtl,
          itemCount: _pages.length,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (context, index) => _StoryPageImage(
            key: ValueKey('single-${_pages[index].syncUuid}'),
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
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  '${_currentIndex + 1} / ${_pages.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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

class _StoryPageImageState extends State<_StoryPageImage> {
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
  Widget build(BuildContext context) {
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
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 44),
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
            child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 44),
          ),
        );
        if (widget.fitWidth) return image;
        return Center(child: image);
      },
    );
  }
}
