import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/models/media_item.dart';
import 'package:h_gallery_mobile/models/scan_result.dart';

void main() {
  test('MediaItem legge i dati nativi', () {
    final item = MediaItem.fromPlatform(<Object?, Object?>{
      'syncUuid': 'media-1',
      'relativePath': 'Serie/Personaggio/foto.gif',
      'filename': 'foto.gif',
      'extension': 'gif',
      'mediaType': 'image',
      'isAnimated': true,
      'mimeType': 'image/gif',
      'sizeBytes': 2048,
      'modifiedEpochMs': 1234,
      'sha256': 'abc',
    });

    expect(item.typeLabel, 'GIF');
    expect(item.relativePath, 'Serie/Personaggio/foto.gif');
    expect(item.sizeBytes, 2048);
  });

  test('ScanResult espone conteggi e modifiche', () {
    final result = ScanResult.fromPlatform(<Object?, Object?>{
      'total': 8,
      'photos': 5,
      'animated': 1,
      'videos': 2,
      'added': 2,
      'updated': 1,
      'moved': 0,
      'removed': 0,
      'durationMs': 250,
    });

    expect(result.total, 8);
    expect(result.hasChanges, isTrue);
  });
}
