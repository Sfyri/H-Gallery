import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../models/organization_models.dart';
import '../services/media_metadata_editor_service.dart';
import '../services/organization_service.dart';
import '../theme/app_theme.dart';

class BatchMetadataEditorPage extends StatefulWidget {
  const BatchMetadataEditorPage({
    super.key,
    required this.galleryUuid,
    required this.items,
  });

  final String galleryUuid;
  final List<MediaItem> items;

  @override
  State<BatchMetadataEditorPage> createState() => _BatchMetadataEditorPageState();
}

class _BatchMetadataEditorPageState extends State<BatchMetadataEditorPage> {
  final MediaMetadataEditorService _metadataService = const MediaMetadataEditorService();
  final OrganizationService _organizationService = const OrganizationService();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _artistsController = TextEditingController();

  OrganizationCatalog? _catalog;
  BatchMetadataMode _characterMode = BatchMetadataMode.keep;
  BatchMetadataMode _tagMode = BatchMetadataMode.keep;
  BatchMetadataMode _artistMode = BatchMetadataMode.keep;
  BatchAiMode _aiMode = BatchAiMode.keep;
  Set<int> _selectedCharacterIds = <int>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _tagsController.dispose();
    _artistsController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _organizationService.getCatalog(widget.galleryUuid);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  List<String> _parseNames(String value) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in value.split(RegExp(r'[,;\n]'))) {
      final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isEmpty) continue;
      final key = cleaned.toLowerCase();
      if (seen.add(key)) result.add(cleaned);
    }
    return result;
  }

  void _appendName(TextEditingController controller, String value) {
    final values = _parseNames(controller.text);
    if (values.any((entry) => entry.toLowerCase() == value.toLowerCase())) return;
    values.add(value);
    controller.text = values.join(', ');
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    setState(() {});
  }

  bool get _hasChanges =>
      _characterMode != BatchMetadataMode.keep ||
      _tagMode != BatchMetadataMode.keep ||
      _artistMode != BatchMetadataMode.keep ||
      _aiMode != BatchAiMode.keep;

  String? _validate() {
    if (!_hasChanges) return 'Scegli almeno una modifica da applicare.';
    if ((_characterMode == BatchMetadataMode.add ||
            _characterMode == BatchMetadataMode.remove) &&
        _selectedCharacterIds.isEmpty) {
      return 'Seleziona almeno un personaggio da aggiungere o rimuovere.';
    }
    if ((_tagMode == BatchMetadataMode.add || _tagMode == BatchMetadataMode.remove) &&
        _parseNames(_tagsController.text).isEmpty) {
      return 'Inserisci almeno un tag da aggiungere o rimuovere.';
    }
    if ((_artistMode == BatchMetadataMode.add ||
            _artistMode == BatchMetadataMode.remove) &&
        _parseNames(_artistsController.text).isEmpty) {
      return 'Inserisci almeno un artista da aggiungere o rimuovere.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Applicare le modifiche?'),
        content: Text(
          'I metadati verranno aggiornati su ${widget.items.length} '
          'media. I campi impostati su “Non modificare” verranno preservati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Applica'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _metadataService.updateBatchMetadata(
        widget.galleryUuid,
        widget.items.map((item) => item.syncUuid).toList(growable: false),
        characterMode: _characterMode,
        characterIds: _selectedCharacterIds.toList(growable: false),
        tagMode: _tagMode,
        tags: _parseNames(_tagsController.text),
        artistMode: _artistMode,
        artists: _parseNames(_artistsController.text),
        aiMode: _aiMode,
      );
      if (!mounted) return;
      if (result.updatedCount <= 0) {
        setState(() {
          _saving = false;
          _error = 'Nessun media è stato aggiornato.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message ?? 'Aggiornamento multiplo non riuscito.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(error);
      });
    }
  }

  String _errorMessage(Object error) {
    if (error is PlatformException) {
      return error.message ?? 'Operazione non riuscita.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Modifica ${widget.items.length} media'),
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
          : _catalog == null
              ? _ErrorState(message: _error ?? 'Catalogo non disponibile.', onRetry: _loadCatalog)
              : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    final catalog = _catalog!;
    final selectedCharacters = catalog.characters
        .where((character) => _selectedCharacterIds.contains(character.id))
        .toList(growable: false);
    final availableCharacters = catalog.characters
        .where((character) => !_selectedCharacterIds.contains(character.id))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _SelectionSummary(items: widget.items),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Text(
            'Ogni sezione è indipendente. “Non modificare” conserva il valore '
            'attuale di ciascun media; “Sostituisci” usa esattamente i valori '
            'indicati e può quindi anche svuotare il campo.',
            style: TextStyle(color: AppTheme.muted),
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Personaggi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetadataModeField(
                value: _characterMode,
                onChanged: _saving ? null : (value) => setState(() => _characterMode = value),
              ),
              if (_characterMode != BatchMetadataMode.keep) ...[
                const SizedBox(height: 12),
                if (selectedCharacters.isEmpty)
                  const Text(
                    'Nessun personaggio scelto.',
                    style: TextStyle(color: AppTheme.muted),
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
                                : () => setState(
                                      () => _selectedCharacterIds.remove(character.id),
                                    ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                if (availableCharacters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey<int>(_selectedCharacterIds.length),
                    initialValue: null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Aggiungi alla modifica',
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
                ],
                if (_characterMode == BatchMetadataMode.replace &&
                    _selectedCharacterIds.isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Salvando così verranno rimossi tutti i personaggi dai media selezionati.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Tag',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetadataModeField(
                value: _tagMode,
                onChanged: _saving ? null : (value) => setState(() => _tagMode = value),
              ),
              if (_tagMode != BatchMetadataMode.keep) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _tagsController,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Tag',
                    hintText: 'food, pizza, wallpaper',
                    helperText: 'Separa i valori con virgole, punto e virgola o una nuova riga.',
                  ),
                ),
                if (catalog.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SuggestionWrap(
                    values: catalog.tags.take(16).toList(growable: false),
                    onSelected: (value) => _appendName(_tagsController, value),
                  ),
                ],
                if (_tagMode == BatchMetadataMode.replace &&
                    _parseNames(_tagsController.text).isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Salvando con il campo vuoto verranno rimossi tutti i tag generali.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Artisti',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MetadataModeField(
                value: _artistMode,
                onChanged: _saving ? null : (value) => setState(() => _artistMode = value),
              ),
              if (_artistMode != BatchMetadataMode.keep) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _artistsController,
                  enabled: !_saving,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Artisti',
                    hintText: 'Nome artista',
                    helperText: 'Separa i valori con virgole, punto e virgola o una nuova riga.',
                  ),
                ),
                if (catalog.artists.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SuggestionWrap(
                    values: catalog.artists.take(16).toList(growable: false),
                    onSelected: (value) => _appendName(_artistsController, value),
                  ),
                ],
                if (_artistMode == BatchMetadataMode.replace &&
                    _parseNames(_artistsController.text).isEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Salvando con il campo vuoto verranno rimossi tutti gli artisti.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Contenuto IA',
          child: DropdownButtonFormField<BatchAiMode>(
            initialValue: _aiMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Azione'),
            items: const [
              DropdownMenuItem(
                value: BatchAiMode.keep,
                child: Text('Non modificare'),
              ),
              DropdownMenuItem(
                value: BatchAiMode.enable,
                child: Text('Segna come IA'),
              ),
              DropdownMenuItem(
                value: BatchAiMode.disable,
                child: Text('Rimuovi IA'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) setState(() => _aiMode = value);
                  },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppTheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: Text(
            _saving ? 'Applicazione…' : 'Applica a ${widget.items.length} media',
          ),
        ),
      ],
    );
  }
}

class _MetadataModeField extends StatelessWidget {
  const _MetadataModeField({required this.value, required this.onChanged});

  final BatchMetadataMode value;
  final ValueChanged<BatchMetadataMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<BatchMetadataMode>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Azione'),
      items: const [
        DropdownMenuItem(
          value: BatchMetadataMode.keep,
          child: Text('Non modificare'),
        ),
        DropdownMenuItem(
          value: BatchMetadataMode.add,
          child: Text('Aggiungi'),
        ),
        DropdownMenuItem(
          value: BatchMetadataMode.remove,
          child: Text('Rimuovi'),
        ),
        DropdownMenuItem(
          value: BatchMetadataMode.replace,
          child: Text('Sostituisci'),
        ),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    final preview = items.take(4).toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${items.length} media selezionati',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final item in preview)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                item.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.muted),
              ),
            ),
          if (items.length > preview.length)
            Text(
              '+ ${items.length - preview.length} altri',
              style: const TextStyle(color: AppTheme.muted),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SuggestionWrap extends StatelessWidget {
  const _SuggestionWrap({required this.values, required this.onSelected});

  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: values
          .map(
            (value) => ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: Text(value),
              onPressed: () => onSelected(value),
            ),
          )
          .toList(growable: false),
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
