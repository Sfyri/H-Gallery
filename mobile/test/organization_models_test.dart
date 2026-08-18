import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/models/organization_models.dart';

void main() {
  test('OrganizationCatalog legge serie, personaggi e metadati', () {
    final catalog = OrganizationCatalog.fromPlatform(<Object?, Object?>{
      'franchises': <Object?>[
        <Object?, Object?>{
          'id': 1,
          'syncUuid': 'franchise-1',
          'name': 'Naruto',
          'code': 'NRT',
          'relativePath': 'Naruto',
        },
      ],
      'characters': <Object?>[
        <Object?, Object?>{
          'id': 2,
          'syncUuid': 'character-1',
          'franchiseId': 1,
          'name': 'Hinata Hyuga',
          'relativePath': 'Naruto/Hinata Hyuga',
          'franchiseName': 'Naruto',
          'franchiseCode': 'NRT',
          'label': 'Naruto / Hinata Hyuga',
        },
      ],
      'tags': <Object?>['night', 'outdoors'],
      'artists': <Object?>['Artist'],
    });

    expect(catalog.franchises.single.code, 'NRT');
    expect(catalog.characters.single.franchiseId, 1);
    expect(catalog.tags, contains('night'));
    expect(catalog.artists, <String>['Artist']);
  });

  test('OrganizationBatchResult distingue modifiche ed errori', () {
    final result = OrganizationBatchResult.fromPlatform(<Object?, Object?>{
      'requested': 3,
      'organizedCount': 2,
      'duplicateCount': 0,
      'errorCount': 1,
      'errors': <Object?>[
        <Object?, Object?>{
          'sourceRelativePath': '.toDo/problem.jpg',
          'message': 'Errore di prova',
        },
      ],
    });

    expect(result.hasChanges, isTrue);
    expect(result.organizedCount, 2);
    expect(result.errors.single.sourceRelativePath, '.toDo/problem.jpg');
  });
}
