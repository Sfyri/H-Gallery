import 'package:flutter/material.dart';

import 'screens/gallery_home_page.dart';
import 'screens/share_import_page.dart';
import 'services/gallery_bridge.dart';
import 'services/shared_media_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HGalleryApp());
}

class HGalleryApp extends StatefulWidget {
  const HGalleryApp({
    super.key,
    this.galleryService,
    this.sharedMediaService,
  });

  final GalleryService? galleryService;
  final SharedMediaService? sharedMediaService;

  @override
  State<HGalleryApp> createState() => _HGalleryAppState();
}

class _HGalleryAppState extends State<HGalleryApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final GalleryService _galleryService;
  late final SharedMediaService _sharedMediaService;
  bool _shareRouteOpen = false;
  bool _checkingShare = false;

  @override
  void initState() {
    super.initState();
    _galleryService = widget.galleryService ?? const PlatformGalleryService();
    _sharedMediaService =
        widget.sharedMediaService ?? PlatformSharedMediaService();
    _sharedMediaService.startListening(_handleSharedMediaReceived);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPendingShareIfNeeded();
    });
  }

  @override
  void dispose() {
    _sharedMediaService.stopListening();
    super.dispose();
  }

  Future<void> _handleSharedMediaReceived() async {
    await _openPendingShareIfNeeded();
  }

  Future<void> _openPendingShareIfNeeded() async {
    if (!mounted || _shareRouteOpen || _checkingShare) return;
    _checkingShare = true;
    try {
      final batch = await _sharedMediaService.getPendingShare();
      if (!mounted || batch == null || _shareRouteOpen) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openPendingShareIfNeeded();
        });
        return;
      }

      _shareRouteOpen = true;
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShareImportPage(
            batch: batch,
            galleryService: _galleryService,
            sharedMediaService: _sharedMediaService,
          ),
        ),
      );
      _shareRouteOpen = false;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openPendingShareIfNeeded();
        });
      }
    } on Exception {
      // Se il canale non è ancora pronto, un successivo intent o frame riproverà.
    } finally {
      _checkingShare = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'H-Gallery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: GalleryHomePage(galleryService: _galleryService),
    );
  }
}

// Mantiene compatibilità con il test/template Flutter generato inizialmente.
class MyApp extends HGalleryApp {
  const MyApp({super.key});
}
