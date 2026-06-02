import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../services/greatest_of_service.dart';
import '../../../services/platform_search_service.dart';
import '../../widgets/source_badges.dart';
import '../../widgets/track_action_menu.dart';

part 'greatest_of_screen_views.dart';
part 'greatest_of_screen_cards.dart';
part 'greatest_of_screen_widgets.dart';

class GreatestOfScreen extends ConsumerStatefulWidget {
  const GreatestOfScreen({super.key});
  @override
  ConsumerState<GreatestOfScreen> createState() => _GreatestOfScreenState();
}

class _GreatestOfScreenState extends ConsumerState<GreatestOfScreen> {
  String _selectedGenre = 'All';
  String _selectedRegion = 'All';
  String _artistFilter = '';
  int? _yearFrom;
  int? _yearTo;
  bool _groupByEra = false;
  bool _searchingPlatforms = false;
  List<PlatformTrackResult> _platformResults = [];

  final _artistController = TextEditingController();
  final _yearFromController = TextEditingController();
  final _yearToController = TextEditingController();
  final _svc = GreatestOfService();
  final _platformSearch = PlatformSearchService();

  String _lastSearchKey = '';

  @override
  void dispose() {
    _artistController.dispose();
    _yearFromController.dispose();
    _yearToController.dispose();
    super.dispose();
  }

  /// Auto-search platforms when filters change
  void _autoSearchPlatforms() {
    final searchKey = '$_selectedGenre|$_artistFilter|$_yearFrom|$_yearTo';
    if (searchKey == _lastSearchKey) return;
    _lastSearchKey = searchKey;

    // Only search if we have a specific filter (not "All" with no artist)
    if (_selectedGenre == 'All' && _artistFilter.isEmpty) {
      setState(() => _platformResults = []);
      return;
    }

    setState(() => _searchingPlatforms = true);

    Future<void> doSearch() async {
      try {
        List<PlatformTrackResult> results;
        if (_artistFilter.isNotEmpty) {
          results = await _platformSearch.searchByArtist(_artistFilter, limit: 100);
        } else {
          final era = _yearFrom != null ? '${_yearFrom}s' : null;
          results = await _platformSearch.searchByGenre(_selectedGenre, limit: 100, era: era);
        }
        if (mounted) setState(() { _platformResults = results; _searchingPlatforms = false; });
      } catch (_) {
        if (mounted) setState(() => _searchingPlatforms = false);
      }
    }
    doSearch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    final genres = ['All', 'Afrobeats', 'Amapiano', 'Hip-Hop', 'R&B', 'House',
        'Dancehall', 'Pop', 'Latin', 'Drill', 'Dance', 'UK Garage',
        ...{for (final t in allTracks) if (t.genre.isNotEmpty) t.genre}];
    final uniqueGenres = genres.toSet().toList();
    final regions = ['All', ...{for (final t in allTracks) if (t.leadRegion.isNotEmpty) t.leadRegion}];

    final topTracks = _svc.buildGreatestOfSet(
      tracks: allTracks,
      genre: _selectedGenre == 'All' ? null : _selectedGenre,
      artist: _artistFilter.isEmpty ? null : _artistFilter,
      region: _selectedRegion == 'All' ? null : _selectedRegion,
      yearFrom: _yearFrom,
      yearTo: _yearTo,
      limit: 500,
    );

    // Auto-search platforms
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSearchPlatforms());

    // Pre-compute greatest scores map for display
    final scoreMap = {for (final t in topTracks) t.id: _svc.computeGreatestScore(t)};

    // Era grouping
    final eraGroups = _groupByEra ? GreatestOfService.groupByEra(topTracks) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + filters
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events_rounded, color: AppTheme.amber, size: 24),
                  const SizedBox(width: 10),
                  Text('Greatest Of',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(width: 12),
                  Text(
                    '${topTracks.length} tracks',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  // Era grouping toggle
                  _ToggleChip(
                    label: 'Group by Era',
                    active: _groupByEra,
                    onTap: () => setState(() => _groupByEra = !_groupByEra),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Ranked by greatest-score — long-term popularity, DJ utility, and cultural impact.',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              // Filter row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Genre',
                      value: _selectedGenre,
                      options: uniqueGenres,
                      onChanged: (v) => setState(() => _selectedGenre = v),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Region',
                      value: _selectedRegion,
                      options: regions,
                      onChanged: (v) => setState(() => _selectedRegion = v),
                    ),
                    const SizedBox(width: 8),
                    // Artist text field
                    SizedBox(
                      width: 160,
                      height: 34,
                      child: TextField(
                        controller: _artistController,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Artist…',
                          hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 14, color: AppTheme.textTertiary),
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                        ),
                        onChanged: (v) => setState(() => _artistFilter = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Year from
                    SizedBox(
                      width: 90,
                      height: 34,
                      child: TextField(
                        controller: _yearFromController,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'From yr',
                          hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                        ),
                        onChanged: (v) => setState(() => _yearFrom = int.tryParse(v.trim())),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('–', style: TextStyle(color: AppTheme.textTertiary)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 90,
                      height: 34,
                      child: TextField(
                        controller: _yearToController,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'To yr',
                          hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                        ),
                        onChanged: (v) => setState(() => _yearTo = int.tryParse(v.trim())),
                      ),
                    ),
                    // Reset filters
                    if (_artistFilter.isNotEmpty || _yearFrom != null || _yearTo != null ||
                        _selectedGenre != 'All' || _selectedRegion != 'All') ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          _artistController.clear();
                          _yearFromController.clear();
                          _yearToController.clear();
                          setState(() {
                            _artistFilter = '';
                            _yearFrom = null;
                            _yearTo = null;
                            _selectedGenre = 'All';
                            _selectedRegion = 'All';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.panelRaised,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          child: const Text('Clear', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Content
        Expanded(
          child: topTracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_off_rounded, color: AppTheme.textTertiary, size: 48),
                      const SizedBox(height: 12),
                      const Text('No tracks match your filters',
                          style: TextStyle(color: AppTheme.textTertiary, fontSize: 14)),
                    ],
                  ),
                )
              : eraGroups != null
                  ? _EraGroupedView(eraGroups: eraGroups, scoreMap: scoreMap, ref: ref)
                  : CustomScrollView(
                      slivers: [
                        // Top 3 podium
                        if (topTracks.length >= 3)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                              child: _PodiumSection(
                                  tracks: topTracks.take(3).toList(),
                                  scoreMap: scoreMap,
                                  ref: ref),
                            ),
                          ),
                        // Grid of remaining tracks
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 220,
                              childAspectRatio: 0.72,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) {
                                final rank = topTracks.length >= 3 ? i + 4 : i + 1;
                                final trackIndex = topTracks.length >= 3 ? i + 3 : i;
                                if (trackIndex >= topTracks.length) return null;
                                return _TrackCard(
                                  track: topTracks[trackIndex],
                                  rank: rank,
                                  greatestScore: scoreMap[topTracks[trackIndex].id] ?? 0.0,
                                  ref: ref,
                                );
                              },
                              childCount: topTracks.length >= 3
                                  ? topTracks.length - 3
                                  : topTracks.length,
                            ),
                          ),
                        ),
                        // Platform results section
                        if (_platformResults.isNotEmpty || _searchingPlatforms) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(28, 20, 28, 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.cloud_download_rounded, color: AppTheme.cyan, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'From Apple Music & Spotify',
                                    style: TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_searchingPlatforms)
                                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyan))
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                                      child: Text('${_platformResults.length}', style: const TextStyle(color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_platformResults.isNotEmpty)
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, i) => _PlatformTrackRow(track: _platformResults[i], index: i),
                                  childCount: _platformResults.length,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }
}
