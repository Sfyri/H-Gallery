import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/viewer_source.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';

class MediaViewerPage extends StatefulWidget {
  const MediaViewerPage({
    required this.gallery,
    required this.initialItems,
    required this.initialIndex,
    required this.totalCount,
    required this.mediaService,
    super.key,
  });

  final GalleryProfile gallery;
  final List<MediaItem> initialItems;
  final int initialIndex;
  final int totalCount;
  final MediaService mediaService;

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  static const int _pageSize = 120;

  late final PageController _pageController;
  late List<MediaItem> _items;
  late int _currentIndex;

  bool _chromeVisible = true;
  bool _pageSwipeEnabled = true;
  bool _loadingMore = false;
  bool _viewerLocked = false;

  @override
  void initState() {
    super.initState();
    _items = List<MediaItem>.of(widget.initialItems);
    _currentIndex = widget.initialIndex >= 0 &&
            widget.initialIndex < widget.initialItems.length
        ? widget.initialIndex
        : 0;
    _pageController = PageController(initialPage: _currentIndex);
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    _loadMoreIfNeeded(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> _loadMoreIfNeeded(int index) async {
    if (_loadingMore || _items.length >= widget.totalCount) return;
    if (index < _items.length - 6) return;
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
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Impossibile caricare altri media nel viewer.',
          ),
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _pageSwipeEnabled = true;
      _viewerLocked = false;
    });
    _loadMoreIfNeeded(index);
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _setZoomed(bool zoomed) {
    if (_pageSwipeEnabled == !zoomed) return;
    setState(() => _pageSwipeEnabled = !zoomed);
  }

  void _setViewerLocked(bool locked) {
    if (_viewerLocked == locked || _items.isEmpty) return;
    if (locked && _items[_currentIndex].isVideo) return;
    setState(() {
      _viewerLocked = locked;
      _chromeVisible = true;
    });
  }

  void _toggleViewerLocked() {
    _setViewerLocked(!_viewerLocked);
  }

  Future<void> _showInfo() {
    if (_items.isEmpty) return Future<void>.value();
    final item = _items[_currentIndex];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppTheme.panel,
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

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Text('Media non disponibile.')),
      );
    }

    final current = _items[_currentIndex];
    final lockAvailable = !current.isVideo;

    return PopScope<Object?>(
      canPop: !_viewerLocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !_viewerLocked) return;
        _setViewerLocked(false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              physics: _pageSwipeEnabled && !_viewerLocked
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _ViewerMediaPage(
                  key: ValueKey(item.syncUuid),
                  galleryUuid: widget.gallery.galleryUuid,
                  item: item,
                  active: index == _currentIndex,
                  chromeVisible: _chromeVisible,
                  locked: _viewerLocked && index == _currentIndex,
                  mediaService: widget.mediaService,
                  onTap: _toggleChrome,
                  onZoomChanged: _setZoomed,
                );
              },
            ),
            _ViewerTopBar(
              visible: _chromeVisible,
              title: current.filename,
              current: _currentIndex + 1,
              total: widget.totalCount,
              lockAvailable: lockAvailable,
              locked: _viewerLocked,
              onBack: () => Navigator.of(context).maybePop(),
              onInfo: _showInfo,
              onLock: _toggleViewerLocked,
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerMediaPage extends StatefulWidget {
  const _ViewerMediaPage({
    required this.galleryUuid,
    required this.item,
    required this.active,
    required this.chromeVisible,
    required this.locked,
    required this.mediaService,
    required this.onTap,
    required this.onZoomChanged,
    super.key,
  });

  final String galleryUuid;
  final MediaItem item;
  final bool active;
  final bool chromeVisible;
  final bool locked;
  final MediaService mediaService;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ViewerMediaPage> createState() => _ViewerMediaPageState();
}

class _ViewerMediaPageState extends State<_ViewerMediaPage> {
  late Future<ViewerSource> _sourceFuture;

  @override
  void initState() {
    super.initState();
    _sourceFuture = _prepareSource();
  }

  @override
  void didUpdateWidget(covariant _ViewerMediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.syncUuid != widget.item.syncUuid) {
      _sourceFuture = _prepareSource();
    }
  }

  Future<ViewerSource> _prepareSource() {
    return widget.mediaService.prepareViewerSource(
      widget.galleryUuid,
      widget.item.syncUuid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ViewerSource>(
      future: _sourceFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ViewerError(
            message: _errorMessage(snapshot.error),
            onRetry: () => setState(() => _sourceFuture = _prepareSource()),
          );
        }
        final source = snapshot.data;
        if (source == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (widget.item.isVideo) {
          if (!source.isVideoContentUri) {
            return const _ViewerError(message: 'Sorgente video non valida.');
          }
          return _VideoMediaView(
            source: source,
            active: widget.active,
            chromeVisible: widget.chromeVisible,
            onTap: widget.onTap,
          );
        }
        if (!source.isImageFile) {
          return const _ViewerError(message: 'Sorgente immagine non valida.');
        }
        return _ImageMediaView(
          source: source,
          locked: widget.locked,
          onTap: widget.onTap,
          onZoomChanged: widget.onZoomChanged,
        );
      },
    );
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile aprire il media.';
    }
    return 'Impossibile aprire il media.';
  }
}

class _ImageMediaView extends StatefulWidget {
  const _ImageMediaView({
    required this.source,
    required this.locked,
    required this.onTap,
    required this.onZoomChanged,
  });

  final ViewerSource source;
  final bool locked;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ImageMediaView> createState() => _ImageMediaViewState();
}

class _ImageMediaViewState extends State<_ImageMediaView> {
  final TransformationController _transformationController =
      TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _updateZoomState() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed == zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    _updateZoomState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: !widget.locked && _zoomed ? _resetZoom : null,
      child: Center(
        child: IgnorePointer(
          ignoring: widget.locked,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1,
            maxScale: 5,
            panEnabled: !widget.locked,
            scaleEnabled: !widget.locked,
            clipBehavior: Clip.none,
            onInteractionUpdate: (_) => _updateZoomState(),
            onInteractionEnd: (_) => _updateZoomState(),
            child: Image.file(
              File(widget.source.value),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => const _ViewerError(
                message: 'Android non riesce a decodificare questa immagine.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoMediaView extends StatefulWidget {
  const _VideoMediaView({
    required this.source,
    required this.active,
    required this.chromeVisible,
    required this.onTap,
  });

  final ViewerSource source;
  final bool active;
  final bool chromeVisible;
  final VoidCallback onTap;

  @override
  State<_VideoMediaView> createState() => _VideoMediaViewState();
}

class _VideoMediaViewState extends State<_VideoMediaView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  Object? _error;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _initialize();
  }

  @override
  void didUpdateWidget(covariant _VideoMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.value != widget.source.value) {
      _disposeController();
      if (widget.active) _initialize();
      return;
    }
    if (!widget.active) {
      _controller?.pause();
    } else if (!oldWidget.active) {
      _initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller?.pause();
    }
  }

  Future<void> _initialize() async {
    if (_controller != null || _initializing) return;
    _initializing = true;
    try {
      final controller = VideoPlayerController.contentUri(
        Uri.parse(widget.source.value),
      );
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setPreventsDisplaySleepDuringVideoPlayback(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ViewerError(
        message: 'Impossibile riprodurre questo video sul dispositivo.',
        onRetry: () {
          setState(() => _error = null);
          _initialize();
        },
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      if (widget.active && !_initializing) _initialize();
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio > 0
                  ? controller.value.aspectRatio
                  : 16 / 9,
              child: VideoPlayer(controller),
            ),
          ),
          _VideoControls(
            controller: controller,
            visible: widget.chromeVisible,
          ),
        ],
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.controller,
    required this.visible,
  });

  final VideoPlayerController controller;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: !visible,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final durationMs = value.duration.inMilliseconds;
            final positionMs = value.position.inMilliseconds.clamp(
              0,
              durationMs > 0 ? durationMs : 0,
            );
            return Stack(
              children: [
                Center(
                  child: Material(
                    color: const Color(0x99000000),
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 42,
                      color: Colors.white,
                      onPressed: () {
                        if (value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      },
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 18,
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: const Color(0xB8000000),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _formatDuration(value.position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: durationMs > 0
                                  ? positionMs.toDouble()
                                  : 0,
                              max: durationMs > 0
                                  ? durationMs.toDouble()
                                  : 1,
                              onChanged: durationMs > 0
                                  ? (newValue) => controller.seekTo(
                                        Duration(
                                          milliseconds: newValue.round(),
                                        ),
                                      )
                                  : null,
                            ),
                          ),
                          Text(
                            _formatDuration(value.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          IconButton(
                            tooltip: value.volume == 0
                                ? 'Attiva audio'
                                : 'Disattiva audio',
                            onPressed: () => controller.setVolume(
                              value.volume == 0 ? 1 : 0,
                            ),
                            icon: Icon(
                              value.volume == 0
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ViewerTopBar extends StatelessWidget {
  const _ViewerTopBar({
    required this.visible,
    required this.title,
    required this.current,
    required this.total,
    required this.lockAvailable,
    required this.locked,
    required this.onBack,
    required this.onInfo,
    required this.onLock,
  });

  final bool visible;
  final String title;
  final int current;
  final int total;
  final bool lockAvailable;
  final bool locked;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 180),
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: IgnorePointer(
            ignoring: !visible,
            child: SafeArea(
              bottom: false,
              child: locked
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Material(
                          color: const Color(0x99000000),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Sblocca visualizzazione',
                            onPressed: onLock,
                            color: Colors.white,
                            icon: const Icon(Icons.lock_rounded),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xD9000000), Color(0x00000000)],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Indietro',
                            onPressed: onBack,
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$current / $total',
                                  style: const TextStyle(
                                    color: Color(0xFFCACACA),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Informazioni',
                            onPressed: onInfo,
                            color: Colors.white,
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                          if (lockAvailable)
                            IconButton(
                              tooltip: 'Blocca visualizzazione',
                              onPressed: onLock,
                              color: Colors.white,
                              icon: const Icon(Icons.lock_open_rounded),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

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
              color: AppTheme.error,
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Riprova'),
              ),
            ],
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 100 ? 0 : 2)} GB';
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '$minutes:${twoDigits(seconds)}';
}
