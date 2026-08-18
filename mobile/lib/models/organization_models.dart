class FranchiseOption {
  const FranchiseOption({
    required this.id,
    required this.syncUuid,
    required this.name,
    required this.code,
    required this.relativePath,
  });

  final int id;
  final String syncUuid;
  final String name;
  final String code;
  final String relativePath;

  factory FranchiseOption.fromPlatform(Map<Object?, Object?> value) {
    return FranchiseOption(
      id: _readInt(value, 'id'),
      syncUuid: _readString(value, 'syncUuid'),
      name: _readString(value, 'name'),
      code: _readString(value, 'code'),
      relativePath: _readString(value, 'relativePath'),
    );
  }
}

class CharacterOption {
  const CharacterOption({
    required this.id,
    required this.syncUuid,
    required this.franchiseId,
    required this.name,
    required this.relativePath,
    required this.franchiseName,
    required this.franchiseCode,
    required this.label,
  });

  final int id;
  final String syncUuid;
  final int franchiseId;
  final String name;
  final String relativePath;
  final String franchiseName;
  final String franchiseCode;
  final String label;

  factory CharacterOption.fromPlatform(Map<Object?, Object?> value) {
    return CharacterOption(
      id: _readInt(value, 'id'),
      syncUuid: _readString(value, 'syncUuid'),
      franchiseId: _readInt(value, 'franchiseId'),
      name: _readString(value, 'name'),
      relativePath: _readString(value, 'relativePath'),
      franchiseName: _readString(value, 'franchiseName'),
      franchiseCode: _readString(value, 'franchiseCode'),
      label: _readString(value, 'label'),
    );
  }
}

class OrganizationCatalog {
  const OrganizationCatalog({
    required this.franchises,
    required this.characters,
    required this.tags,
    required this.artists,
  });

  final List<FranchiseOption> franchises;
  final List<CharacterOption> characters;
  final List<String> tags;
  final List<String> artists;

  factory OrganizationCatalog.fromPlatform(Map<Object?, Object?> value) {
    return OrganizationCatalog(
      franchises: _readMapList(value['franchises'])
          .map(FranchiseOption.fromPlatform)
          .toList(growable: false),
      characters: _readMapList(value['characters'])
          .map(CharacterOption.fromPlatform)
          .toList(growable: false),
      tags: _readStringList(value['tags']),
      artists: _readStringList(value['artists']),
    );
  }
}

class OrganizationPreviewItem {
  const OrganizationPreviewItem({
    required this.token,
    required this.sourceRelativePath,
    required this.filename,
    required this.destinationRelativePath,
    required this.duplicate,
    required this.duplicateRelativePath,
  });

  final String token;
  final String sourceRelativePath;
  final String filename;
  final String destinationRelativePath;
  final bool duplicate;
  final String duplicateRelativePath;

  factory OrganizationPreviewItem.fromPlatform(Map<Object?, Object?> value) {
    return OrganizationPreviewItem(
      token: _readString(value, 'token'),
      sourceRelativePath: _readString(value, 'sourceRelativePath'),
      filename: _readString(value, 'filename'),
      destinationRelativePath: _readString(value, 'destinationRelativePath'),
      duplicate: value['duplicate'] == true,
      duplicateRelativePath: _readString(value, 'duplicateRelativePath'),
    );
  }
}

class OrganizationPreview {
  const OrganizationPreview({
    required this.category,
    required this.destinationFolder,
    required this.requested,
    required this.duplicateCount,
    required this.totalBytes,
    required this.items,
  });

  final String category;
  final String destinationFolder;
  final int requested;
  final int duplicateCount;
  final int totalBytes;
  final List<OrganizationPreviewItem> items;

  factory OrganizationPreview.fromPlatform(Map<Object?, Object?> value) {
    return OrganizationPreview(
      category: _readString(value, 'category'),
      destinationFolder: _readString(value, 'destinationFolder'),
      requested: _readInt(value, 'requested'),
      duplicateCount: _readInt(value, 'duplicateCount'),
      totalBytes: _readInt(value, 'totalBytes'),
      items: _readMapList(value['items'])
          .map(OrganizationPreviewItem.fromPlatform)
          .toList(growable: false),
    );
  }
}

class OrganizationBatchResult {
  const OrganizationBatchResult({
    required this.requested,
    required this.organizedCount,
    required this.duplicateCount,
    required this.errorCount,
    required this.errors,
  });

  final int requested;
  final int organizedCount;
  final int duplicateCount;
  final int errorCount;
  final List<OrganizationError> errors;

  bool get hasChanges => organizedCount > 0;

  factory OrganizationBatchResult.fromPlatform(Map<Object?, Object?> value) {
    return OrganizationBatchResult(
      requested: _readInt(value, 'requested'),
      organizedCount: _readInt(value, 'organizedCount'),
      duplicateCount: _readInt(value, 'duplicateCount'),
      errorCount: _readInt(value, 'errorCount'),
      errors: _readMapList(value['errors'])
          .map(OrganizationError.fromPlatform)
          .toList(growable: false),
    );
  }
}

class OrganizationError {
  const OrganizationError({
    required this.sourceRelativePath,
    required this.message,
  });

  final String sourceRelativePath;
  final String message;

  factory OrganizationError.fromPlatform(Map<Object?, Object?> value) {
    return OrganizationError(
      sourceRelativePath: _readString(value, 'sourceRelativePath'),
      message: _readString(value, 'message'),
    );
  }
}

String _readString(Map<Object?, Object?> value, String key) {
  return value[key]?.toString() ?? '';
}

int _readInt(Map<Object?, Object?> value, String key) {
  final raw = value[key];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

List<Map<Object?, Object?>> _readMapList(Object? value) {
  if (value is! List) return const <Map<Object?, Object?>>[];
  return value.whereType<Map<Object?, Object?>>().toList(growable: false);
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
