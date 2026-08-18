class MediaItem {
  const MediaItem({
    required this.syncUuid,
    required this.relativePath,
    required this.filename,
    required this.extension,
    required this.mediaType,
    required this.isAnimated,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedEpochMs,
    required this.sha256,
  });

  final String syncUuid;
  final String relativePath;
  final String filename;
  final String extension;
  final String mediaType;
  final bool isAnimated;
  final String mimeType;
  final int sizeBytes;
  final int modifiedEpochMs;
  final String sha256;

  bool get isVideo => mediaType == 'video';
  bool get isImage => mediaType == 'image';

  String get typeLabel {
    if (isVideo) return 'Video';
    if (isAnimated) return 'GIF';
    return 'Foto';
  }

  factory MediaItem.fromPlatform(Map<Object?, Object?> value) {
    String readString(String key) => value[key]?.toString() ?? '';
    int readInt(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return MediaItem(
      syncUuid: readString('syncUuid'),
      relativePath: readString('relativePath'),
      filename: readString('filename'),
      extension: readString('extension'),
      mediaType: readString('mediaType'),
      isAnimated: value['isAnimated'] == true,
      mimeType: readString('mimeType'),
      sizeBytes: readInt('sizeBytes'),
      modifiedEpochMs: readInt('modifiedEpochMs'),
      sha256: readString('sha256'),
    );
  }
}
