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
          character.aliases.any(
            (alias) => alias.toLowerCase().contains(_query),
          ) ||
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
    var aliases = '';
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
              const SizedBox(height: 12),
              TextField(
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Soprannomi (opzionale)',
                  helperText: 'Separali con virgole.',
                ),
                onChanged: (value) => aliases = value,
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
        aliases: _parseNames(aliases),
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
      await widget.service.preview(
        widget.gallery.galleryUuid,
        tokens: widget.items.map((item) => item.syncUuid).toList(growable: false),
        characterIds: _selectedCharacters.toList(growable: false),
        aiGenerated: _aiGenerated,
      );
      if (!mounted) return;

      final result = await widget.service.organize(
        widget.gallery.galleryUuid,
        tokens: widget.items.map((item) => item.syncUuid).toList(growable: false),
        characterIds: _selectedCharacters.toList(growable: false),
        tags: _parseNames(_tagsController.text),
        artists: _parseNames(_artistsController.text),
        aiGenerated: _aiGenerated,
        allowDuplicates: false,
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

  String _errorMessage(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Organizzazione non riuscita.';
    }
    return 'Organizzazione non riuscita.';
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
    final tagSuggestions = _matchingSuggestions(_tagsController, catalog.tags);
    final artistSuggestions = _matchingSuggestions(
      _artistsController,
      catalog.artists,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _SectionCard(
          title: '${widget.items.length} media selezionati',
          child: const SizedBox.shrink(),
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
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Tag',
                  hintText: catalog.tags.take(4).join(', '),
                  helperText: 'Separali con virgole.',
                ),
              ),
              if (tagSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _NameSuggestionWrap(
                  values: tagSuggestions,
                  onSelected: (value) => _applySuggestion(_tagsController, value),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _artistsController,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Artisti',
                  hintText: catalog.artists.take(4).join(', '),
                  helperText: 'Separali con virgole.',
                ),
              ),
              if (artistSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                _NameSuggestionWrap(
                  values: artistSuggestions,
                  onSelected: (value) => _applySuggestion(_artistsController, value),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _aiGenerated,
                title: const Text('Generato con IA'),
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

class _NameSuggestionWrap extends StatelessWidget {
  const _NameSuggestionWrap({
    required this.values,
    required this.onSelected,
  });

  final List<String> values;
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
              (value) => ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(value),
                onPressed: () => onSelected(value),
              ),
            )
            .toList(growable: false),
      ),
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
