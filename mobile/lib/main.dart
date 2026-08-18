import 'package:flutter/material.dart';

import 'screens/gallery_home_page.dart';
import 'services/gallery_bridge.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HGalleryApp());
}

class HGalleryApp extends StatelessWidget {
  const HGalleryApp({super.key, this.galleryService});

  final GalleryService? galleryService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'H-Gallery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: GalleryHomePage(
        galleryService: galleryService ?? const PlatformGalleryService(),
      ),
    );
  }
}

// Mantiene compatibilità con il test/template Flutter generato inizialmente.
class MyApp extends HGalleryApp {
  const MyApp({super.key});
}
