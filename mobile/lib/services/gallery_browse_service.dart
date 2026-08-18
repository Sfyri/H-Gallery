import 'package:flutter/services.dart';

import '../models/gallery_browse_models.dart';
import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../models/viewer_source.dart';
import 'media_bridge.dart';

abstract interface class GalleryBrowseService {
  Future<GalleryBrowseCatalog> getBrowseCatalog(String galleryUuid);

  Future<GallerySeriesDetail> getSeriesDetail(
    String galleryUuid,
    String relativePath,
  );

  Future<GalleryFilterCatalog> getFilterCatalog(String galleryUuid);

  Future<({int total, List<MediaItem> items})> queryMedia(
    String galleryUuid,
    MediaQuerySpec query, {
    int limit = 120,
    int offset = 0,
  });

  Future<MediaMetadataInfo> getMediaMetadata(
    String galleryUuid,
    String syncUuid,
  );
}

class PlatformGalleryBrowseService implements GalleryBrowseService {
  const PlatformGalleryBrowseService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<GalleryBrowseCatalog> getBrowseCatalog(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getBrowseCatalog',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_BROWSE_CATALOG',
        message: 'La struttura della galleria non è disponibile.',
      );
    }
    return GalleryBrowseCatalog.fromPlatform(value);
  }

  @override
  Future<GallerySeriesDetail> getSeriesDetail(
    String galleryUuid,
    String relativePath,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getSeriesDetail',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'relativePath': relativePath,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_SERIES_DETAIL',
        message: 'La serie non è disponibile.',
      );
    }
    return GallerySeriesDetail.fromPlatform(value);
  }

  @override
  Future<GalleryFilterCatalog> getFilterCatalog(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getFilterCatalog',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (value == null) {
      return const GalleryFilterCatalog(
        locations: <GalleryFilterLocation>[],
        tags: <String>[],
        artists: <String>[],
      );
    }
    return GalleryFilterCatalog.fromPlatform(value);
  }

  @override
  Future<({int total, List<MediaItem> items})> queryMedia(
    String galleryUuid,
    MediaQuerySpec query, {
    int limit = 120,
    int offset = 0,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'queryMedia',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'text': query.text.trim(),
        'kind': query.kind,
        'relativePrefix': query.relativePrefix,
        'tag': query.tag,
        'artist': query.artist,
        'aiOnly': query.aiOnly,
        'limit': limit,
        'offset': offset,
      },
    );
    if (value == null) return (total: 0, items: const <MediaItem>[]);
    final parsed = MediaQueryResult.fromPlatform(value);
    return (
      total: parsed.total,
      items: parsed.items.map(MediaItem.fromPlatform).toList(growable: false),
    );
  }

  @override
  Future<MediaMetadataInfo> getMediaMetadata(
    String galleryUuid,
    String syncUuid,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getMediaMetadata',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
      },
    );
    if (value == null) {
      return const MediaMetadataInfo(
        aiGenerated: false,
        characters: <MediaCharacterInfo>[],
        tags: <String>[],
        artists: <String>[],
      );
    }
    return MediaMetadataInfo.fromPlatform(value);
  }
}

class FilteredMediaService implements MediaService {
  const FilteredMediaService({
    required this.base,
    required this.browse,
    required this.query,
  });

  final MediaService base;
  final GalleryBrowseService browse;
  final MediaQuerySpec query;

  @override
  Future<ScanResult> scanGallery(String galleryUuid) => base.scanGallery(galleryUuid);

  @override
  Future<GalleryStats> getStats(String galleryUuid) => base.getStats(galleryUuid);

  @override
  Future<List<MediaItem>> listMedia(
    String galleryUuid, {
    int limit = 120,
    int offset = 0,
  }) async {
    final result = await browse.queryMedia(
      galleryUuid,
      query,
      limit: limit,
      offset: offset,
    );
    return result.items;
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String galleryUuid,
    String syncUuid, {
    int maxPx = 360,
  }) {
    return base.loadThumbnail(galleryUuid, syncUuid, maxPx: maxPx);
  }

  @override
  Future<ViewerSource> prepareViewerSource(
    String galleryUuid,
    String syncUuid,
  ) {
    return base.prepareViewerSource(galleryUuid, syncUuid);
  }
}
