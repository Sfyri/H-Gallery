import 'package:flutter_test/flutter_test.dart';
import 'package:h_gallery_mobile/main.dart';
import 'package:h_gallery_mobile/models/gallery_profile.dart';
import 'package:h_gallery_mobile/services/gallery_bridge.dart';

class _FakeGalleryService implements GalleryService {
  @override
  Future<GalleryProfile?> addGallery({String nameHint = ''}) async => null;

  @override
  Future<void> disconnectGallery(String galleryUuid) async {}

  @override
  Future<List<GalleryProfile>> listGalleries() async => const [];
}

void main() {
  testWidgets('mostra lo stato iniziale senza gallerie', (tester) async {
    await tester.pumpWidget(HGalleryApp(galleryService: _FakeGalleryService()));
    await tester.pumpAndSettle();

    expect(find.text('H-Gallery'), findsOneWidget);
    expect(find.text('Nessuna galleria collegata'), findsOneWidget);
  });
}
