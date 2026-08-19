import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';

abstract interface class GalleryService {
  Future<List<GalleryProfile>> listGalleries();

  Future<GalleryProfile?> addGallery({String nameHint = ''});

  Future<void> renameGallery(String galleryUuid, String name);

  Future<void> disconnectGallery(String galleryUuid);
}

class PlatformGalleryService implements GalleryService {
  const PlatformGalleryService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/gallery',
  );

  @override
  Future<List<GalleryProfile>> listGalleries() async {
    final values = await _channel.invokeListMethod<Object?>('listGalleries') ?? [];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(GalleryProfile.fromPlatform)
        .toList(growable: false);
  }

  @override
  Future<GalleryProfile?> addGallery({String nameHint = ''}) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'pickGalleryDirectory',
      <String, Object?>{'nameHint': nameHint.trim()},
    );
    if (value == null) return null;
    return GalleryProfile.fromPlatform(value);
  }

  @override
  Future<void> renameGallery(String galleryUuid, String name) {
    return _channel.invokeMethod<void>(
      'renameGallery',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'name': name.trim(),
      },
    );
  }

  @override
  Future<void> disconnectGallery(String galleryUuid) {
    return _channel.invokeMethod<void>(
      'disconnectGallery',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
  }
}
