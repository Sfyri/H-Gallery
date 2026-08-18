import 'package:flutter/foundation.dart';

@immutable
class GalleryCollection {
  const GalleryCollection({
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.mediaCount,
    required this.coverSyncUuid,
  });

  final String name;
  final String relativePath;
  final String kind;
  final int mediaCount;
  final String coverSyncUuid;

  bool get isSeries => kind == 'series';
  bool get isSpecial => kind == 'special';
  bool get isCharacter => kind == 'character';

  factory GalleryCollection.fromPlatform(Map<Object?, Object?> value) {
    return GalleryCollection(
      name: _readString(value, 'name'),
      relativePath: _readString(value, 'relativePath'),
      kind: _readString(value, 'kind'),
      mediaCount: _readInt(value, 'mediaCount'),
      coverSyncUuid: _readString(value, 'coverSyncUuid'),
    );
  }
}

@immutable
class GalleryBrowseCatalog {
  const GalleryBrowseCatalog({
    required this.series,
    required this.special,
    required this.total,
  });

  final List<GalleryCollection> series;
  final List<GalleryCollection> special;
  final int total;

  factory GalleryBrowseCatalog.fromPlatform(Map<Object?, Object?> value) {
    return GalleryBrowseCatalog(
      series: _readMapList(value['series'])
          .map(GalleryCollection.fromPlatform)
          .toList(growable: false),
      special: _readMapList(value['special'])
          .map(GalleryCollection.fromPlatform)
          .toList(growable: false),
      total: _readInt(value, 'total'),
    );
  }
}

@immutable
class GallerySeriesDetail {
  const GallerySeriesDetail({
    required this.name,
    required this.relativePath,
    required this.mediaCount,
    required this.coverSyncUuid,
    required this.collections,
  });

  final String name;
  final String relativePath;
  final int mediaCount;
  final String coverSyncUuid;
  final List<GalleryCollection> collections;

  factory GallerySeriesDetail.fromPlatform(Map<Object?, Object?> value) {
    return GallerySeriesDetail(
      name: _readString(value, 'name'),
      relativePath: _readString(value, 'relativePath'),
      mediaCount: _readInt(value, 'mediaCount'),
      coverSyncUuid: _readString(value, 'coverSyncUuid'),
      collections: _readMapList(value['collections'])
          .map(GalleryCollection.fromPlatform)
          .toList(growable: false),
    );
  }
}

@immutable
class GalleryFilterLocation {
  const GalleryFilterLocation({
    required this.label,
    required this.relativePath,
    required this.kind,
  });

  final String label;
  final String relativePath;
  final String kind;

  factory GalleryFilterLocation.fromPlatform(Map<Object?, Object?> value) {
    return GalleryFilterLocation(
      label: _readString(value, 'label'),
      relativePath: _readString(value, 'relativePath'),
      kind: _readString(value, 'kind'),
    );
  }
}

@immutable
class GalleryFilterCatalog {
  const GalleryFilterCatalog({
    required this.locations,
    required this.tags,
    required this.artists,
  });

  final List<GalleryFilterLocation> locations;
  final List<String> tags;
  final List<String> artists;

  factory GalleryFilterCatalog.fromPlatform(Map<Object?, Object?> value) {
    return GalleryFilterCatalog(
      locations: _readMapList(value['locations'])
          .map(GalleryFilterLocation.fromPlatform)
          .toList(growable: false),
      tags: _readStringList(value['tags']),
      artists: _readStringList(value['artists']),
    );
  }
}

@immutable
class MediaQuerySpec {
  const MediaQuerySpec({
    this.text = '',
    this.kind = '',
    this.relativePrefix = '',
    this.tag = '',
    this.artist = '',
    this.aiOnly = false,
  });

  final String text;
  final String kind;
  final String relativePrefix;
  final String tag;
  final String artist;
  final bool aiOnly;

  bool get hasFilters =>
      text.trim().isNotEmpty ||
      kind.isNotEmpty ||
      relativePrefix.isNotEmpty ||
      tag.isNotEmpty ||
      artist.isNotEmpty ||
      aiOnly;

  MediaQuerySpec copyWith({
    String? text,
    String? kind,
    String? relativePrefix,
    String? tag,
    String? artist,
    bool? aiOnly,
  }) {
    return MediaQuerySpec(
      text: text ?? this.text,
      kind: kind ?? this.kind,
      relativePrefix: relativePrefix ?? this.relativePrefix,
      tag: tag ?? this.tag,
      artist: artist ?? this.artist,
      aiOnly: aiOnly ?? this.aiOnly,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MediaQuerySpec &&
        other.text == text &&
        other.kind == kind &&
        other.relativePrefix == relativePrefix &&
        other.tag == tag &&
        other.artist == artist &&
        other.aiOnly == aiOnly;
  }

  @override
  int get hashCode => Object.hash(
        text,
        kind,
        relativePrefix,
        tag,
        artist,
        aiOnly,
      );
}

@immutable
class MediaQueryResult {
  const MediaQueryResult({required this.total, required this.items});

  final int total;
  final List<Map<Object?, Object?>> items;

  factory MediaQueryResult.fromPlatform(Map<Object?, Object?> value) {
    return MediaQueryResult(
      total: _readInt(value, 'total'),
      items: _readMapList(value['items']),
    );
  }
}

@immutable
class MediaCharacterInfo {
  const MediaCharacterInfo({
    required this.name,
    required this.franchiseName,
  });

  final String name;
  final String franchiseName;

  String get label => franchiseName.isEmpty ? name : '$franchiseName · $name';

  factory MediaCharacterInfo.fromPlatform(Map<Object?, Object?> value) {
    return MediaCharacterInfo(
      name: _readString(value, 'name'),
      franchiseName: _readString(value, 'franchiseName'),
    );
  }
}

@immutable
class MediaMetadataInfo {
  const MediaMetadataInfo({
    required this.aiGenerated,
    required this.characters,
    required this.tags,
    required this.artists,
  });

  final bool aiGenerated;
  final List<MediaCharacterInfo> characters;
  final List<String> tags;
  final List<String> artists;

  factory MediaMetadataInfo.fromPlatform(Map<Object?, Object?> value) {
    return MediaMetadataInfo(
      aiGenerated: value['aiGenerated'] == true,
      characters: _readMapList(value['characters'])
          .map(MediaCharacterInfo.fromPlatform)
          .toList(growable: false),
      tags: _readStringList(value['tags']),
      artists: _readStringList(value['artists']),
    );
  }
}

String _readString(Map<Object?, Object?> value, String key) {
  return value[key]?.toString() ?? '';
}

int _readInt(Map<Object?, Object?> value, String key) {
  final raw = value[key];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

List<Map<Object?, Object?>> _readMapList(Object? value) {
  if (value is! List) return const <Map<Object?, Object?>>[];
  return value.whereType<Map<Object?, Object?>>().toList(growable: false);
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
