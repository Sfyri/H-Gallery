import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/scan_result.dart';

abstract interface class MediaService {
  Future<ScanResult> scanGallery(String galleryUuid);

  Future<GalleryStats> getStats(String galleryUuid);

  Future<List<MediaItem>> listMedia(
    String galleryUuid, {
    int limit = 120,
    int offset = 0,
  });

  Future<Uint8List?> loadThumbnail(
    String galleryUuid,
    String syncUuid, {
    int maxPx = 360,
  });
}

class PlatformMediaService implements MediaService {
  const PlatformMediaService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<ScanResult> scanGallery(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'scanGallery',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_SCAN_RESULT',
        message: 'La scansione non ha restituito un risultato.',
      );
    }
    return ScanResult.fromPlatform(value);
  }

  @override
  Future<GalleryStats> getStats(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getGalleryStats',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    return value == null ? GalleryStats.empty : GalleryStats.fromPlatform(value);
  }

  @override
  Future<List<MediaItem>> listMedia(
    String galleryUuid, {
    int limit = 120,
    int offset = 0,
  }) async {
    final values = await _channel.invokeListMethod<Object?>(
          'listMedia',
          <String, Object?>{
            'galleryUuid': galleryUuid,
            'limit': limit,
            'offset': offset,
          },
        ) ??
        const <Object?>[];

    return values
        .whereType<Map<Object?, Object?>>()
        .map(MediaItem.fromPlatform)
        .toList(growable: false);
  }

  @override
  Future<Uint8List?> loadThumbnail(
    String galleryUuid,
    String syncUuid, {
    int maxPx = 360,
  }) {
    return _channel.invokeMethod<Uint8List>(
      'loadThumbnail',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
        'maxPx': maxPx,
      },
    );
  }
}
