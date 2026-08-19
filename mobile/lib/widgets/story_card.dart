import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/story_models.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';

class StoryCard extends StatefulWidget {
  const StoryCard({
    required this.galleryUuid,
    required this.story,
    required this.mediaService,
    required this.onTap,
    super.key,
  });

  final String galleryUuid;
  final GalleryStorySummary story;
  final MediaService mediaService;
  final VoidCallback onTap;

  @override
  State<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<StoryCard> {
  Future<Uint8List?>? _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _loadCover();
  }

  @override
  void didUpdateWidget(covariant StoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story.coverSyncUuid != widget.story.coverSyncUuid ||
        oldWidget.galleryUuid != widget.galleryUuid) {
      _coverFuture = _loadCover();
    }
  }

  Future<Uint8List?> _loadCover() {
    if (widget.story.coverSyncUuid.isEmpty) return Future.value(null);
    return widget.mediaService.loadThumbnail(
      widget.galleryUuid,
      widget.story.coverSyncUuid,
      maxPx: 520,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  future: _coverFuture,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes != null && bytes.isNotEmpty) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(7),
                                child: Icon(
                                  Icons.auto_stories_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return const ColoredBox(
                      color: AppTheme.panel2,
                      child: Center(
                        child: Icon(
                          Icons.auto_stories_outlined,
                          size: 48,
                          color: AppTheme.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.story.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.story.pageCount} pagine · ${widget.story.isRtl ? 'RTL' : 'LTR'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
