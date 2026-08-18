import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';
import 'filtered_media_page.dart';

class SeriesBrowserPage extends StatefulWidget {
  const SeriesBrowserPage({
    required this.gallery,
    required this.series,
    this.mediaService = const PlatformMediaService(),
    this.browseService = const PlatformGalleryBrowseService(),
    this.onChanged,
    super.key,
  });

  final GalleryProfile gallery;
  final GalleryCollection series;
  final MediaService mediaService;
  final GalleryBrowseService browseService;
  final Future<void> Function()? onChanged;

  @override
  State<SeriesBrowserPage> createState() => _SeriesBrowserPageState();
}

class _SeriesBrowserPageState extends State<SeriesBrowserPage> {
  final Map<String, Future<Uint8List?>> _coverFutures = {};
  GallerySeriesDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.browseService.getSeriesDetail(
        widget.gallery.galleryUuid,
        widget.series.relativePath,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _coverFor(GalleryCollection collection) {
    if (collection.coverSyncUuid.isEmpty) return Future.value(null);
    return _coverFutures.putIfAbsent(
      collection.relativePath,
      () => widget.mediaService.loadThumbnail(
        widget.gallery.galleryUuid,
        collection.coverSyncUuid,
        maxPx: 520,
      ),
    );
  }

  Future<void> _handleChanged() async {
    await widget.onChanged?.call();
    _coverFutures.clear();
    await _load();
  }

  void _openCollection(String title, String relativePath) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => FilteredMediaPage(
          gallery: widget.gallery,
          title: title,
          query: MediaQuerySpec(relativePrefix: relativePath),
          mediaService: widget.mediaService,
          browseService: widget.browseService,
          onChanged: _handleChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorState(message: _message(_error), onRetry: _load);
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            sliver: SliverToBoxAdapter(
              child: _SeriesHeader(
                name: detail.name,
                count: detail.mediaCount,
                onOpenAll: () => _openCollection(
                  'Tutti · ${detail.name}',
                  detail.relativePath,
                ),
              ),
            ),
          ),
          if (detail.collections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Nessuna cartella personaggio trovata.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 28),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final collection = detail.collections[index];
                    return _CollectionCard(
                      collection: collection,
                      cover: _coverFor(collection),
                      onTap: () => _openCollection(
                        collection.name,
                        collection.relativePath,
                      ),
                    );
                  },
                  childCount: detail.collections.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.86,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _message(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile leggere la serie.';
    }
    return 'Impossibile leggere la serie.';
  }
}

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({
    required this.name,
    required this.count,
    required this.onOpenAll,
  });

  final String name;
  final int count;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_copy_outlined, color: AppTheme.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('$count media', style: const TextStyle(color: AppTheme.muted)),
              ],
            ),
          ),
          TextButton(onPressed: onOpenAll, child: const Text('Tutti')),
        ],
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.cover,
    required this.onTap,
  });

  final GalleryCollection collection;
  final Future<Uint8List?> cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isMultiple = collection.kind == 'multiple';
    final isOther = collection.kind == 'other';
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List?>(
                  future: cover,
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes != null && bytes.isNotEmpty) {
                      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                    }
                    return ColoredBox(
                      color: AppTheme.panel2,
                      child: Center(
                        child: Icon(
                          isMultiple
                              ? Icons.group_outlined
                              : isOther
                                  ? Icons.folder_outlined
                                  : Icons.person_outline_rounded,
                          size: 44,
                          color: AppTheme.muted,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${collection.mediaCount} media',
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
