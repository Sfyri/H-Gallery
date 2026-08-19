class GalleryStats {
  const GalleryStats({
    required this.total,
    required this.photos,
    required this.animated,
    required this.videos,
    this.series = 0,
    this.stories = 0,
    this.ai = 0,
  });

  final int total;
  final int photos;
  final int animated;
  final int videos;
  final int series;
  final int stories;
  final int ai;

  int get images => photos + animated;

  static const empty = GalleryStats(
    total: 0,
    photos: 0,
    animated: 0,
    videos: 0,
    series: 0,
    stories: 0,
    ai: 0,
  );

  factory GalleryStats.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return GalleryStats(
      total: readInt('total'),
      photos: readInt('photos'),
      animated: readInt('animated'),
      videos: readInt('videos'),
      series: readInt('series'),
      stories: readInt('stories'),
      ai: readInt('ai'),
    );
  }
}

class ScanResult extends GalleryStats {
  const ScanResult({
    required super.total,
    required super.photos,
    required super.animated,
    required super.videos,
    super.series = 0,
    super.stories = 0,
    super.ai = 0,
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
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return ScanResult(
      total: readInt('total'),
      photos: readInt('photos'),
      animated: readInt('animated'),
      videos: readInt('videos'),
      series: readInt('series'),
      stories: readInt('stories'),
      ai: readInt('ai'),
      added: readInt('added'),
      updated: readInt('updated'),
      moved: readInt('moved'),
      removed: readInt('removed'),
      durationMs: readInt('durationMs'),
    );
  }
}
