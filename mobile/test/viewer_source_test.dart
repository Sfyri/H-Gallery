import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/models/viewer_source.dart';

void main() {
  test('ViewerSource riconosce immagine preparata', () {
    final source = ViewerSource.fromPlatform(<Object?, Object?>{
      'kind': 'imageFile',
      'value': '/cache/media.gif',
    });

    expect(source.isImageFile, isTrue);
    expect(source.isVideoContentUri, isFalse);
  });

  test('ViewerSource riconosce video SAF', () {
    final source = ViewerSource.fromPlatform(<Object?, Object?>{
      'kind': 'videoContentUri',
      'value': 'content://com.android.providers.media.documents/video/1',
    });

    expect(source.isVideoContentUri, isTrue);
    expect(source.value, startsWith('content://'));
  });
}
