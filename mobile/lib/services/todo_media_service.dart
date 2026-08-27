import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/scan_result.dart';
import '../models/viewer_source.dart';
import 'media_bridge.dart';

/// MediaService adapter for the special `.toDo` area.
///
/// `.toDo` is intentionally NOT inserted in the gallery database. Android reads
/// it directly through SAF so the user remains in full control of what enters
/// the organization queue.
class TodoMediaService implements MediaService {
  const TodoMediaService();

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
      'getTodoStats',
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
          'listTodoMedia',
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
      'loadTodoThumbnail',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
        'maxPx': maxPx,
      },
    );
  }


  Future<int> moveMediaToTrashBatch(
    String galleryUuid,
    List<String> syncUuids,
  ) async {
    if (syncUuids.isEmpty) return 0;

    return await _channel.invokeMethod<int>(
          'trashTodoMediaBatch',
          <String, Object?>{
            'galleryUuid': galleryUuid,
            'tokens': syncUuids,
          },
        ) ??
        0;
  }

  @override
  Future<ViewerSource> prepareViewerSource(
    String galleryUuid,
    String syncUuid,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'prepareTodoViewerSource',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_TODO_VIEWER_SOURCE',
        message: 'Il media in .toDo non ha restituito una sorgente visualizzabile.',
      );
    }
    final source = ViewerSource.fromPlatform(value);
    if (source.kind.isEmpty || source.value.isEmpty) {
      throw PlatformException(
        code: 'INVALID_TODO_VIEWER_SOURCE',
        message: 'La sorgente del media in .toDo non è valida.',
      );
    }
    return source;
  }
}
