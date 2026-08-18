import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gallery_profile.dart';
import '../models/media_item.dart';
import '../models/organization_models.dart';
import '../services/organization_service.dart';
import '../theme/app_theme.dart';

class OrganizationPage extends StatefulWidget {
  const OrganizationPage({
    required this.gallery,
    required this.items,
    this.service = const OrganizationService(),
    super.key,
  });

  final GalleryProfile gallery;
  final List<MediaItem> items;
  final OrganizationService service;

  @override
  State<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends State<OrganizationPage> {
  final TextEditingController _characterSearchController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _artistsController = TextEditingController();
  final Set<int> _selectedCharacters = <int>{};

  OrganizationCatalog? _catalog;
  Object? _error;
  bool _loading = true;
  bool _busy = false;
  bool _aiGenerated = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _characterSearchController.addListener(_handleSearchChanged);
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    _characterSearchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _tagsController.dispose();
    _artistsController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final value = _characterSearchController.text.trim().toLowerCase();
    if (value == _query) return;
    setState(() => _query = value);
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.service.getCatalog(widget.gallery.galleryUuid);
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CharacterOption> get _visibleCharacters {
    final characters = _catalog?.characters ?? const <CharacterOption>[];
    if (_query.isEmpty) return characters;
    return characters.where((character) {
      return character.name.toLowerCase().contains(_query) ||
          character.franchiseName.toLowerCase().contains(_query) ||
          character.label.toLowerCase().contains(_query);
    }).toList(growable: false);
  }

  Future<void> _createFranchise() async {
    var name = '';
    var code = '';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuova serie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome serie'),
              onChanged: (value) => name = value,
            ),
            const SizedBox(height: 12),
            TextField(
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Codice (opzionale)',
                helperText: 'Se vuoto viene generato automaticamente.',
              ),
              onChanged: (value) => code = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) return;
    await _runCatalogMutation(() async {
      await widget.service.createFranchise(
        widget.gallery.galleryUuid,
        name: name,
        code: code,
      );
    });
  }

  Future<void> _createCharacter() async {
    final franchises = _catalog?.franchises ?? const <FranchiseOption>[];
    if (franchises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea prima almeno una serie.')),
      );
      return;
    }

    var franchiseId = franchises.first.id;
    var name = '';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo personaggio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: franchiseId,
                decoration: const InputDecoration(labelText: 'Serie'),
                items: franchises
                    .map(
                      (franchise) => DropdownMenuItem<int>(
                        value: franchise.id,
                        child: Text(franchise.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => franchiseId = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome personaggio'),
                onChanged: (value) => name = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    await _runCatalogMutation(() async {
      final created = await widget.service.createCharacter(
        widget.gallery.galleryUuid,
        franchiseId: franchiseId,
        name: name,
      );
      _selectedCharacters.add(created.id);
    });
  }

  Future<void> _runCatalogMutation(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      final catalog = await widget.service.getCatalog(widget.gallery.galleryUuid);
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewAndOrganize() async {
    if (_busy) return;
    if (_selectedCharacters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona almeno un personaggio.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final preview = await widget.service.preview(
        widget.gallery.galleryUuid,
        tokens: widget.items.map((item) => item.syncUuid).toList(growable: false),
        characterIds: _selectedCharacters.toList(growable: false),
        aiGenerated: _aiGenerated,
      );
      if (!mounted) return;

      final allowDuplicates = await _confirmPreview(preview);
      if (allowDuplicates == null || !mounted) return;

      final result = await widget.service.organize(
        widget.gallery.galleryUuid,
        tokens: widget.items.map((item) => item.syncUuid).toList(growable: false),
        characterIds: _selectedCharacters.toList(growable: false),
        tags: _parseNames(_tagsController.text),
        artists: _parseNames(_artistsController.text),
        aiGenerated: _aiGenerated,
        allowDuplicates: allowDuplicates,
      );
      if (!mounted) return;
      await _showResult(result);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmPreview(OrganizationPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final shown = preview.items.take(6).toList(growable: false);
        return AlertDialog(
          title: const Text('Conferma organizzazione'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SummaryRow(label: 'Media', value: '${preview.requested}'),
                  _SummaryRow(label: 'Destinazione', value: preview.destinationFolder),
                  _SummaryRow(label: 'Dimensione', value: _formatBytes(preview.totalBytes)),
                  if (preview.duplicateCount > 0)
                    _SummaryRow(
                      label: 'Duplicati',
                      value: '${preview.duplicateCount}',
                      warning: true,
                    ),
                  const SizedBox(height: 14),
                  const Text(
                    'Anteprima',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final item in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.duplicate
                                ? Icons.content_copy_rounded
                                : Icons.arrow_forward_rounded,
                            size: 17,
                            color: item.duplicate ? AppTheme.error : AppTheme.muted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              item.duplicate
                                  ? '${item.sourceRelativePath}\nDuplicato: ${item.duplicateRelativePath}'
                                  : item.destinationRelativePath,
                              style: const TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (preview.items.length > shown.length)
                    Text(
                      '…e altri ${preview.items.length - shown.length} media.',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  if (preview.duplicateCount > 0) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Per sicurezza i duplicati vengono lasciati in .toDo, a meno che tu scelga esplicitamente di includerli.',
                      style: TextStyle(color: AppTheme.muted, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla'),
            ),
            if (preview.duplicateCount > 0)
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Includi duplicati'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                preview.duplicateCount > 0 ? 'Organizza senza duplicati' : 'Organizza',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showResult(OrganizationBatchResult result) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Organizzazione completata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SummaryRow(label: 'Organizzati', value: '${result.organizedCount}'),
            _SummaryRow(label: 'Duplicati lasciati in New', value: '${result.duplicateCount}'),
            _SummaryRow(
              label: 'Errori',
              value: '${result.errorCount}',
              warning: result.errorCount > 0,
            ),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final error in result.errors.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${error.sourceRelativePath}: ${error.message}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.error),
                  ),
                ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<String> _parseNames(String raw) {
    final seen = <String>{};
    return raw
        .split(RegExp(r'[,;\n]+'))
        .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .toList(growable: false);
  }

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Organizzazione non riuscita.';
    }
    return 'Organizzazione non riuscita.';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 100 ? 0 : 2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizza'),
      ),
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _catalog == null)
            _LoadError(message: _errorMessage(_error), onRetry: _loadCatalog)
          else
            _buildForm(),
          if (_busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final catalog = _catalog ??
        const OrganizationCatalog(
          franchises: <FranchiseOption>[],
          characters: <CharacterOption>[],
          tags: <String>[],
          artists: <String>[],
        );
    final selected = catalog.characters
        .where((character) => _selectedCharacters.contains(character.id))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SectionCard(
          title: '${widget.items.length} media selezionati',
          child: Text(
            widget.items.length == 1
                ? widget.items.first.filename
                : '${widget.items.take(3).map((item) => item.filename).join(', ')}${widget.items.length > 3 ? '…' : ''}',
            style: const TextStyle(color: AppTheme.muted, height: 1.4),
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Personaggi',
          trailing: Text(
            '${_selectedCharacters.length} selezionati',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createFranchise,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Nuova serie'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createCharacter,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Nuovo personaggio'),
                  ),
                ],
              ),
              if (selected.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: selected
                      .map(
                        (character) => InputChip(
                          label: Text(character.label),
                          onDeleted: _busy
                              ? null
                              : () => setState(
                                    () => _selectedCharacters.remove(character.id),
                                  ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _characterSearchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Cerca personaggio o serie',
                ),
              ),
              const SizedBox(height: 8),
              if (catalog.characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Nessun personaggio disponibile. Crea una serie e poi un personaggio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted, height: 1.4),
                  ),
                )
              else if (_visibleCharacters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Nessun risultato.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 330),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _visibleCharacters.length,
                    itemBuilder: (context, index) {
                      final character = _visibleCharacters[index];
                      final selected = _selectedCharacters.contains(character.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected,
                        title: Text(character.name),
                        subtitle: Text('${character.franchiseName} · ${character.franchiseCode}'),
                        onChanged: _busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedCharacters.add(character.id);
                                  } else {
                                    _selectedCharacters.remove(character.id);
                                  }
                                });
                              },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Metadati',
          child: Column(
            children: [
              TextField(
                controller: _tagsController,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Tag',
                  hintText: catalog.tags.take(4).join(', '),
                  helperText: 'Separali con virgole.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _artistsController,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Artisti',
                  hintText: catalog.artists.take(4).join(', '),
                  helperText: 'Separali con virgole.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _aiGenerated,
                title: const Text('Generato con IA'),
                subtitle: const Text('Organizza nella sottocartella .AI.'),
                onChanged: _busy ? null : (value) => setState(() => _aiGenerated = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _previewAndOrganize,
          icon: const Icon(Icons.drive_file_move_outline),
          label: const Text('Verifica e organizza'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label, style: const TextStyle(color: AppTheme.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: warning ? AppTheme.error : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52, color: AppTheme.error),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}
