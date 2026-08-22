import 'package:flutter/services.dart';

abstract interface class StoryManagementService {
  Future<Map<Object?, Object?>> createFromGallery(
    String galleryUuid, {
    required String title,
    required List<String> syncUuids,
  });

  Future<Map<Object?, Object?>> updateStory(
    String galleryUuid, {
    required String currentRelativePath,
    required String title,
    required List<String> orderedSyncUuids,
    String? coverSyncUuid,
  });
}

class PlatformStoryManagementService implements StoryManagementService {
  const PlatformStoryManagementService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<Map<Object?, Object?>> createFromGallery(
    String galleryUuid, {
    required String title,
    required List<String> syncUuids,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'createStoryFromGallery',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'title': title,
        'syncUuids': syncUuids,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_STORY_CREATE_RESULT',
        message: 'La creazione della storia non ha restituito un risultato.',
      );
    }
    return value;
  }

  @override
  Future<Map<Object?, Object?>> updateStory(
    String galleryUuid, {
    required String currentRelativePath,
    required String title,
    required List<String> orderedSyncUuids,
    String? coverSyncUuid,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'updateStory',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'currentRelativePath': currentRelativePath,
        'title': title,
        'syncUuids': orderedSyncUuids,
        'coverSyncUuid': coverSyncUuid,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_STORY_UPDATE_RESULT',
        message: 'La modifica della storia non ha restituito un risultato.',
      );
    }
    return value;
  }
}
