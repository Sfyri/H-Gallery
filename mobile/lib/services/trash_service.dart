import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../models/trash_models.dart';
import '../models/viewer_source.dart';
import 'media_bridge.dart';

abstract interface class TrashService {
  Future<void> moveMediaToTrash(String galleryUuid, String syncUuid);

  Future<TrashStats> getStats(String galleryUuid);

  Future<List<TrashItem>> listItems(
    String galleryUuid, {
    int limit = 120,
    int offset = 0,
  });

  Future<TrashRestoreResult> restore(
    String galleryUuid,
    int trashId, {
    bool autoRename = false,
  });

  Future<void> permanentlyDelete(String galleryUuid, int trashId);

  Future<EmptyTrashResult> emptyTrash(String galleryUuid);
}

class PlatformTrashService implements TrashService {
  const PlatformTrashService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<void> moveMediaToTrash(String galleryUuid, String syncUuid) {
    return _channel.invokeMethod<void>(
      'trashMedia',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
      },
    );
  }

  @override
  Future<TrashStats> getStats(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getTrashStats',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    return value == null
        ? const TrashStats(total: 0, totalBytes: 0)
        : TrashStats.fromPlatform(value);
  }

  @override
  Future<List<TrashItem>> listItems(
    String galleryUuid, {
    int limit = 120,
    int offset = 0,
  }) async {
    final values = await _channel.invokeListMethod<Object?>(
          'listTrashItems',
          <String, Object?>{
            'galleryUuid': galleryUuid,
            'limit': limit,
            'offset': offset,
          },
        ) ??
        const <Object?>[];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(TrashItem.fromPlatform)
        .toList(growable: false);
  }

  @override
  Future<TrashRestoreResult> restore(
    String galleryUuid,
    int trashId, {
    bool autoRename = false,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'restoreTrashItem',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'trashId': trashId,
        'autoRename': autoRename,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_TRASH_RESTORE_RESULT',
        message: 'Il ripristino non ha restituito un risultato.',
      );
    }
    return TrashRestoreResult.fromPlatform(value);
  }

  @override
  Future<void> permanentlyDelete(String galleryUuid, int trashId) {
    return _channel.invokeMethod<void>(
      'permanentlyDeleteTrashItem',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'trashId': trashId,
      },
    );
  }

  @override
  Future<EmptyTrashResult> emptyTrash(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'emptyTrash',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (value == null) {
      return const EmptyTrashResult(deleted: 0, errors: <String>[]);
    }
    return EmptyTrashResult.fromPlatform(value);
  }
}

class TrashMediaService implements MediaService {
  const TrashMediaService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<ScanResult> scanGallery(String galleryUuid) async {
    final stats = await getStats(galleryUuid);
    return ScanResult(
      total: stats.total,
      photos: stats.photos,
      animated: stats.animated,
      videos: stats.videos,
      added: 0,
      updated: 0,
      moved: 0,
      removed: 0,
      durationMs: 0,
    );
  }

  @override
  Future<GalleryStats> getStats(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getTrashMediaStats',
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
          'listTrashItems',
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
      'loadTrashThumbnail',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
        'maxPx': maxPx,
      },
    );
  }

  @override
  Future<ViewerSource> prepareViewerSource(
    String galleryUuid,
    String syncUuid,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'prepareTrashViewerSource',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_TRASH_VIEWER_SOURCE',
        message: 'Il media nel cestino non ha restituito una sorgente visualizzabile.',
      );
    }
    final source = ViewerSource.fromPlatform(value);
    if (source.kind.isEmpty || source.value.isEmpty) {
      throw PlatformException(
        code: 'INVALID_TRASH_VIEWER_SOURCE',
        message: 'La sorgente del media nel cestino non è valida.',
      );
    }
    return source;
  }
}
