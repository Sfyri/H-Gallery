import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/character_ranking_entry.dart';
import '../models/gallery_browse_models.dart';
import '../models/gallery_profile.dart';
import '../services/character_ranking_service.dart';
import '../theme/app_theme.dart';
import 'filtered_media_page.dart';

class RankingMediaTab extends StatefulWidget {
  const RankingMediaTab({
    required this.gallery,
    required this.refreshToken,
    this.service = const PlatformCharacterRankingService(),
    super.key,
  });

  final GalleryProfile gallery;
  final int refreshToken;
  final CharacterRankingService service;

  @override
  State<RankingMediaTab> createState() => _RankingMediaTabState();
}

class _RankingMediaTabState extends State<RankingMediaTab> {
  List<CharacterRankingEntry> _entries = const <CharacterRankingEntry>[];
  List<RankingFranchise> _franchises = const <RankingFranchise>[];
  final Set<int> _updating = <int>{};
  int _selectedFranchiseId = 0;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RankingMediaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.gallery.galleryUuid != widget.gallery.galleryUuid) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final franchises = await widget.service.getFranchises(
        widget.gallery.galleryUuid,
      );
      var selectedId = _selectedFranchiseId;
      if (selectedId != 0 &&
          !franchises.any((entry) => entry.franchiseId == selectedId)) {
        selectedId = 0;
      }
      final entries = await widget.service.getRanking(
        widget.gallery.galleryUuid,
        limit: 500,
        franchiseId: selectedId == 0 ? null : selectedId,
      );
      if (!mounted) return;
      final sorted = entries.toList()..sort(_compareEntries);
      setState(() {
        _franchises = franchises;
        _selectedFranchiseId = selectedId;
        _entries = sorted;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _compareEntries(CharacterRankingEntry left, CharacterRankingEntry right) {
    final byScore = right.score.compareTo(left.score);
    if (byScore != 0) return byScore;
    final byName = left.name.toLowerCase().compareTo(right.name.toLowerCase());
    if (byName != 0) return byName;
    return left.franchiseName
        .toLowerCase()
        .compareTo(right.franchiseName.toLowerCase());
  }

  Future<void> _changeScore(CharacterRankingEntry entry, int delta) async {
    if (_updating.contains(entry.characterId)) return;
    if (delta < 0 && entry.score <= 0) return;
    setState(() => _updating.add(entry.characterId));
    try {
      final updated = await widget.service.updateScore(
        widget.gallery.galleryUuid,
        entry.characterId,
        delta,
      );
      if (!mounted) return;
      final values = _entries.toList();
      final index = values.indexWhere(
        (candidate) => candidate.characterId == updated.characterId,
      );
      if (index >= 0) {
        values[index] = updated;
      } else {
        values.add(updated);
      }
      values.sort(_compareEntries);
      setState(() => _entries = values);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_message(error))),
      );
    } finally {
      if (mounted) setState(() => _updating.remove(entry.characterId));
    }
  }

  void _openCharacter(CharacterRankingEntry entry) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FilteredMediaPage(
          gallery: widget.gallery,
          title: entry.name,
          query: MediaQuerySpec(relativePrefix: entry.relativePath),
          onChanged: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _entries.isEmpty) {
      return _RankingError(message: _message(_error), onRetry: _load);
    }

    final visible = _entries;
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(child: _buildFilter()),
          ),
          if (_error != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  _message(_error),
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            ),
          if (visible.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Nessun personaggio in classifica.',
                  style: TextStyle(color: AppTheme.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final entry = visible[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RankingRow(
                      rank: index + 1,
                      entry: entry,
                      busy: _updating.contains(entry.characterId),
                      onTap: () => _openCharacter(entry),
                      onMinus: entry.score > 0
                          ? () => _changeScore(entry, -1)
                          : null,
                      onPlus: () => _changeScore(entry, 1),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilter() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Serie',
        prefixIcon: Icon(Icons.filter_list_rounded),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedFranchiseId,
          isExpanded: true,
          items: <DropdownMenuItem<int>>[
            const DropdownMenuItem<int>(
              value: 0,
              child: Text('Tutte le serie'),
            ),
            ..._franchises.map(
              (franchise) => DropdownMenuItem<int>(
                value: franchise.franchiseId,
                child: Text(
                  franchise.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) {
            if (value == null || value == _selectedFranchiseId) return;
            setState(() => _selectedFranchiseId = value);
            _load();
          },
        ),
      ),
    );
  }

  String _message(Object? error) {
    if (error is PlatformException) {
      return error.message ?? 'Impossibile leggere la classifica.';
    }
    return 'Impossibile leggere la classifica.';
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.entry,
    required this.busy,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
  });

  final int rank;
  final CharacterRankingEntry entry;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.panel,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${entry.franchiseName} · ${entry.mediaCount} media',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Diminuisci punteggio',
              onPressed: busy ? null : onMinus,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 38,
              child: Text(
                '${entry.score}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Aumenta punteggio',
              onPressed: busy ? null : onPlus,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _RankingError extends StatelessWidget {
  const _RankingError({required this.message, required this.onRetry});

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
            const Icon(
              Icons.error_outline_rounded,
              size: 50,
              color: AppTheme.error,
            ),
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
