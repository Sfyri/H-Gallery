import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/models/trash_models.dart';

void main() {
  test('TrashStats legge conteggi e dimensione', () {
    final stats = TrashStats.fromPlatform(<Object?, Object?>{
      'total': 4,
      'totalBytes': 123456,
      'photos': 2,
      'animated': 1,
      'videos': 1,
    });

    expect(stats.total, 4);
    expect(stats.totalBytes, 123456);
    expect(stats.photos, 2);
    expect(stats.animated, 1);
    expect(stats.videos, 1);
  });

  test('TrashItem conserva identità e percorso originale', () {
    final item = TrashItem.fromPlatform(<Object?, Object?>{
      'trashId': 7,
      'syncUuid': 'media-uuid',
      'relativePath': '.trash/Serie/Personaggio/foto.jpg',
      'filename': 'foto.jpg',
      'extension': 'jpg',
      'mediaType': 'image',
      'isAnimated': false,
      'mimeType': 'image/jpeg',
      'sizeBytes': 42,
      'modifiedEpochMs': 100,
      'sha256': 'abc',
      'originalRelativePath': 'Serie/Personaggio/foto.jpg',
      'trashRelativePath': '.trash/Serie/Personaggio/foto.jpg',
      'deletedAtEpochMs': 200,
    });

    expect(item.trashId, 7);
    expect(item.media.syncUuid, 'media-uuid');
    expect(item.originalRelativePath, 'Serie/Personaggio/foto.jpg');
    expect(item.deletedAtEpochMs, 200);
  });

  test('TrashRestoreResult distingue conflitto e ripristino', () {
    final conflict = TrashRestoreResult.fromPlatform(<Object?, Object?>{
      'status': 'conflict',
      'relativePath': 'Serie/A/foto.jpg',
      'renamed': false,
    });
    final restored = TrashRestoreResult.fromPlatform(<Object?, Object?>{
      'status': 'restored',
      'relativePath': 'Serie/A/foto_restored_001.jpg',
      'renamed': true,
    });

    expect(conflict.isConflict, isTrue);
    expect(conflict.isRestored, isFalse);
    expect(restored.isRestored, isTrue);
    expect(restored.renamed, isTrue);
  });
}
