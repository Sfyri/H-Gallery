import 'package:flutter/services.dart';

class EditableMediaCharacter {
  const EditableMediaCharacter({
    required this.id,
    required this.name,
    required this.franchiseName,
    required this.label,
  });

  final int id;
  final String name;
  final String franchiseName;
  final String label;

  factory EditableMediaCharacter.fromPlatform(Map<Object?, Object?> value) {
    final rawId = value['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
    return EditableMediaCharacter(
      id: id,
      name: value['name']?.toString() ?? '',
      franchiseName: value['franchiseName']?.toString() ?? '',
      label: value['label']?.toString() ?? '',
    );
  }
}

class EditableMediaMetadata {
  const EditableMediaMetadata({
    required this.syncUuid,
    required this.relativePath,
    required this.metadataExplicit,
    required this.characterIds,
    required this.characters,
    required this.tags,
    required this.artists,
    required this.aiGenerated,
  });

  final String syncUuid;
  final String relativePath;
  final bool metadataExplicit;
  final List<int> characterIds;
  final List<EditableMediaCharacter> characters;
  final List<String> tags;
  final List<String> artists;
  final bool aiGenerated;

  factory EditableMediaMetadata.fromPlatform(Map<Object?, Object?> value) {
    List<int> ints(Object? raw) {
      if (raw is! List) return const <int>[];
      return raw
          .map((entry) => entry is num ? entry.toInt() : int.tryParse('$entry'))
          .whereType<int>()
          .toList(growable: false);
    }

    List<String> strings(Object? raw) {
      if (raw is! List) return const <String>[];
      return raw
          .map((entry) => entry?.toString().trim() ?? '')
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    }

    final rawCharacters = value['characters'];
    final characters = rawCharacters is List
        ? rawCharacters
            .whereType<Map>()
            .map(
              (entry) => EditableMediaCharacter.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <EditableMediaCharacter>[];

    return EditableMediaMetadata(
      syncUuid: value['syncUuid']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      metadataExplicit: value['metadataExplicit'] == true,
      characterIds: ints(value['characterIds']),
      characters: characters,
      tags: strings(value['tags']),
      artists: strings(value['artists']),
      aiGenerated: value['aiGenerated'] == true,
    );
  }
}

enum BatchMetadataMode {
  keep,
  add,
  remove,
  replace;

  String get wireName => name;
}

enum BatchAiMode {
  keep,
  enable,
  disable;

  String get wireName => name;
}

class BatchMetadataUpdateResult {
  const BatchMetadataUpdateResult({
    required this.requestedCount,
    required this.updatedCount,
  });

  final int requestedCount;
  final int updatedCount;

  factory BatchMetadataUpdateResult.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return BatchMetadataUpdateResult(
      requestedCount: readInt('requestedCount'),
      updatedCount: readInt('updatedCount'),
    );
  }
}

class MediaMetadataEditorService {
  const MediaMetadataEditorService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  Future<EditableMediaMetadata> getMetadata(
    String galleryUuid,
    String syncUuid,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getEditableMediaMetadata',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_EDITABLE_MEDIA_METADATA',
        message: 'I metadati del media non sono disponibili.',
      );
    }
    return EditableMediaMetadata.fromPlatform(value);
  }

  Future<EditableMediaMetadata> updateMetadata(
    String galleryUuid,
    String syncUuid, {
    required List<int> characterIds,
    required List<String> tags,
    required List<String> artists,
    required bool aiGenerated,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'updateMediaMetadata',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuid': syncUuid,
        'characterIds': characterIds,
        'tags': tags,
        'artists': artists,
        'aiGenerated': aiGenerated,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_MEDIA_METADATA_UPDATE',
        message: 'L’aggiornamento dei metadati non ha restituito un risultato.',
      );
    }
    return EditableMediaMetadata.fromPlatform(value);
  }

  Future<BatchMetadataUpdateResult> updateBatchMetadata(
    String galleryUuid,
    List<String> syncUuids, {
    required BatchMetadataMode characterMode,
    required List<int> characterIds,
    required BatchMetadataMode tagMode,
    required List<String> tags,
    required BatchMetadataMode artistMode,
    required List<String> artists,
    required BatchAiMode aiMode,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'updateMediaMetadataBatch',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncUuids': syncUuids,
        'characterMode': characterMode.wireName,
        'characterIds': characterIds,
        'tagMode': tagMode.wireName,
        'tags': tags,
        'artistMode': artistMode.wireName,
        'artists': artists,
        'aiMode': aiMode.wireName,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_MEDIA_METADATA_BATCH_UPDATE',
        message: 'L’aggiornamento multiplo non ha restituito un risultato.',
      );
    }
    return BatchMetadataUpdateResult.fromPlatform(value);
  }
}
