import 'package:flutter/material.dart';

import '../models/gallery_profile.dart';
import '../theme/app_theme.dart';
import 'gallery_media_tab.dart';
import 'new_media_tab.dart';
import 'ranking_media_tab.dart';
import 'search_media_tab.dart';
import 'settings_page.dart';
import 'trash_media_tab.dart';

class GalleryReadyPage extends StatefulWidget {
  const GalleryReadyPage({required this.gallery, super.key});

  final GalleryProfile gallery;

  @override
  State<GalleryReadyPage> createState() => _GalleryReadyPageState();
}

class _GalleryReadyPageState extends State<GalleryReadyPage> {
  int _index = 0;
  int _galleryRevision = 0;

  String get _subtitle {
    switch (_index) {
      case 1:
        return 'New · .toDo';
      case 2:
        return 'Cerca e filtra';
      case 3:
        return 'Classifica personaggi';
      case 4:
        return 'Cestino';
      default:
        return 'Gallery';
    }
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(gallery: widget.gallery),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.gallery.name),
            Text(
              _subtitle,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          GalleryMediaTab(
            gallery: widget.gallery,
            refreshToken: _galleryRevision,
            onChanged: () => setState(() => _galleryRevision += 1),
          ),
          NewMediaTab(
            gallery: widget.gallery,
            onOrganized: () => setState(() => _galleryRevision += 1),
          ),
          SearchMediaTab(
            gallery: widget.gallery,
            refreshToken: _galleryRevision,
            onChanged: () async {
              if (mounted) setState(() => _galleryRevision += 1);
            },
          ),
          RankingMediaTab(
            gallery: widget.gallery,
            refreshToken: _galleryRevision,
          ),
          TrashMediaTab(
            gallery: widget.gallery,
            refreshToken: _galleryRevision,
            onChanged: () => setState(() => _galleryRevision += 1),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'New',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard_rounded),
            label: 'Classifica',
          ),
          NavigationDestination(
            icon: Icon(Icons.delete_outline_rounded),
            selectedIcon: Icon(Icons.delete_rounded),
            label: 'Trash',
          ),
        ],
      ),
    );
  }
}
