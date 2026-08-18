import 'media_item.dart';

class TrashStats {
  const TrashStats({
    required this.total,
    required this.totalBytes,
    this.photos = 0,
    this.animated = 0,
    this.videos = 0,
  });

  final int total;
  final int totalBytes;
  final int photos;
  final int animated;
  final int videos;

  factory TrashStats.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return TrashStats(
      total: readInt('total'),
      totalBytes: readInt('totalBytes'),
      photos: readInt('photos'),
      animated: readInt('animated'),
      videos: readInt('videos'),
    );
  }
}

class TrashItem {
  const TrashItem({
    required this.trashId,
    required this.media,
    required this.originalRelativePath,
    required this.trashRelativePath,
    required this.deletedAtEpochMs,
  });

  final int trashId;
  final MediaItem media;
  final String originalRelativePath;
  final String trashRelativePath;
  final int deletedAtEpochMs;

  factory TrashItem.fromPlatform(Map<Object?, Object?> value) {
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return TrashItem(
      trashId: readInt('trashId'),
      media: MediaItem.fromPlatform(value),
      originalRelativePath: value['originalRelativePath']?.toString() ?? '',
      trashRelativePath: value['trashRelativePath']?.toString() ?? '',
      deletedAtEpochMs: readInt('deletedAtEpochMs'),
    );
  }
}

class TrashRestoreResult {
  const TrashRestoreResult({
    required this.status,
    required this.relativePath,
    required this.renamed,
  });

  final String status;
  final String relativePath;
  final bool renamed;

  bool get isConflict => status == 'conflict';
  bool get isRestored => status == 'restored';

  factory TrashRestoreResult.fromPlatform(Map<Object?, Object?> value) {
    return TrashRestoreResult(
      status: value['status']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      renamed: value['renamed'] == true,
    );
  }
}

class EmptyTrashResult {
  const EmptyTrashResult({required this.deleted, required this.errors});

  final int deleted;
  final List<String> errors;

  factory EmptyTrashResult.fromPlatform(Map<Object?, Object?> value) {
    final rawDeleted = value['deleted'];
    final deleted = rawDeleted is int
        ? rawDeleted
        : int.tryParse(rawDeleted?.toString() ?? '') ?? 0;
    final rawErrors = value['errors'];
    final errors = rawErrors is List
        ? rawErrors.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];
    return EmptyTrashResult(deleted: deleted, errors: errors);
  }
}
