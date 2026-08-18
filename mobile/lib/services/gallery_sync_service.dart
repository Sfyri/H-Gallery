import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gallery_profile.dart';

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

  factory GallerySyncResult.fromPlatform(Map<Object?, Object?> value) {
    int number(String key) => (value[key] as num?)?.toInt() ?? 0;
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
    );
  }
}

class GallerySyncProgress {
  const GallerySyncProgress({
    required this.phase,
    required this.processed,
    required this.total,
    required this.current,
  });

  final String phase;
  final int processed;
  final int total;
  final String current;

  double? get fraction => total <= 0 ? null : (processed / total).clamp(0.0, 1.0).toDouble();

  factory GallerySyncProgress.fromPlatform(Map<Object?, Object?> value) {
    return GallerySyncProgress(
      phase: value['phase']?.toString() ?? '',
      processed: (value['processed'] as num?)?.toInt() ?? 0,
      total: (value['total'] as num?)?.toInt() ?? 0,
      current: value['current']?.toString() ?? '',
    );
  }
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

  Future<Map<String, Object?>> _arguments(GalleryProfile gallery) async {
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
    return <String, Object?>{
      'galleryUuid': gallery.galleryUuid,
      'galleryName': gallery.name,
      'address': address,
      'port': port,
      'deviceId': deviceId,
      'token': token,
    };
  }

  Future<GallerySyncPlan> analyze(GalleryProfile gallery) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'analyzeSync',
      await _arguments(gallery),
    );
    if (value == null) {
      throw PlatformException(code: 'SYNC_EMPTY', message: 'Il PC non ha restituito un piano di merge.');
    }
    return GallerySyncPlan.fromPlatform(value);
  }

  Future<GallerySyncResult> run(GalleryProfile gallery) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'runSync',
      await _arguments(gallery),
    );
    if (value == null) {
      throw PlatformException(code: 'SYNC_EMPTY', message: 'La sincronizzazione non ha restituito un risultato.');
    }
    return GallerySyncResult.fromPlatform(value);
  }
}
