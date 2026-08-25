import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/gallery_profile.dart';
import '../theme/app_theme.dart';
import 'device_connection_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.gallery, super.key});

  static final Uri _creatorUrl = Uri.parse('https://github.com/Sfyri');

  final GalleryProfile gallery;

  Future<void> _openCreatorProfile(BuildContext context) async {
    final opened = await launchUrl(
      _creatorUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il profilo GitHub.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _SettingsCard(
            title: 'Galleria',
            children: [
              _InfoLine(label: 'Nome', value: gallery.name),
              _InfoLine(label: 'Cartella', value: gallery.directoryName),
              _InfoLine(label: 'Posizione', value: gallery.locationLabel),
              _InfoLine(
                label: 'Accesso',
                value: gallery.accessible ? 'Disponibile' : 'Non disponibile',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: 'Sincronizzazione',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.devices_rounded, color: AppTheme.accent),
                title: const Text('Collega PC'),
                subtitle: const Text('Apri la schermata di collegamento e sincronizzazione.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeviceConnectionPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'This tool is created by ',
                  style: TextStyle(color: AppTheme.muted),
                ),
                TextButton(
                  onPressed: () => _openCreatorProfile(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Sfyri',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: const TextStyle(color: AppTheme.muted)),
          ),
          Expanded(child: Text(value.isEmpty ? '—' : value)),
        ],
      ),
    );
  }
}
