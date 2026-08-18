import 'package:flutter/material.dart';

import '../models/gallery_profile.dart';
import '../theme/app_theme.dart';

class GalleryReadyPage extends StatelessWidget {
  const GalleryReadyPage({required this.gallery, super.key});

  final GalleryProfile gallery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(gallery.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppTheme.success),
                    SizedBox(width: 10),
                    Text(
                      'Galleria collegata',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  gallery.locationLabel,
                  style: const TextStyle(color: AppTheme.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Struttura H-Gallery',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const _FolderRow(name: '.user', description: 'Dati tecnici della galleria'),
          const _FolderRow(name: '.toDo', description: 'Media da organizzare'),
          const _FolderRow(name: '.trash', description: 'Cestino della galleria'),
          const SizedBox(height: 24),
          const Text(
            'Identità locale',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SelectableText(
            gallery.galleryUuid,
            style: const TextStyle(
              color: AppTheme.muted,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.panel2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'La lettura dei media e il database Android verranno aggiunti nel prossimo passaggio. Per ora questa schermata conferma che H-Gallery mantiene l’accesso alla directory e la struttura richiesta.',
              style: TextStyle(color: AppTheme.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.name, required this.description});

  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.panel2,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Icon(Icons.folder_rounded, color: AppTheme.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
