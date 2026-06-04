import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/track.dart';
import '../../../models/user_profile.dart';
import '../../../providers/app_state.dart';
import '../../../providers/repositories.dart';
import '../../widgets/source_badges.dart';
import '../../widgets/track_action_menu.dart';

part 'home_screen_widgets.dart';
part 'home_screen_cards.dart';
part 'home_screen_helpers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.allTracks,
    required this.userProfile,
  });

  final List<Track> allTracks;
  final UserProfile userProfile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedGenre = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allTracks = widget.allTracks;
    // Prefer the reactive local selection (works for guests too); fall back to
    // the signed-in profile's region when nothing has been picked this session.
    final region =
        ref.watch(selectedRegionProvider) ?? widget.userProfile.preferredRegion;
    final genreFiltered = _selectedGenre == 'All'
        ? allTracks
        : allTracks.where((t) => t.genre == _selectedGenre).toList();
    // Sort by regional score when a specific region is set, otherwise global trendScore
    final sorted = [...genreFiltered];
    if (region.isNotEmpty && region != 'Global') {
      sorted.sort(
        (a, b) => (b.regionScores[region] ?? 0).compareTo(
          a.regionScores[region] ?? 0,
        ),
      );
    } else {
      sorted.sort((a, b) => b.trendScore.compareTo(a.trendScore));
    }
    final top = sorted.take(80).toList();
    final rising = allTracks.where((t) => t.isRisingFast).toList()
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final risingTop = rising.take(15).toList();

    final regional = [...allTracks]
      ..sort((a, b) {
        return _regionalRelevance(
          b,
          region,
        ).compareTo(_regionalRelevance(a, region));
      });
    // Keep all tracks with any regional relevance, minimum 100
    final relevanceFiltered = regional
        .where((t) => _regionalRelevance(t, region) > 0.05)
        .toList();
    final regionalTop = (relevanceFiltered.length >= 100
        ? relevanceFiltered
        : regional.take(100).toList());

    // Genre breakdown
    final genreCounts = <String, int>{};
    for (final t in allTracks) {
      if (t.genre.isNotEmpty) {
        genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      }
    }
    final topGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 700;
    final edge = compact ? 16.0 : 28.0;
    final welcomePadding = compact ? 18.0 : 24.0;
    final gridMaxExtent = compact ? 176.0 : 200.0;

    return CustomScrollView(
      slivers: [
        // ── Welcome Banner ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            margin: EdgeInsets.fromLTRB(edge, compact ? 14 : 20, edge, 0),
            padding: EdgeInsets.all(welcomePadding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.violet.withValues(alpha: 0.15),
                  AppTheme.pink.withValues(alpha: 0.08),
                  AppTheme.panel,
                ],
              ),
              border: Border.all(color: AppTheme.violet.withValues(alpha: 0.2)),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeCopy(
                        theme: theme,
                        allTracks: allTracks,
                        risingCount: rising.length,
                        topGenres: topGenres,
                      ),
                      const SizedBox(height: 16),
                      _buildStatusControls(region, compact: true),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildWelcomeCopy(
                          theme: theme,
                          allTracks: allTracks,
                          risingCount: rising.length,
                          topGenres: topGenres,
                        ),
                      ),
                      const SizedBox(width: 20),
                      _buildStatusControls(region, compact: false),
                    ],
                  ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── #1 Trending Hero ──────────────────────────────────────────────
        if (top.length >= 3)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: edge),
              child: _SectionHeader(
                icon: Icons.whatshot_rounded,
                label: 'Top Trending',
                color: AppTheme.amber,
              ),
            ),
          ),
        if (top.length >= 3)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(edge, 12, edge, 0),
              child: compact
                  ? Column(
                      children: [
                        _HeroCard(track: top[0], ref: ref),
                        const SizedBox(height: 12),
                        _RunnerCard(
                          track: top[1],
                          rank: 2,
                          ref: ref,
                          accent: const Color(0xFFC0C0C0),
                        ),
                        const SizedBox(height: 12),
                        _RunnerCard(
                          track: top[2],
                          rank: 3,
                          ref: ref,
                          accent: const Color(0xFFCD7F32),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _HeroCard(track: top[0], ref: ref),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _RunnerCard(
                                track: top[1],
                                rank: 2,
                                ref: ref,
                                accent: const Color(0xFFC0C0C0),
                              ),
                              const SizedBox(height: 12),
                              _RunnerCard(
                                track: top[2],
                                rank: 3,
                                ref: ref,
                                accent: const Color(0xFFCD7F32),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 28)),

        // ── Genre Quick Filters ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: edge),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: topGenres.take(8).length + 1, // +1 for "All"
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  // First item is "All" to clear the filter
                  if (i == 0) {
                    final isAll = _selectedGenre == 'All';
                    return GestureDetector(
                      onTap: () => setState(() => _selectedGenre = 'All'),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: isAll
                                ? AppTheme.violet.withValues(alpha: 0.2)
                                : AppTheme.panelRaised,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isAll
                                  ? AppTheme.violet.withValues(alpha: 0.5)
                                  : AppTheme.edge.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'All',
                            style: TextStyle(
                              color: isAll
                                  ? AppTheme.violet
                                  : AppTheme.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final genre = topGenres[i - 1];
                  final isSelected = _selectedGenre == genre.key;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedGenre = genre.key),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.violet.withValues(alpha: 0.2)
                              : AppTheme.panelRaised,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.violet.withValues(alpha: 0.5)
                                : AppTheme.edge.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              genre.key,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.violet
                                    : AppTheme.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.violet.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${genre.value}',
                                style: const TextStyle(
                                  color: AppTheme.violet,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── Hot Right Now Grid ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(edge, 0, edge, 12),
            child: _SectionHeader(
              icon: Icons.local_fire_department_rounded,
              label: 'Hot Right Now',
              color: AppTheme.amber,
              count: '${(top.length - 3).clamp(0, 48)}',
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(edge, 0, edge, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: gridMaxExtent,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final idx = i + 3;
              if (idx >= top.length) return null;
              return _TrackCard(track: top[idx], rank: idx + 1, ref: ref);
            }, childCount: (top.length - 3).clamp(0, 48)),
          ),
        ),

        // ── Rising Fast ──────────────────────────────────────────────────
        if (risingTop.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(edge, 0, edge, 12),
              child: _SectionHeader(
                icon: Icons.rocket_launch_rounded,
                label: 'Rising Fast',
                color: AppTheme.pink,
                count: '${risingTop.length}',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(edge, 0, edge, 0),
                itemCount: risingTop.length,
                separatorBuilder: (_, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) =>
                    _RisingCard(track: risingTop[i], ref: ref),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],

        // ── Hot in Region ────────────────────────────────────────────────
        if (regionalTop.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(edge, 0, edge, 12),
              child: _SectionHeader(
                icon: Icons.public_rounded,
                label: 'Hot in ${formatRegionLabel(region)}',
                color: AppTheme.cyan,
                count: '${regionalTop.length}',
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(edge, 0, edge, 32),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: gridMaxExtent,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) =>
                    _TrackCard(track: regionalTop[i], rank: i + 1, ref: ref),
                childCount: regionalTop.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWelcomeCopy({
    required ThemeData theme,
    required List<Track> allTracks,
    required int risingCount,
    required List<MapEntry<String, int>> topGenres,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to VibeRadar',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your DJ intelligence dashboard. ${allTracks.length} tracks from 8 sources across 6 regions.',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatPill(
              icon: Icons.music_note_rounded,
              label: '${allTracks.length}',
              sublabel: 'tracks',
              color: AppTheme.cyan,
            ),
            _StatPill(
              icon: Icons.trending_up_rounded,
              label: '$risingCount',
              sublabel: 'rising',
              color: AppTheme.pink,
            ),
            _StatPill(
              icon: Icons.people_rounded,
              label: '${_uniqueArtists(allTracks)}',
              sublabel: 'artists',
              color: AppTheme.violet,
            ),
            if (topGenres.isNotEmpty)
              _StatPill(
                icon: Icons.album_rounded,
                label: topGenres.first.key,
                sublabel: '${topGenres.first.value}',
                color: AppTheme.amber,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusControls(String region, {required bool compact}) {
    final liveBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.lime.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lime.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.lime,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.lime.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Live',
            style: TextStyle(
              color: AppTheme.lime,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    if (compact) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          liveBadge,
          _RegionPickerBadge(currentRegion: region),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        liveBadge,
        const SizedBox(height: 10),
        _RegionPickerBadge(currentRegion: region),
      ],
    );
  }

  int _uniqueArtists(List<Track> tracks) =>
      {for (final t in tracks) t.artist}.length;
}
