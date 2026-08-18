import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery_profile.dart';

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

class GallerySyncPlan {
  const GallerySyncPlan({
    required this.androidCount,
    required this.windowsCount,
    required this.toAndroid,
    required this.toWindows,
    required this.alreadyPresent,
    required this.pathConflicts,
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
  final int bytesToAndroid;
  final int bytesToWindows;
  final String windowsGalleryUuid;
  final String windowsGalleryName;

  factory GallerySyncPlan.fromPlatform(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
    return GallerySyncPlan(
      androidCount: number('androidCount'),
      windowsCount: number('windowsCount'),
      toAndroid: number('toAndroid'),
      toWindows: number('toWindows'),
      alreadyPresent: number('alreadyPresent'),
      pathConflicts: number('pathConflicts'),
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
    return GallerySyncFailure(
      direction: value['direction']?.toString() ?? '',
      filename: value['filename']?.toString() ?? '',
      message: value['message']?.toString() ?? 'Errore non specificato.',
      network: value['network'] == true,
    );
  }
}

class GallerySyncResult {
  const GallerySyncResult({
    required this.downloaded,
    required this.uploaded,
    required this.alreadyPresent,
    required this.pathConflicts,
    required this.metadataMergedWindows,
    required this.unresolvedWindowsCharacters,
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
  final int alreadyPresent;
  final int pathConflicts;
  final int metadataMergedWindows;
  final int unresolvedWindowsCharacters;
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
      alreadyPresent: number('alreadyPresent'),
      pathConflicts: number('pathConflicts'),
      metadataMergedWindows: number('metadataMergedWindows'),
      unresolvedWindowsCharacters: number('unresolvedWindowsCharacters'),
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
        message: 'Il PC non è associato. Torna a “Collega PC” e ripeti il pairing.',
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
    } on SocketException catch (error) {
      throw PlatformException(code: 'NETWORK', message: 'PC non raggiungibile: ${error.message}');
    } on TimeoutException {
      throw PlatformException(code: 'NETWORK_TIMEOUT', message: 'Il PC non ha risposto in tempo.');
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
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'analyzeSync',
      await _arguments(gallery, windowsGallery, syncGroupUuid),
    );
    if (value == null) {
      throw PlatformException(code: 'SYNC_EMPTY', message: 'Il PC non ha restituito un piano di merge.');
    }
    return GallerySyncPlan.fromPlatform(value);
  }

  Future<void> cancel() {
    return _channel.invokeMethod<void>('cancelSync');
  }

  Future<GallerySyncResult> run(
    GalleryProfile gallery,
    WindowsGalleryProfile windowsGallery,
    String syncGroupUuid,
  ) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'runSync',
      await _arguments(gallery, windowsGallery, syncGroupUuid),
    );
    if (value == null) {
      throw PlatformException(code: 'SYNC_EMPTY', message: 'La sincronizzazione non ha restituito un risultato.');
    }
    return GallerySyncResult.fromPlatform(value);
  }
}
