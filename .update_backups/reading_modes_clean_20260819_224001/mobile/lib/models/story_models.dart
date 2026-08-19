import 'package:flutter/foundation.dart';

@immutable
class GalleryStorySummary {
  const GalleryStorySummary({
    required this.title,
    required this.relativePath,
    required this.readingDirection,
    required this.pageCount,
    required this.coverSyncUuid,
    required this.aiGenerated,
  });

  final String title;
  final String relativePath;
  final String readingDirection;
  final int pageCount;
  final String coverSyncUuid;
  final bool aiGenerated;

  bool get isRtl => readingDirection.toLowerCase() == 'rtl';

  factory GalleryStorySummary.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    bool readBool(String key) {
      final raw = value[key];
      if (raw is bool) return raw;
      if (raw is num) return raw != 0;
      return raw?.toString().toLowerCase() == 'true';
    }

    final direction = value['readingDirection']?.toString().toLowerCase();
    return GalleryStorySummary(
      title: value['title']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      readingDirection: direction == 'ltr' ? 'ltr' : 'rtl',
      pageCount: readInt('pageCount'),
      coverSyncUuid: value['coverSyncUuid']?.toString() ?? '',
      aiGenerated: readBool('aiGenerated'),
    );
  }
}
