import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../screens/media_metadata_editor_page.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_metadata_editor_service.dart';
import '../theme/app_theme.dart';

Future<void> showMediaInfoSheet({
  required BuildContext context,
  required String galleryUuid,
  required MediaItem item,
  required GalleryBrowseService browseService,
  Future<void> Function()? onTrash,
}) async {
  // browseService remains in the public signature so every existing caller keeps
  // working. Metadata are intentionally read through the explicit editor API,
  // which can distinguish legacy path-derived values from user-edited values.
  final metadataService = const MediaMetadataEditorService();
  EditableMediaMetadata? metadata;
  Object? metadataError;
  try {
    metadata = await metadataService.getMetadata(galleryUuid, item.syncUuid);
  } catch (error) {
    metadataError = error;
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppTheme.panel,
    builder: (sheetContext) => SafeArea(
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
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final updated = await Navigator.of(sheetContext).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => MediaMetadataEditorPage(
                        galleryUuid: galleryUuid,
                        item: item,
                      ),
                    ),
                  );
                  if (updated == true && sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Modifica metadata'),
              ),
            ),
            if (onTrash != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await onTrash();
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Sposta nel cestino'),
                ),
              ),
            ],
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
