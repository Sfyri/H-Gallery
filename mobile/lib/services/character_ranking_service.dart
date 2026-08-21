import 'package:flutter/services.dart';

import '../models/character_ranking_entry.dart';

abstract interface class CharacterRankingService {
  Future<List<RankingFranchise>> getFranchises(String galleryUuid);

  Future<List<CharacterRankingEntry>> getRanking(
    String galleryUuid, {
    int limit = 500,
    int? franchiseId,
  });

  Future<CharacterRankingEntry> updateScore(
    String galleryUuid,
    int characterId,
    int delta,
  );
}

class PlatformCharacterRankingService implements CharacterRankingService {
  const PlatformCharacterRankingService();

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/media',
  );

  @override
  Future<List<RankingFranchise>> getFranchises(String galleryUuid) async {
    final values = await _channel.invokeListMethod<Object?>(
      'getRankingFranchises',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    if (values == null) return const <RankingFranchise>[];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(RankingFranchise.fromPlatform)
        .where((entry) => entry.franchiseId > 0 && entry.name.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<CharacterRankingEntry>> getRanking(
    String galleryUuid, {
    int limit = 500,
    int? franchiseId,
  }) async {
    final values = await _channel.invokeListMethod<Object?>(
      'getCharacterRanking',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'limit': limit.clamp(1, 500).toInt(),
        if (franchiseId != null) 'franchiseId': franchiseId,
      },
    );
    if (values == null) return const <CharacterRankingEntry>[];
    return values
        .whereType<Map<Object?, Object?>>()
        .map(CharacterRankingEntry.fromPlatform)
        .toList(growable: false);
  }

  @override
  Future<CharacterRankingEntry> updateScore(
    String galleryUuid,
    int characterId,
    int delta,
  ) async {
    if (delta != -1 && delta != 1) {
      throw ArgumentError.value(delta, 'delta', 'Deve essere -1 oppure +1.');
    }
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'updateCharacterScore',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'characterId': characterId,
        'delta': delta,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_CHARACTER_SCORE',
        message: 'Il punteggio aggiornato non è disponibile.',
      );
    }
    return CharacterRankingEntry.fromPlatform(value);
  }
}
