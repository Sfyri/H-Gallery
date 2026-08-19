import 'package:flutter/material.dart';

import '../models/gallery_profile.dart';
import '../theme/app_theme.dart';
import 'device_connection_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.gallery, super.key});

  final GalleryProfile gallery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _SectionTitle('Galleria'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(gallery.name),
                  subtitle: Text(gallery.locationLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Cartella'),
                  subtitle: Text(gallery.directoryName),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Connessione'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.devices_rounded),
              title: const Text('Collega PC'),
              subtitle: const Text(
                'Gestisci la connessione e la sincronizzazione con H-Gallery Windows.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceConnectionPage(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Informazioni'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('H-Gallery Android'),
              subtitle: Text(
                'Impostazioni della galleria mobile.',
                style: TextStyle(color: AppTheme.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}
