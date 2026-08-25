import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';

class MediaThumbnailTile extends StatefulWidget {
  const MediaThumbnailTile({
    required this.galleryUuid,
    required this.item,
    required this.mediaService,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    super.key,
  });

  final String galleryUuid;
  final MediaItem item;
  final MediaService mediaService;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  State<MediaThumbnailTile> createState() => _MediaThumbnailTileState();
}

class _MediaThumbnailTileState extends State<MediaThumbnailTile> {
  late Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.syncUuid != widget.item.syncUuid ||
        oldWidget.mediaService.runtimeType != widget.mediaService.runtimeType) {
      _thumbnailFuture = _load();
    }
  }

  Future<Uint8List?> _load() {
    return widget.mediaService.loadThumbnail(
      widget.galleryUuid,
      widget.item.syncUuid,
      maxPx: 420,
    );
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.selected ? AppTheme.accent : AppTheme.border;
    final borderWidth = widget.selected ? 2.2 : 1.0;

    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: _thumbnailFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (bytes != null && bytes.isNotEmpty) {
                    return Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          _MediaPlaceholder(item: widget.item),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return _MediaPlaceholder(item: widget.item);
                },
              ),
              if (widget.selectionMode)
                Positioned(
                  right: 7,
                  top: 7,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selected ? AppTheme.accent : const Color(0xB8000000),
                      border: Border.all(
                        color: widget.selected ? AppTheme.accent : Colors.white70,
                      ),
                    ),
                    child: widget.selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 19,
                            color: Color(0xFF0B172A),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.panel2,
      child: Center(
        child: Icon(
          item.isVideo ? Icons.movie_outlined : Icons.image_outlined,
          size: 40,
          color: AppTheme.muted,
        ),
      ),
    );
  }
}
