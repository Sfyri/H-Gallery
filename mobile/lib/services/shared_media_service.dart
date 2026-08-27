import 'package:flutter/services.dart';

class SharedMediaItem {
  const SharedMediaItem({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String name;
  final String mimeType;
  final int sizeBytes;

  factory SharedMediaItem.fromPlatform(Map<Object?, Object?> value) {
    return SharedMediaItem(
      name: value['name']?.toString() ?? '',
      mimeType: value['mimeType']?.toString() ?? '',
      sizeBytes: _readInt(value['sizeBytes']),
    );
  }
}

class SharedMediaBatch {
  const SharedMediaBatch({
    required this.token,
    required this.items,
    required this.rejectedCount,
    required this.receivedAtEpochMs,
    required this.totalSizeBytes,
  });

  final String token;
  final List<SharedMediaItem> items;
  final int rejectedCount;
  final int receivedAtEpochMs;
  final int totalSizeBytes;

  int get count => items.length;

  factory SharedMediaBatch.fromPlatform(Map<Object?, Object?> value) {
    final rawItems = value['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<Object?, Object?>>()
            .map(SharedMediaItem.fromPlatform)
            .toList(growable: false)
        : const <SharedMediaItem>[];
    return SharedMediaBatch(
      token: value['token']?.toString() ?? '',
      items: items,
      rejectedCount: _readInt(value['rejectedCount']),
      receivedAtEpochMs: _readInt(value['receivedAtEpochMs']),
      totalSizeBytes: _readInt(value['totalSizeBytes']),
    );
  }
}

class SharedMediaImportResult {
  const SharedMediaImportResult({
    required this.copied,
    required this.failed,
    required this.failures,
    required this.remainingPending,
    required this.removeOriginalsRequested,
    required this.deletedOriginals,
    required this.originalsNotDeleted,
    required this.deleteConfirmationShown,
  });

  final int copied;
  final int failed;
  final List<String> failures;
  final int remainingPending;
  final bool removeOriginalsRequested;
  final int deletedOriginals;
  final int originalsNotDeleted;
  final bool deleteConfirmationShown;

  factory SharedMediaImportResult.fromPlatform(Map<Object?, Object?> value) {
    final rawFailures = value['failures'];
    return SharedMediaImportResult(
      copied: _readInt(value['copied']),
      failed: _readInt(value['failed']),
      failures: rawFailures is List
          ? rawFailures.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
      remainingPending: _readInt(value['remainingPending']),
      removeOriginalsRequested: value['removeOriginalsRequested'] == true,
      deletedOriginals: _readInt(value['deletedOriginals']),
      originalsNotDeleted: _readInt(value['originalsNotDeleted']),
      deleteConfirmationShown: value['deleteConfirmationShown'] == true,
    );
  }
}

abstract interface class SharedMediaService {
  Future<SharedMediaBatch?> getPendingShare();

  Future<void> clearPendingShare(String token);

  Future<SharedMediaImportResult> importPendingShare({
    required String token,
    required String galleryUuid,
    required bool removeOriginals,
  });

  void startListening(Future<void> Function() onSharedMediaReceived);

  void stopListening();
}

class PlatformSharedMediaService implements SharedMediaService {
  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/share',
  );

  Future<void> Function()? _onSharedMediaReceived;
  bool _listening = false;

  @override
  Future<SharedMediaBatch?> getPendingShare() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getPendingShare',
    );
    if (value == null) return null;
    final batch = SharedMediaBatch.fromPlatform(value);
    return batch.token.isEmpty ? null : batch;
  }

  @override
  Future<void> clearPendingShare(String token) {
    return _channel.invokeMethod<void>(
      'clearPendingShare',
      <String, Object?>{'token': token},
    );
  }

  @override
  Future<SharedMediaImportResult> importPendingShare({
    required String token,
    required String galleryUuid,
    required bool removeOriginals,
  }) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'importPendingShare',
      <String, Object?>{
        'token': token,
        'galleryUuid': galleryUuid,
        'removeOriginals': removeOriginals,
      },
    );
    if (value == null) {
      throw PlatformException(
        code: 'EMPTY_SHARE_IMPORT_RESULT',
        message: 'H-Gallery non ha ricevuto il risultato dell’importazione.',
      );
    }
    return SharedMediaImportResult.fromPlatform(value);
  }

  @override
  void startListening(Future<void> Function() onSharedMediaReceived) {
    _onSharedMediaReceived = onSharedMediaReceived;
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedMediaReceived') {
        await _onSharedMediaReceived?.call();
      }
    });
  }

  @override
  void stopListening() {
    _onSharedMediaReceived = null;
    if (!_listening) return;
    _listening = false;
    _channel.setMethodCallHandler(null);
  }
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
