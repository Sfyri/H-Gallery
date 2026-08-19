import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery_profile.dart';

String _friendlyNetworkFailure(String message) {
  final lower = message.trim().toLowerCase();
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return 'Il PC non ha risposto in tempo. Controlla la rete e riprova.';
  }
  return 'Connessione al PC interrotta. Controlla che PC e telefono siano sulla stessa rete e che H-Gallery Windows sia aperto. Puoi riprovare la sincronizzazione senza perdere i file già completati.';
}

class WindowsGalleryProfile {
  const WindowsGalleryProfile({
    required this.registryId,
    required this.galleryUuid,
    required this.name,
    required this.syncGroupUuid,
    required this.mediaCount,
    required this.available,
    required this.active,
    required this.syncReady,
  });
  final String registryId;
  final String galleryUuid;
  final String name;
  final String syncGroupUuid;
  final int mediaCount;
  final bool available;
  final bool active;
  final bool syncReady;

  bool get linked => syncGroupUuid.isNotEmpty;
  factory WindowsGalleryProfile.fromJson(Map<String, dynamic> value) {
    return WindowsGalleryProfile(
      registryId: value['registryId']?.toString() ?? '',
      galleryUuid: value['galleryUuid']?.toString() ?? '',
      name: value['name']?.toString() ?? 'Galleria Windows',
      syncGroupUuid: value['syncGroupUuid']?.toString() ?? '',
      mediaCount: (value['mediaCount'] as num?)?.toInt() ?? 0,
      available: value['available'] == true,
      active: value['active'] == true,
      syncReady: value['syncReady'] == true,
    );
  }
}
class GallerySyncStatus {
  const GallerySyncStatus({
    required this.lastSyncEpochMs,
    required this.androidCount,
    required this.windowsCount,
    required this.windowsGalleryUuid,
    required this.syncGroupUuid,
    required this.verified,
  });

  final int lastSyncEpochMs;
  final int androidCount;
  final int windowsCount;
  final String windowsGalleryUuid;
  final String syncGroupUuid;
  final bool verified;

  bool get hasHistory => lastSyncEpochMs > 0;
  factory GallerySyncStatus.fromPlatform(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    return GallerySyncStatus(
      lastSyncEpochMs: number('lastSyncEpochMs'),
      androidCount: number('androidCount'),
      windowsCount: number('windowsCount'),
      windowsGalleryUuid: value['windowsGalleryUuid']?.toString() ?? '',
      syncGroupUuid: value['syncGroupUuid']?.toString() ?? '',
      verified: value['verified'] == true,
    );
  }
}
class GalleryMetadataChange {
  const GalleryMetadataChange({
    required this.kind,
    required this.value,
    required this.action,
    required this.note,
  });

  final String kind;
  final String value;
  final String action;
  final String note;

  String get label => value.isEmpty ? kind : '$kind: $value';
  bool get removes => action == 'remove';
  bool get changesType => action == 'set';
  String get symbol => removes ? '−' : (changesType ? '↔' : '+');
  factory GalleryMetadataChange.fromPlatform(Map<Object?, Object?> value) {
    return GalleryMetadataChange(
      kind: value['kind']?.toString() ?? 'Metadata',
      value: value['value']?.toString() ?? '',
      action: value['action']?.toString() ?? 'add',
      note: value['note']?.toString() ?? '',
    );
  }
}
class GalleryMetadataDifference {
  const GalleryMetadataDifference({
    required this.filename,
    required this.relativePath,
    required this.toAndroid,
    required this.toWindows,
    required this.typeConflict,
    required this.changeCount,
  });

  final String filename;
  final String relativePath;
  final List<GalleryMetadataChange> toAndroid;
  final List<GalleryMetadataChange> toWindows;
  final bool typeConflict;
  final int changeCount;
  factory GalleryMetadataDifference.fromPlatform(Map<Object?, Object?> value) {
    List<GalleryMetadataChange> changes(Object? raw) {
      if (raw is! List) return const <GalleryMetadataChange>[];
      return raw
          .whereType<Map>()
          .map(
            (entry) => GalleryMetadataChange.fromPlatform(
              Map<Object?, Object?>.from(entry),
            ),
          )
          .toList(growable: false);
    }
    final rawCount = value['changeCount'];
    return GalleryMetadataDifference(
      filename: value['filename']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      toAndroid: changes(value['toAndroid']),
      toWindows: changes(value['toWindows']),
      typeConflict: value['typeConflict'] == true,
      changeCount: rawCount is num ? rawCount.toInt() : int.tryParse('$rawCount') ?? 0,
    );
  }
}
class GalleryMetadataConflict {
  const GalleryMetadataConflict({
    required this.filename,
    required this.relativePath,
    required this.message,
  });

  final String filename;
  final String relativePath;
  final String message;
  factory GalleryMetadataConflict.fromPlatform(Map<Object?, Object?> value) {
    return GalleryMetadataConflict(
      filename: value['filename']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      message: value['message']?.toString() ?? 'Conflitto metadata non risolvibile automaticamente.',
    );
  }
}
class GalleryDeletionDetail {
  const GalleryDeletionDetail({
    required this.direction,
    required this.filename,
    required this.relativePath,
    required this.matchKind,
    required this.action,
  });

  final String direction;
  final String filename;
  final String relativePath;
  final String matchKind;
  final String action;

  bool get onAndroid => direction == 'android';
  String get targetLabel => onAndroid ? 'Android' : 'Windows';
  factory GalleryDeletionDetail.fromPlatform(Map<Object?, Object?> value) {
    return GalleryDeletionDetail(
      direction: value['direction']?.toString() ?? '',
      filename: value['filename']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      matchKind: value['matchKind']?.toString() ?? '',
      action: value['action']?.toString() ?? 'trash',
    );
  }
}
class GalleryDeletionConflict {
  const GalleryDeletionConflict({
    required this.direction,
    required this.filename,
    required this.relativePath,
    required this.message,
  });

  final String direction;
  final String filename;
  final String relativePath;
  final String message;

  String get targetLabel => direction == 'android' ? 'Android' : 'Windows';
  factory GalleryDeletionConflict.fromPlatform(Map<Object?, Object?> value) {
    return GalleryDeletionConflict(
      direction: value['direction']?.toString() ?? '',
      filename: value['filename']?.toString() ?? '',
      relativePath: value['relativePath']?.toString() ?? '',
      message: value['message']?.toString() ?? 'Cancellazione bloccata per sicurezza.',
    );
  }
}
class GallerySyncPlan {
  const GallerySyncPlan({
    required this.androidCount,
    required this.windowsCount,
    required this.toAndroid,
    required this.toWindows,
    required this.alreadyPresent,
    required this.pathConflicts,
    required this.metadataDifferences,
    required this.metadataTypeConflicts,
    required this.metadataChangeCount,
    required this.metadataDetails,
    required this.metadataDetailsTruncated,
    required this.metadataBaselinePending,
    required this.metadataResolutionConflicts,
    required this.metadataResolutionConflictDetails,
    required this.deleteOnAndroid,
    required this.deleteOnWindows,
    required this.deletionPendingAndroid,
    required this.deletionPendingWindows,
    required this.deletionConflicts,
    required this.deletionDetails,
    required this.deletionDetailsTruncated,
    required this.deletionConflictDetails,
    required this.bytesToAndroid,
    required this.bytesToWindows,
    required this.windowsGalleryUuid,
    required this.windowsGalleryName,
  });
  final int androidCount;
  final int windowsCount;
  final int toAndroid;
  final int toWindows;
  final int alreadyPresent;
  final int pathConflicts;
  final int metadataDifferences;
  final int metadataTypeConflicts;
  final int metadataChangeCount;
  final List<GalleryMetadataDifference> metadataDetails;
  final bool metadataDetailsTruncated;
  final int metadataBaselinePending;
  final int metadataResolutionConflicts;
  final List<GalleryMetadataConflict> metadataResolutionConflictDetails;
  final int deleteOnAndroid;
  final int deleteOnWindows;
  final int deletionPendingAndroid;
  final int deletionPendingWindows;
  final int deletionConflicts;
  final List<GalleryDeletionDetail> deletionDetails;
  final bool deletionDetailsTruncated;
  final List<GalleryDeletionConflict> deletionConflictDetails;
  final int bytesToAndroid;
  final int bytesToWindows;
  final String windowsGalleryUuid;
  final String windowsGalleryName;
  int get pendingDeletions => deletionPendingAndroid + deletionPendingWindows;
  int get pendingChanges =>
      toAndroid + toWindows + metadataDifferences + pendingDeletions + metadataBaselinePending;
  bool get hasBlockingConflicts =>
      deletionConflicts > 0 || metadataResolutionConflicts > 0;
  bool get synchronized =>
      toAndroid == 0 &&
      toWindows == 0 &&
      metadataDifferences == 0 &&
      metadataBaselinePending == 0 &&
      metadataResolutionConflicts == 0 &&
      pendingDeletions == 0 &&
      deletionConflicts == 0;
  factory GallerySyncPlan.fromPlatform(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    final rawDetails = value['metadataDetails'];
    final metadataDetails = rawDetails is List
        ? rawDetails
            .whereType<Map>()
            .map(
              (entry) => GalleryMetadataDifference.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <GalleryMetadataDifference>[];
    final rawMetadataConflicts = value['metadataResolutionConflictDetails'];
    final metadataResolutionConflictDetails = rawMetadataConflicts is List
        ? rawMetadataConflicts
            .whereType<Map>()
            .map(
              (entry) => GalleryMetadataConflict.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <GalleryMetadataConflict>[];
    final rawDeletionDetails = value['deletionDetails'];
    final deletionDetails = rawDeletionDetails is List
        ? rawDeletionDetails
            .whereType<Map>()
            .map(
              (entry) => GalleryDeletionDetail.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <GalleryDeletionDetail>[];
    final rawDeletionConflicts = value['deletionConflictDetails'];
    final deletionConflictDetails = rawDeletionConflicts is List
        ? rawDeletionConflicts
            .whereType<Map>()
            .map(
              (entry) => GalleryDeletionConflict.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <GalleryDeletionConflict>[];
    return GallerySyncPlan(
      androidCount: number('androidCount'),
      windowsCount: number('windowsCount'),
      toAndroid: number('toAndroid'),
      toWindows: number('toWindows'),
      alreadyPresent: number('alreadyPresent'),
      pathConflicts: number('pathConflicts'),
      metadataDifferences: number('metadataDifferences'),
      metadataTypeConflicts: number('metadataTypeConflicts'),
      metadataChangeCount: number('metadataChangeCount'),
      metadataDetails: metadataDetails,
      metadataDetailsTruncated: value['metadataDetailsTruncated'] == true,
      metadataBaselinePending: number('metadataBaselinePending'),
      metadataResolutionConflicts: number('metadataResolutionConflicts'),
      metadataResolutionConflictDetails: metadataResolutionConflictDetails,
      deleteOnAndroid: number('deleteOnAndroid'),
      deleteOnWindows: number('deleteOnWindows'),
      deletionPendingAndroid: number('deletionPendingAndroid'),
      deletionPendingWindows: number('deletionPendingWindows'),
      deletionConflicts: number('deletionConflicts'),
      deletionDetails: deletionDetails,
      deletionDetailsTruncated: value['deletionDetailsTruncated'] == true,
      deletionConflictDetails: deletionConflictDetails,
      bytesToAndroid: number('bytesToAndroid'),
      bytesToWindows: number('bytesToWindows'),
      windowsGalleryUuid: value['windowsGalleryUuid']?.toString() ?? '',
      windowsGalleryName: value['windowsGalleryName']?.toString() ?? 'H-Gallery Windows',
    );
  }
}
class GallerySyncFailure {
  const GallerySyncFailure({
    required this.direction,
    required this.filename,
    required this.message,
    required this.network,
  });

  final String direction;
  final String filename;
  final String message;
  final bool network;
  factory GallerySyncFailure.fromPlatform(Map<Object?, Object?> value) {
    final network = value['network'] == true;
    final rawMessage = value['message']?.toString() ?? 'Errore non specificato.';
    return GallerySyncFailure(
      direction: value['direction']?.toString() ?? '',
      filename: value['filename']?.toString() ?? '',
      message: network ? _friendlyNetworkFailure(rawMessage) : rawMessage,
      network: network,
    );
  }
}
class GallerySyncResult {
  const GallerySyncResult({
    required this.downloaded,
    required this.uploaded,
    required this.deletedOnAndroid,
    required this.deletedOnWindows,
    required this.deletionAlreadyAbsentAndroid,
    required this.deletionAlreadyAbsentWindows,
    required this.deletionPendingAfter,
    required this.deletionConflictsBefore,
    required this.deletionConflictsAfter,
    required this.alreadyPresent,
    required this.pathConflicts,
    required this.metadataDifferencesBefore,
    required this.metadataDifferencesAfter,
    required this.metadataBaselinePendingBefore,
    required this.metadataBaselinePendingAfter,
    required this.metadataResolutionConflictsBefore,
    required this.metadataResolutionConflictsAfter,
    required this.metadataMergedWindows,
    required this.metadataChangedAndroid,
    required this.metadataChangedWindows,
    required this.createdFranchisesAndroid,
    required this.createdCharactersAndroid,
    required this.createdFranchisesWindows,
    required this.createdCharactersWindows,
    required this.unresolvedWindowsCharacters,
    required this.verifiedSynced,
    required this.androidCount,
    required this.windowsCount,
    required this.elapsedMs,
    required this.complete,
    required this.interrupted,
    required this.cancelled,
    required this.failedDownloads,
    required this.failedUploads,
    required this.pendingDownloads,
    required this.pendingUploads,
    required this.failures,
  });
  final int downloaded;
  final int uploaded;
  final int deletedOnAndroid;
  final int deletedOnWindows;
  final int deletionAlreadyAbsentAndroid;
  final int deletionAlreadyAbsentWindows;
  final int deletionPendingAfter;
  final int deletionConflictsBefore;
  final int deletionConflictsAfter;
  final int alreadyPresent;
  final int pathConflicts;
  final int metadataDifferencesBefore;
  final int metadataDifferencesAfter;
  final int metadataBaselinePendingBefore;
  final int metadataBaselinePendingAfter;
  final int metadataResolutionConflictsBefore;
  final int metadataResolutionConflictsAfter;
  final int metadataMergedWindows;
  final int metadataChangedAndroid;
  final int metadataChangedWindows;
  final int createdFranchisesAndroid;
  final int createdCharactersAndroid;
  final int createdFranchisesWindows;
  final int createdCharactersWindows;
  final int unresolvedWindowsCharacters;
  final bool verifiedSynced;
  final int androidCount;
  final int windowsCount;
  final int elapsedMs;
  final bool complete;
  final bool interrupted;
  final bool cancelled;
  final int failedDownloads;
  final int failedUploads;
  final int pendingDownloads;
  final int pendingUploads;
  final List<GallerySyncFailure> failures;
  int get failed => failedDownloads + failedUploads;
  int get pending => pendingDownloads + pendingUploads;
  factory GallerySyncResult.fromPlatform(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    final rawFailures = value['failures'];
    final failures = rawFailures is List
        ? rawFailures
            .whereType<Map>()
            .map(
              (entry) => GallerySyncFailure.fromPlatform(
                Map<Object?, Object?>.from(entry),
              ),
            )
            .toList(growable: false)
        : const <GallerySyncFailure>[];
    return GallerySyncResult(
      downloaded: number('downloaded'),
      uploaded: number('uploaded'),
      deletedOnAndroid: number('deletedOnAndroid'),
      deletedOnWindows: number('deletedOnWindows'),
      deletionAlreadyAbsentAndroid: number('deletionAlreadyAbsentAndroid'),
      deletionAlreadyAbsentWindows: number('deletionAlreadyAbsentWindows'),
      deletionPendingAfter: number('deletionPendingAfter'),
      deletionConflictsBefore: number('deletionConflictsBefore'),
      deletionConflictsAfter: number('deletionConflictsAfter'),
      alreadyPresent: number('alreadyPresent'),
      pathConflicts: number('pathConflicts'),
      metadataDifferencesBefore: number('metadataDifferencesBefore'),
      metadataDifferencesAfter: number('metadataDifferencesAfter'),
      metadataBaselinePendingBefore: number('metadataBaselinePendingBefore'),
      metadataBaselinePendingAfter: number('metadataBaselinePendingAfter'),
      metadataResolutionConflictsBefore: number('metadataResolutionConflictsBefore'),
      metadataResolutionConflictsAfter: number('metadataResolutionConflictsAfter'),
      metadataMergedWindows: number('metadataMergedWindows'),
      metadataChangedAndroid: number('metadataChangedAndroid'),
      metadataChangedWindows: number('metadataChangedWindows'),
      createdFranchisesAndroid: number('createdFranchisesAndroid'),
      createdCharactersAndroid: number('createdCharactersAndroid'),
      createdFranchisesWindows: number('createdFranchisesWindows'),
      createdCharactersWindows: number('createdCharactersWindows'),
      unresolvedWindowsCharacters: number('unresolvedWindowsCharacters'),
      verifiedSynced: value['verifiedSynced'] == true,
      androidCount: number('androidCount'),
      windowsCount: number('windowsCount'),
      elapsedMs: number('elapsedMs'),
      complete: value['complete'] == true,
      interrupted: value['interrupted'] == true,
      cancelled: value['cancelled'] == true,
      failedDownloads: number('failedDownloads'),
      failedUploads: number('failedUploads'),
      pendingDownloads: number('pendingDownloads'),
      pendingUploads: number('pendingUploads'),
      failures: failures,
    );
  }
}
class GallerySyncProgress {
  const GallerySyncProgress({
    required this.phase,
    required this.processed,
    required this.total,
    required this.current,
    this.succeeded = 0,
    this.failed = 0,
    this.attempt = 1,
    this.maxAttempts = 1,
  });

  final String phase;
  final int processed;
  final int total;
  final String current;
  final int succeeded;
  final int failed;
  final int attempt;
  final int maxAttempts;
  double? get fraction => total <= 0
      ? null
      : (processed / total).clamp(0.0, 1.0).toDouble();
  factory GallerySyncProgress.fromPlatform(Map<Object?, Object?> value) {
    int number(String key, [int fallback = 0]) =>
        (value[key] as num?)?.toInt() ?? fallback;
    return GallerySyncProgress(
      phase: value['phase']?.toString() ?? '',
      processed: number('processed'),
      total: number('total'),
      current: value['current']?.toString() ?? '',
      succeeded: number('succeeded'),
      failed: number('failed'),
      attempt: number('attempt', 1),
      maxAttempts: number('maxAttempts', 1),
    );
  }
}
class _ConnectionInfo {
  const _ConnectionInfo({
    required this.address,
    required this.port,
    required this.deviceId,
    required this.token,
  });

  final String address;
  final int port;
  final String deviceId;
  final String token;
}

class GallerySyncService {
  GallerySyncService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.sfyri.h_gallery_mobile/sync',
  );
  final StreamController<GallerySyncProgress> _progressController =
      StreamController<GallerySyncProgress>.broadcast();

  Stream<GallerySyncProgress> get progress => _progressController.stream;

  PlatformException _friendlyPlatformException(PlatformException error) {
    final raw = (error.message ?? '').trim();
    final lower = raw.toLowerCase();
    final code = error.code.toUpperCase();

    if (code == 'M6_NOT_PAIRED') {
      return PlatformException(
        code: error.code,
        message: 'Il PC non è associato. Torna a “Collega PC” e associa nuovamente il dispositivo.',
        details: error.details,
      );
    }

    final timeout = code == 'NETWORK_TIMEOUT' ||
        lower.contains('timed out') ||
        lower.contains('timeout');
    if (timeout) {
      return PlatformException(
        code: 'NETWORK_TIMEOUT',
        message: _friendlyNetworkFailure('timeout'),
        details: error.details,
      );
    }

    final network = code == 'NETWORK' ||
        code.contains('SOCKET') ||
        lower.contains('software caused connection abort') ||
        lower.contains('connection reset') ||
        lower.contains('broken pipe') ||
        lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('no route to host') ||
        lower.contains('pc non raggiungibile');
    if (network) {
      return PlatformException(
        code: 'NETWORK',
        message: _friendlyNetworkFailure(raw),
        details: error.details,
      );
    }

    return error;
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _progressController.close();
  }
  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'syncProgress') return;
    final arguments = call.arguments;
    if (arguments is Map<Object?, Object?> && !_progressController.isClosed) {
      _progressController.add(GallerySyncProgress.fromPlatform(arguments));
    }
  }
  Future<_ConnectionInfo> _connection() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('m6_pc_address');
    final port = prefs.getInt('m6_pc_port');
    final token = prefs.getString('m6_token');
    final deviceId = prefs.getString('m6_device_id');
    if (address == null || port == null || token == null || deviceId == null) {
      throw PlatformException(
        code: 'M6_NOT_PAIRED',
        message: 'Il PC non è associato. Torna a “Collega PC” e associa nuovamente il dispositivo.',
      );
    }
    return _ConnectionInfo(
      address: address,
      port: port,
      deviceId: deviceId,
      token: token,
    );
  }
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final info = await _connection();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('http://${info.address}:${info.port}$path'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode(<String, Object?>{
        'device_id': info.deviceId,
        'token': info.token,
        ...body,
      }));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final text = await utf8.decoder.bind(response).join();
      Map<String, dynamic> decoded = <String, dynamic>{};
      if (text.trim().isNotEmpty) {
        final value = jsonDecode(text);
        if (value is Map<String, dynamic>) decoded = value;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PlatformException(
          code: 'HTTP_${response.statusCode}',
          message: decoded['detail']?.toString() ?? 'Errore HTTP ${response.statusCode}.',
        );
      }
      return decoded;
    } on SocketException {
      throw PlatformException(
        code: 'NETWORK',
        message: _friendlyNetworkFailure(''),
      );
    } on TimeoutException {
      throw PlatformException(
        code: 'NETWORK_TIMEOUT',
        message: _friendlyNetworkFailure('timeout'),
      );
    } finally {
      client.close(force: true);
    }
  }
  Future<List<WindowsGalleryProfile>> listWindowsGalleries() async {
    final response = await _postJson('/api/mobile/sync/windows-galleries', const {});
    final raw = response['galleries'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((value) => WindowsGalleryProfile.fromJson(Map<String, dynamic>.from(value)))
        .toList(growable: false);
  }
  Future<String> getSyncGroupUuid(String galleryUuid) async {
    final value = await _channel.invokeMethod<String>(
      'getSyncGroup',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    return value?.trim() ?? '';
  }
  Future<GallerySyncStatus> getSyncStatus(String galleryUuid) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getSyncStatus',
      <String, Object?>{'galleryUuid': galleryUuid},
    );
    return GallerySyncStatus.fromPlatform(value ?? const <Object?, Object?>{});
  }
  Future<void> _setSyncGroupUuid(String galleryUuid, String groupUuid) {
    return _channel.invokeMethod<void>(
      'setSyncGroup',
      <String, Object?>{
        'galleryUuid': galleryUuid,
        'syncGroupUuid': groupUuid,
      },
    );
  }
  Future<String> linkGalleries(
    GalleryProfile androidGallery,
    WindowsGalleryProfile windowsGallery,
  ) async {
    final localGroup = await getSyncGroupUuid(androidGallery.galleryUuid);
    final response = await _postJson(
      '/api/mobile/sync/link',
      <String, Object?>{
        'android_gallery_uuid': androidGallery.galleryUuid,
        'android_gallery_name': androidGallery.name,
        'android_group_uuid': localGroup,
        'windows_registry_id': windowsGallery.registryId,
      },
    );
    final groupUuid = response['syncGroupUuid']?.toString().trim() ?? '';
    if (groupUuid.isEmpty) {
      throw PlatformException(code: 'SYNC_LINK_EMPTY', message: 'Il PC non ha restituito un ID di gruppo valido.');
    }
    await _setSyncGroupUuid(androidGallery.galleryUuid, groupUuid);
    return groupUuid;
  }
  Future<void> unlinkAndroidGallery(GalleryProfile gallery) {
    return _setSyncGroupUuid(gallery.galleryUuid, '');
  }
  Future<Map<String, Object?>> _arguments(
    GalleryProfile gallery,
    WindowsGalleryProfile windowsGallery,
    String syncGroupUuid,
  ) async {
    final info = await _connection();
    final localGroup = await getSyncGroupUuid(gallery.galleryUuid);
    if (localGroup.isEmpty || localGroup != syncGroupUuid) {
      throw PlatformException(
        code: 'SYNC_NOT_LINKED',
        message: 'La galleria Android non appartiene più a questo gruppo di sincronizzazione.',
      );
    }
    return <String, Object?>{
      'galleryUuid': gallery.galleryUuid,
      'galleryName': gallery.name,
      'address': info.address,
      'port': info.port,
      'deviceId': info.deviceId,
      'token': info.token,
      'syncGroupUuid': syncGroupUuid,
      'windowsGalleryUuid': windowsGallery.galleryUuid,
    };
  }
  Future<GallerySyncPlan> analyze(
    GalleryProfile gallery,
    WindowsGalleryProfile windowsGallery,
    String syncGroupUuid,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'analyzeSync',
        await _arguments(gallery, windowsGallery, syncGroupUuid),
      );
      if (value == null) {
        throw PlatformException(
          code: 'SYNC_EMPTY',
          message: 'Il PC non ha restituito un piano di sincronizzazione.',
        );
      }
      return GallerySyncPlan.fromPlatform(value);
    } on PlatformException catch (error) {
      throw _friendlyPlatformException(error);
    }
  }
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancelSync');
    } on PlatformException catch (error) {
      throw _friendlyPlatformException(error);
    }
  }
  Future<GallerySyncResult> run(
    GalleryProfile gallery,
    WindowsGalleryProfile windowsGallery,
    String syncGroupUuid,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'runSync',
        await _arguments(gallery, windowsGallery, syncGroupUuid),
      );
      if (value == null) {
        throw PlatformException(
          code: 'SYNC_EMPTY',
          message: 'La sincronizzazione non ha restituito un risultato.',
        );
      }
      return GallerySyncResult.fromPlatform(value);
    } on PlatformException catch (error) {
      throw _friendlyPlatformException(error);
    }
  }
}
