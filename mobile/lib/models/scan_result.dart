class GalleryStats {
  const GalleryStats({
    required this.total,
    required this.photos,
    required this.animated,
    required this.videos,
  });

  final int total;
  final int photos;
  final int animated;
  final int videos;

  static const empty = GalleryStats(total: 0, photos: 0, animated: 0, videos: 0);

  factory GalleryStats.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return GalleryStats(
      total: readInt('total'),
      photos: readInt('photos'),
      animated: readInt('animated'),
      videos: readInt('videos'),
    );
  }
}

class ScanResult extends GalleryStats {
  const ScanResult({
    required super.total,
    required super.photos,
    required super.animated,
    required super.videos,
    required this.added,
    required this.updated,
    required this.moved,
    required this.removed,
    required this.durationMs,
  });

  final int added;
  final int updated;
  final int moved;
  final int removed;
  final int durationMs;

  bool get hasChanges => added + updated + moved + removed > 0;

  factory ScanResult.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return ScanResult(
      total: readInt('total'),
      photos: readInt('photos'),
      animated: readInt('animated'),
      videos: readInt('videos'),
      added: readInt('added'),
      updated: readInt('updated'),
      moved: readInt('moved'),
      removed: readInt('removed'),
      durationMs: readInt('durationMs'),
    );
  }
}
