import 'package:flutter/material.dart';

import '../models/gallery_browse_models.dart';
import '../models/media_item.dart';
import '../services/gallery_browse_service.dart';
import '../theme/app_theme.dart';

Future<void> showMediaInfoSheet({
  required BuildContext context,
  required String galleryUuid,
  required MediaItem item,
  required GalleryBrowseService browseService,
}) async {
  MediaMetadataInfo? metadata;
  Object? metadataError;
  try {
    metadata = await browseService.getMediaMetadata(galleryUuid, item.syncUuid);
  } catch (error) {
    metadataError = error;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppTheme.panel,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.filename,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _InfoRow(label: 'Tipo', value: item.typeLabel),
            _InfoRow(label: 'Dimensione', value: _formatBytes(item.sizeBytes)),
            _InfoRow(label: 'Percorso', value: item.relativePath),
            if (metadata != null) ...[
              _InfoRow(
                label: 'Personaggi',
                value: metadata.characters.isEmpty
                    ? '—'
                    : metadata.characters.map((value) => value.label).join(', '),
              ),
              _InfoRow(
                label: 'Tag',
                value: metadata.tags.isEmpty ? '—' : metadata.tags.join(', '),
              ),
              _InfoRow(
                label: 'Artisti',
                value: metadata.artists.isEmpty ? '—' : metadata.artists.join(', '),
              ),
              _InfoRow(
                label: 'IA',
                value: metadata.aiGenerated ? 'Sì' : 'No',
              ),
            ] else if (metadataError != null)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Metadati non disponibili.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            width: 94,
            child: Text(label, style: const TextStyle(color: AppTheme.muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
