import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../services/greatest_of_service.dart';
import '../../../services/platform_search_service.dart';
import '../../widgets/source_badges.dart';
import '../../widgets/track_action_menu.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// Era-grouped view
// ─────────────────────────────────────────────────────────────────────────────

class _EraGroupedView extends StatelessWidget {
  final Map<String, List<Track>> eraGroups;
  final Map<String, double> scoreMap;
  final WidgetRef ref;
  const _EraGroupedView({required this.eraGroups, required this.scoreMap, required this.ref});

  @override
  Widget build(BuildContext context) {
    final eras = ['2000s', '2010s', '2020s'].where(eraGroups.containsKey).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      itemCount: eras.length,
      itemBuilder: (context, eraIdx) {
        final era = eras[eraIdx];
        final tracks = eraGroups[era]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.cyan]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(era, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Text('${tracks.length} tracks', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ]),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => _TrackCard(
                track: tracks[i],
                rank: i + 1,
                greatestScore: scoreMap[tracks[i].id] ?? 0.0,
                ref: ref,
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top 3 Podium — hero layout with large artwork
// ─────────────────────────────────────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<Track> tracks;
  final Map<String, double> scoreMap;
  final WidgetRef ref;
  const _PodiumSection({required this.tracks, required this.scoreMap, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // #1 — Hero card (large)
        Expanded(
          flex: 5,
          child: _HeroCard(
              track: tracks[0], rank: 1,
              greatestScore: scoreMap[tracks[0].id] ?? 0.0, ref: ref),
        ),
        const SizedBox(width: 12),
        // #2 and #3 stacked
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _RunnerUpCard(track: tracks[1], rank: 2,
                  greatestScore: scoreMap[tracks[1].id] ?? 0.0, ref: ref),
              const SizedBox(height: 12),
              _RunnerUpCard(track: tracks[2], rank: 3,
                  greatestScore: scoreMap[tracks[2].id] ?? 0.0, ref: ref),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _HeroCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final trendPct = (t.trendScore * 100).toInt();
    final greatestPct = (widget.greatestScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.amber.withValues(alpha: _hovered ? 0.18 : 0.12),
                AppTheme.panel,
                AppTheme.panel,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background artwork (blurred)
              if (t.artworkUrl.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.6),
                        colorBlendMode: BlendMode.darken,
                        errorWidget: (_, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              // Content overlay
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    // Large artwork
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: t.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: t.artworkUrl,
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                              errorWidget: (_, e, s) => _ArtPlaceholder(size: 180),
                            )
                          : _ArtPlaceholder(size: 180),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Crown + rank badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.amber, Color(0xFFFF8C00)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.emoji_events_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('#1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.violet.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(t.genre, style: const TextStyle(color: AppTheme.violet, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              SourceBadges(sources: t.effectiveSources, compact: true),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            t.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.artist,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          // Meta row
                          Row(
                            children: [
                              _MetaPill(icon: Icons.speed_rounded, text: '${t.bpm}'),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.music_note_rounded, text: t.keySignature),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.public_rounded, text: t.leadRegion),
                              const Spacer(),
                              // Score pair
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                                  const SizedBox(height: 4),
                                  _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
                                  const SizedBox(height: 4),
                                  Text('$greatestPct / $trendPct',
                                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Play button overlay
              if (_bestUrl(t) != null)
                Positioned(
                  left: 24 + 180 - 20,
                  bottom: 24,
                  child: GestureDetector(
                    onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.cyan,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.cyan.withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunnerUpCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _RunnerUpCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_RunnerUpCard> createState() => _RunnerUpCardState();
}

class _RunnerUpCardState extends State<_RunnerUpCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final rank = widget.rank;
    final accent = rank == 2 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 124,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: _hovered ? 0.1 : 0.06),
                AppTheme.panel,
              ],
            ),
          ),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: t.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                        errorWidget: (_, e, s) => _ArtPlaceholder(size: 92),
                      )
                    : _ArtPlaceholder(size: 92),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('#$rank', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 10)),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                            const SizedBox(height: 3),
                            _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.artist,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('${t.bpm} BPM', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 8),
                        Text(t.keySignature, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 8),
                        Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 10)),
                        const SizedBox(width: 8),
                        SourceBadges(sources: t.effectiveSources, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid card for ranks 4+
// ─────────────────────────────────────────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _TrackCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork with rank overlay
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _ArtPlaceholder(size: 120, rounded: false),
                              )
                            : _ArtPlaceholder(size: 120, rounded: false),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.rank}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10),
                        ),
                      ),
                    ),
                    // Score badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ScoreBadge(value: widget.greatestScore, color: AppTheme.amber, prefix: 'G'),
                          const SizedBox(height: 3),
                          _ScoreBadge(value: t.trendScore, color: AppTheme.cyan, prefix: 'T'),
                        ],
                      ),
                    ),
                    // Play button on hover
                    if (_hovered && _bestUrl(t) != null)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info section
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.artist,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${t.bpm}',
                          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.edge.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        SourceBadges(sources: t.effectiveSources, compact: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                    const SizedBox(height: 3),
                    _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 12),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  final double size;
  final bool rounded;
  const _ArtPlaceholder({this.size = 44, this.rounded = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.edge,
            AppTheme.panelRaised,
          ],
        ),
        borderRadius: rounded ? BorderRadius.circular(size * 0.16) : null,
      ),
      child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: size * 0.35),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score bar — inline horizontal bar with label
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ScoreBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(children: [
              Container(color: color.withValues(alpha: 0.15)),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        Text('${(value * 100).toInt()}',
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9)),
      ],
    );
  }
}

/// Compact badge version for artwork overlay
class _ScoreBadge extends StatelessWidget {
  final double value;
  final Color color;
  final String prefix;
  const _ScoreBadge({required this.value, required this.color, required this.prefix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$prefix${(value * 100).toInt()}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle chip
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.violet.withValues(alpha: 0.2) : AppTheme.panelRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.violet.withValues(alpha: 0.6) : AppTheme.edge.withValues(alpha: 0.5),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timeline_rounded,
              size: 13, color: active ? AppTheme.violet : AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                color: active ? AppTheme.violet : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isDense: true,
              dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}

// ignore: unused_element
Future<void> _openTrack(Track track) async {
  final url = _bestUrl(track);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Platform track row (for Spotify/Apple Music results)
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformTrackRow extends StatefulWidget {
  const _PlatformTrackRow({required this.track, required this.index});
  final PlatformTrackResult track;
  final int index;

  @override
  State<_PlatformTrackRow> createState() => _PlatformTrackRowState();
}

class _PlatformTrackRowState extends State<_PlatformTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.panelRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('${widget.index + 1}', textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: t.artworkUrl != null
                  ? CachedNetworkImage(imageUrl: t.artworkUrl!, width: 36, height: 36, fit: BoxFit.cover)
                  : Container(width: 36, height: 36, color: AppTheme.panelRaised,
                      child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (t.durationMs > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${t.durationMs ~/ 60000}:${((t.durationMs % 60000) ~/ 1000).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
              ),
            if (t.spotifyUrl != null)
              _PlayBtn(icon: Icons.graphic_eq_rounded, color: const Color(0xFF1ED760), url: t.spotifyUrl!, tip: 'Spotify'),
            if (t.appleUrl != null)
              _PlayBtn(icon: Icons.music_note_rounded, color: const Color(0xFFFF7AB5), url: t.appleUrl!, tip: 'Apple Music'),
          ],
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.icon, required this.color, required this.url, required this.tip});
  final IconData icon;
  final Color color;
  final String url;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Play on $tip',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final uri = Uri.tryParse(url);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}
