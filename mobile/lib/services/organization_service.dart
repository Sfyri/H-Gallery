import 'package:flutter/services.dart';

import '../models/organization_models.dart';

class OrganizationService {
  const OrganizationService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  Future<OrganizationCatalog> getCatalog(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getOrganizationCatalog',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_ORGANIZATION_CATALOG',
        message: 'Il catalogo di organizzazione è vuoto.',
      );
    }
    return OrganizationCatalog.fromPlatform(value);
  }

  Future<FranchiseOption> createFranchise(
    String galleryUuid, {
    required String name,
    String code = '',
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'createFranchise',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'name': name,
        'code': code,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_FRANCHISE',
        message: 'La serie non è stata creata.',
      );
    }
    return FranchiseOption.fromPlatform(value);
  }

  Future<CharacterOption> createCharacter(
    String galleryUuid, {
    required int franchiseId,
    required String name,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'createCharacter',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'franchiseId': franchiseId,
        'name': name,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_CHARACTER',
        message: 'Il personaggio non è stato creato.',
      );
    }
    return CharacterOption.fromPlatform(value);
  }

  Future<OrganizationPreview> preview(
    String galleryUuid, {
    required List<String> tokens,
    required List<int> characterIds,
    required bool aiGenerated,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'previewTodoOrganization',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'tokens': tokens,
        'characterIds': characterIds,
        'aiGenerated': aiGenerated,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_ORGANIZATION_PREVIEW',
        message: 'Impossibile preparare l’anteprima dell’organizzazione.',
      );
    }
    return OrganizationPreview.fromPlatform(value);
  }

  Future<OrganizationBatchResult> organize(
    String galleryUuid, {
    required List<String> tokens,
    required List<int> characterIds,
    required List<String> tags,
    required List<String> artists,
    required bool aiGenerated,
    required bool allowDuplicates,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'organizeTodoMediaBatch',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'tokens': tokens,
        'characterIds': characterIds,
        'tags': tags,
        'artists': artists,
        'aiGenerated': aiGenerated,
        'allowDuplicates': allowDuplicates,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_ORGANIZATION_RESULT',
        message: 'L’organizzazione non ha restituito un risultato.',
      );
    }
    return OrganizationBatchResult.fromPlatform(value);
  }
}
