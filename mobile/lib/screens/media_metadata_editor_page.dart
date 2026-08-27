import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/organization_models.dart';
import '../services/media_metadata_editor_service.dart';
import '../services/organization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/tag_chip.dart';

class MediaMetadataEditorPage extends StatefulWidget {
  const MediaMetadataEditorPage({
    super.key,
    required this.galleryUuid,
    required this.item,
  });

  final String galleryUuid;
  final MediaItem item;

  @override
  State<MediaMetadataEditorPage> createState() => _MediaMetadataEditorPageState();
}

class _MediaMetadataEditorPageState extends State<MediaMetadataEditorPage> {
  final MediaMetadataEditorService _metadataService = const MediaMetadataEditorService();
  final OrganizationService _organizationService = const OrganizationService();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _artistsController = TextEditingController();

  OrganizationCatalog? _catalog;
  EditableMediaMetadata? _metadata;
  Set<int> _selectedCharacterIds = <int>{};
  bool _aiGenerated = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tagsController.dispose();
    _artistsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _metadataService.getMetadata(widget.galleryUuid, widget.item.syncUuid),
        _organizationService.getCatalog(widget.galleryUuid),
      ]);
      final metadata = results[0] as EditableMediaMetadata;
      final catalog = results[1] as OrganizationCatalog;
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _catalog = catalog;
        _selectedCharacterIds = metadata.characterIds.toSet();
        _tagsController.text = metadata.tags.join(', ');
        _artistsController.text = metadata.artists.join(', ');
        _aiGenerated = metadata.aiGenerated;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<String> _parseNames(String value) {
    final seen = <String>{};
    final values = <String>[];
    for (final raw in value.split(RegExp(r'[,;\n]'))) {
      final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isEmpty) continue;
      final key = cleaned.toLowerCase();
      if (seen.add(key)) values.add(cleaned);
    }
    return values;
  }

  bool _isNameSeparator(String value) {
    return value == ',' || value == ';' || value == '\n';
  }

  int _controllerOffset(TextEditingController controller) {
    final offset = controller.selection.extentOffset;
    if (offset < 0 || offset > controller.text.length) {
      return controller.text.length;
    }
    return offset;
  }

  int _fragmentStart(TextEditingController controller) {
    final text = controller.text;
    var start = _controllerOffset(controller);
    while (start > 0 && !_isNameSeparator(text[start - 1])) {
      start -= 1;
    }
    return start;
  }

  int _fragmentEnd(TextEditingController controller) {
    final text = controller.text;
    var end = _controllerOffset(controller);
    while (end < text.length && !_isNameSeparator(text[end])) {
      end += 1;
    }
    return end;
  }

  List<String> _matchingSuggestions(
    TextEditingController controller,
    List<String> available,
  ) {
    if (!controller.selection.isValid) return const <String>[];

    final text = controller.text;
    final start = _fragmentStart(controller);
    final end = _fragmentEnd(controller);
    final fragment = text.substring(start, _controllerOffset(controller)).trim().toLowerCase();
    if (fragment.isEmpty) return const <String>[];

    final completedText = '${text.substring(0, start)}${text.substring(end)}';
    final completed = _parseNames(completedText)
        .map((value) => value.toLowerCase())
        .toSet();

    final matches = available.where((value) {
      final key = value.toLowerCase();
      return key != fragment &&
          !completed.contains(key) &&
          key.contains(fragment);
    }).toList(growable: true);

    matches.sort((a, b) {
      final aKey = a.toLowerCase();
      final bKey = b.toLowerCase();
      final aStarts = aKey.startsWith(fragment);
      final bStarts = bKey.startsWith(fragment);
      if (aStarts != bStarts) return aStarts ? -1 : 1;
      return aKey.compareTo(bKey);
    });

    return matches.take(8).toList(growable: false);
  }

  void _applySuggestion(TextEditingController controller, String value) {
    final text = controller.text;
    final start = _fragmentStart(controller);
    final end = _fragmentEnd(controller);

    var insertion = value;
    if (start > 0 && (text[start - 1] == ',' || text[start - 1] == ';')) {
      insertion = ' $value';
    }

    final updated = '${text.substring(0, start)}$insertion${text.substring(end)}';
    final caret = start + insertion.length;
    controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _metadataService.updateMetadata(
        widget.galleryUuid,
        widget.item.syncUuid,
        characterIds: _selectedCharacterIds.toList(growable: false),
        tags: _parseNames(_tagsController.text),
        artists: _parseNames(_artistsController.text),
        aiGenerated: _aiGenerated,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _saving = false;
      });
    }
  }

  Future<void> _createSeries() async {
    var name = '';
    var code = '';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuova serie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => name = value,
              decoration: const InputDecoration(labelText: 'Nome serie'),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (value) => code = value,
              decoration: const InputDecoration(
                labelText: 'Codice (opzionale)',
                helperText: 'Se vuoto verrà gestito da H-Gallery.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final cleaned = name.trim();
              if (cleaned.isEmpty) return;
              Navigator.of(dialogContext).pop(<String, String>{
                'name': cleaned,
                'code': code.trim(),
              });
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      await _organizationService.createFranchise(
        widget.galleryUuid,
        name: result['name']!,
        code: result['code'] ?? '',
      );
      final catalog = await _organizationService.getCatalog(widget.galleryUuid);
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _createCharacter() async {
    final catalog = _catalog;
    if (catalog == null || catalog.franchises.isEmpty) {
      _showError('Crea prima almeno una serie.');
      return;
    }
    var name = '';
    var aliases = '';
    var franchiseId = catalog.franchises.first.id;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo personaggio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: franchiseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Serie'),
                items: catalog.franchises
                    .map(
                      (franchise) => DropdownMenuItem<int>(
                        value: franchise.id,
                        child: Text(franchise.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setDialogState(() => franchiseId = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (value) => name = value,
                decoration: const InputDecoration(labelText: 'Nome personaggio'),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => aliases = value,
                decoration: const InputDecoration(
                  labelText: 'Soprannomi (opzionale)',
                  helperText: 'Separali con virgole.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final cleaned = name.trim();
                if (cleaned.isEmpty) return;
                Navigator.of(dialogContext).pop(<String, Object?>{
                  'franchiseId': franchiseId,
                  'name': cleaned,
                  'aliases': aliases,
                });
              },
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      final created = await _organizationService.createCharacter(
        widget.galleryUuid,
        franchiseId: result['franchiseId'] as int,
        name: result['name'] as String,
        aliases: _parseNames(result['aliases']?.toString() ?? ''),
      );
      final updatedCatalog = await _organizationService.getCatalog(widget.galleryUuid);
      if (!mounted) return;
      setState(() {
        _catalog = updatedCatalog;
        _selectedCharacterIds.add(created.id);
      });
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifica metadata'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salva'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _metadata == null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    final catalog = _catalog!;
    final metadata = _metadata!;
    final selectedCharacters = catalog.characters
        .where((character) => _selectedCharacterIds.contains(character.id))
        .toList(growable: false);
    final availableCharacters = catalog.characters
        .where((character) => !_selectedCharacterIds.contains(character.id))
        .toList(growable: false);
    final currentTags = _parseNames(_tagsController.text);
    final currentArtists = _parseNames(_artistsController.text);
    final tagSuggestions = _matchingSuggestions(_tagsController, catalog.tags);
    final artistSuggestions = _matchingSuggestions(
      _artistsController,
      catalog.artists,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
      children: [
        Text(
          widget.item.filename,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          widget.item.relativePath,
          style: const TextStyle(color: AppTheme.muted),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            metadata.metadataExplicit
                ? 'Questa modifica aggiorna i metadata della galleria Android senza spostare o rinominare il file.'
                : 'Alcuni metadata iniziali possono essere dedotti dal percorso. Dopo il primo salvataggio diventano espliciti, senza spostare il file.',
            style: const TextStyle(color: AppTheme.muted),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('Personaggi'),
        if (selectedCharacters.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Nessun personaggio associato.', style: TextStyle(color: AppTheme.muted)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedCharacters
                .map(
                  (character) => InputChip(
                    label: Text(character.label),
                    onDeleted: _saving
                        ? null
                        : () => setState(() => _selectedCharacterIds.remove(character.id)),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 10),
        if (availableCharacters.isNotEmpty)
          DropdownButtonFormField<int>(
            key: ValueKey<int>(_selectedCharacterIds.length),
            initialValue: null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Aggiungi personaggio',
              prefixIcon: Icon(Icons.person_add_alt_1_rounded),
            ),
            items: availableCharacters
                .map(
                  (character) => DropdownMenuItem<int>(
                    value: character.id,
                    child: Text(character.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => _selectedCharacterIds.add(value));
                  },
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _createSeries,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Nuova serie'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _createCharacter,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Nuovo personaggio'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Tag'),
        TextField(
          controller: _tagsController,
          enabled: !_saving,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'food, pizza, wallpaper',
            helperText: 'Separa più tag con virgole, punto e virgola o una nuova riga.',
          ),
        ),
        if (currentTags.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TagValueWrap(
            values: currentTags,
            type: HGalleryTagType.general,
          ),
        ],
        if (tagSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SuggestionWrap(
            values: tagSuggestions,
            type: HGalleryTagType.general,
            onSelected: (value) => _applySuggestion(_tagsController, value),
          ),
        ],
        const SizedBox(height: 24),
        const _SectionTitle('Artisti'),
        TextField(
          controller: _artistsController,
          enabled: !_saving,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Nome artista',
            helperText: 'Separa più artisti con virgole, punto e virgola o una nuova riga.',
          ),
        ),
        if (currentArtists.isNotEmpty) ...[
          const SizedBox(height: 10),
          _TagValueWrap(
            values: currentArtists,
            type: HGalleryTagType.artist,
          ),
        ],
        if (artistSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SuggestionWrap(
            values: artistSuggestions,
            type: HGalleryTagType.artist,
            onSelected: (value) => _applySuggestion(_artistsController, value),
          ),
        ],
        const SizedBox(height: 20),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Contenuto IA'),
          subtitle: const Text('Marca questo media come generato con IA.'),
          value: _aiGenerated,
          onChanged: _saving ? null : (value) => setState(() => _aiGenerated = value),
        ),
        if (_aiGenerated)
          const Align(
            alignment: Alignment.centerLeft,
            child: HGalleryTagChip(
              label: 'AI',
              type: HGalleryTagType.system,
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_saving ? 'Salvataggio…' : 'Salva metadata'),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _TagValueWrap extends StatelessWidget {
  const _TagValueWrap({
    required this.values,
    required this.type,
  });

  final List<String> values;
  final HGalleryTagType type;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: values
            .map(
              (value) => HGalleryTagChip(
                label: value,
                type: type,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SuggestionWrap extends StatelessWidget {
  const _SuggestionWrap({
    required this.values,
    required this.type,
    required this.onSelected,
  });

  final List<String> values;
  final HGalleryTagType type;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: values
            .map(
              (value) => HGalleryTagChip(
                label: value,
                type: type,
                showAddIcon: true,
                onPressed: () => onSelected(value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
          ],
        ),
      ),
    );
  }
}
