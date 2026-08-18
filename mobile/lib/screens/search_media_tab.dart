import 'dart:async';

import 'package:flutter/material.dart';
import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../services/gallery_browse_service.dart';
import '../services/media_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/media_query_grid.dart';

class SearchMediaTab extends StatefulWidget {
  const SearchMediaTab({
    required this.gallery,
    this.refreshToken = 0,
    this.mediaService = const PlatformMediaService(),
    this.browseService = const PlatformGalleryBrowseService(),
    super.key,
  });

  final GalleryProfile gallery;
  final int refreshToken;
  final MediaService mediaService;
  final GalleryBrowseService browseService;

  @override
  State<SearchMediaTab> createState() => _SearchMediaTabState();
}

class _SearchMediaTabState extends State<SearchMediaTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  GalleryFilterCatalog? _catalog;
  MediaQuerySpec _query = const MediaQuerySpec();
  Object? _catalogError;
  bool _loadingCatalog = true;
  int _resultCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void didUpdateWidget(covariant SearchMediaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _catalogError = null;
    });
    try {
      final catalog = await widget.browseService.getFilterCatalog(
        widget.gallery.galleryUuid,
      );
      if (!mounted) return;
      setState(() => _catalog = catalog);
    } catch (error) {
      if (!mounted) return;
      setState(() => _catalogError = error);
    } finally {
      if (mounted) setState(() => _loadingCatalog = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() => _query = _query.copyWith(text: value));
    });
  }

  void _setKind(String kind) {
    setState(() {
      _query = _query.copyWith(kind: _query.kind == kind ? '' : kind);
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _debounce?.cancel();
    setState(() => _query = const MediaQuerySpec());
  }

  Future<void> _showFilters() async {
    final catalog = _catalog;
    if (catalog == null) return;

    var location = _query.relativePrefix;
    var tag = _query.tag;
    var artist = _query.artist;
    var aiOnly = _query.aiOnly;
    if (!catalog.locations.any((value) => value.relativePath == location)) {
      location = '';
    }
    if (!catalog.tags.contains(tag)) tag = '';
    if (!catalog.artists.contains(artist)) artist = '';

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.panel,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                18,
                4,
                18,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Filtri',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('location:$location'),
                    initialValue: location.isEmpty ? null : location,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Serie / cartella'),
                    items: catalog.locations
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value.relativePath,
                            child: Text(value.label, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setSheetState(() => location = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('tag:$tag'),
                    initialValue: tag.isEmpty ? null : tag,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tag'),
                    items: catalog.tags
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setSheetState(() => tag = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String>('artist:$artist'),
                    initialValue: artist.isEmpty ? null : artist,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Artista'),
                    items: catalog.artists
                        .map(
                          (value) => DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setSheetState(() => artist = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo contenuti IA'),
                    value: aiOnly,
                    onChanged: (value) => setSheetState(() => aiOnly = value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              location = '';
                              tag = '';
                              artist = '';
                              aiOnly = false;
                            });
                          },
                          child: const Text('Azzera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Applica'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (applied == true && mounted) {
      setState(() {
        _query = _query.copyWith(
          relativePrefix: location,
          tag: tag,
          artist: artist,
          aiOnly: aiOnly,
        );
      });
    }
  }

  int get _extraFilterCount {
    var count = 0;
    if (_query.relativePrefix.isNotEmpty) count += 1;
    if (_query.tag.isNotEmpty) count += 1;
    if (_query.artist.isNotEmpty) count += 1;
    if (_query.aiOnly) count += 1;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cerca file, serie, personaggi, tag…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Cancella ricerca',
                          onPressed: () {
                            _searchController.clear();
                            _debounce?.cancel();
                            setState(() => _query = _query.copyWith(text: ''));
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('Foto'),
                            selected: _query.kind == 'photo',
                            onSelected: (_) => _setKind('photo'),
                          ),
                          const SizedBox(width: 7),
                          FilterChip(
                            label: const Text('GIF'),
                            selected: _query.kind == 'animated',
                            onSelected: (_) => _setKind('animated'),
                          ),
                          const SizedBox(width: 7),
                          FilterChip(
                            label: const Text('Video'),
                            selected: _query.kind == 'video',
                            onSelected: (_) => _setKind('video'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Badge(
                    isLabelVisible: _extraFilterCount > 0,
                    label: Text('$_extraFilterCount'),
                    child: IconButton.filledTonal(
                      tooltip: 'Filtri avanzati',
                      onPressed: _loadingCatalog ? null : _showFilters,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                ],
              ),
              if (_catalogError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Alcuni filtri non sono disponibili.',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ),
                      TextButton(onPressed: _loadCatalog, child: const Text('Riprova')),
                    ],
                  ),
                ),
              if (_query.hasFilters)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_resultCount risultati',
                          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                        label: const Text('Azzera'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: MediaQueryGrid(
            gallery: widget.gallery,
            query: _query,
            refreshToken: widget.refreshToken,
            mediaService: widget.mediaService,
            browseService: widget.browseService,
            onTotalChanged: (value) {
              if (mounted && value != _resultCount) {
                setState(() => _resultCount = value);
              }
            },
          ),
        ),
      ],
    );
  }
}
