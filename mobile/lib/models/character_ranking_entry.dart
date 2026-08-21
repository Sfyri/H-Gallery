import 'package:flutter/foundation.dart';

@immutable
class CharacterRankingEntry {
  const CharacterRankingEntry({
    required this.characterId,
    required this.name,
    required this.relativePath,
    required this.franchiseId,
    required this.franchiseName,
    required this.franchiseRelativePath,
    required this.mediaCount,
    required this.score,
  });

  final int characterId;
  final String name;
  final String relativePath;
  final int franchiseId;
  final String franchiseName;
  final String franchiseRelativePath;
  final int mediaCount;
  final int score;

  factory CharacterRankingEntry.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    String readString(String key) => value[key]?.toString() ?? '';

    return CharacterRankingEntry(
      characterId: readInt('characterId'),
      name: readString('name'),
      relativePath: readString('relativePath'),
      franchiseId: readInt('franchiseId'),
      franchiseName: readString('franchiseName'),
      franchiseRelativePath: readString('franchiseRelativePath'),
      mediaCount: readInt('mediaCount'),
      score: readInt('score').clamp(0, 1 << 31).toInt(),
    );
  }
}

@immutable
class RankingFranchise {
  const RankingFranchise({required this.franchiseId, required this.name});

  final int franchiseId;
  final String name;

  factory RankingFranchise.fromPlatform(Map<Object?, Object?> value) {
    final rawId = value['franchiseId'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    return RankingFranchise(
      franchiseId: id,
      name: value['name']?.toString() ?? '',
    );
  }
}
