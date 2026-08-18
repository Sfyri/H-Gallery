import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/models/gallery_browse_models.dart';

void main() {
  test('MediaQuerySpec equality is stable', () {
    const first = MediaQuerySpec(
      text: 'hinata',
      kind: 'photo',
      relativePrefix: 'Naruto/Hinata',
      tag: 'night',
      artist: 'artist',
      aiOnly: true,
    );
    const second = MediaQuerySpec(
      text: 'hinata',
      kind: 'photo',
      relativePrefix: 'Naruto/Hinata',
      tag: 'night',
      artist: 'artist',
      aiOnly: true,
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.hasFilters, isTrue);
  });

  test('GalleryCollection parses platform values', () {
    final value = GalleryCollection.fromPlatform(<Object?, Object?>{
      'name': 'Hinata',
      'relativePath': 'Naruto/Hinata',
      'kind': 'character',
      'mediaCount': 12,
      'coverSyncUuid': 'abc',
    });

    expect(value.name, 'Hinata');
    expect(value.mediaCount, 12);
    expect(value.isCharacter, isTrue);
  });
}
