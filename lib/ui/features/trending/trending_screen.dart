import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/config/music_genres.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../widgets/source_badges.dart';
import '../../widgets/track_action_menu.dart';
import '../../widgets/ui_kit.dart';

class TrendingScreen extends ConsumerStatefulWidget {
  const TrendingScreen({super.key});
  @override
  ConsumerState<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends ConsumerState<TrendingScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveAccess = ref.watch(liveCatalogAccessProvider);
    final selectedRegion = ref.watch(selectedRegionProvider) ?? 'Global';
    final selectedRegionLabel = selectedRegion == 'Global'
        ? 'All'
        : selectedRegion;
    final selectedGenre = ref.watch(selectedGenreProvider);
    final selectedGenreLabel = selectedGenre ?? 'All';
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];
    final loadingTracks = tracksAsync.isLoading && allTracks.isEmpty;

    final genres = ref.watch(availableGenresProvider);
    final regions = <String>[
      'All',
      ...ref.watch(availableRegionsProvider).where((r) => r != 'Global'),
    ];

    var filtered = allTracks.toList();
    if (!liveAccess.hasLiveAccess && selectedGenre != null) {
      filtered = filtered
          .where((t) => genreMatches(t.genre, selectedGenre))
          .toList();
    }
    if (!liveAccess.hasLiveAccess && selectedRegionLabel != 'All') {
      // Keep tracks that have ANY score in the selected region, sort by regional score
      filtered = filtered
          .where((t) => (t.regionScores[selectedRegionLabel] ?? 0) > 0)
          .toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      filtered = filtered
          .where(
            (t) =>
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q),
          )
          .toList();
    }
    // Sort by regional score when a region is selected, otherwise by global trendScore
    if (selectedRegionLabel != 'All') {
      filtered.sort(
        (a, b) => (b.regionScores[selectedRegionLabel] ?? 0).compareTo(
          a.regionScores[selectedRegionLabel] ?? 0,
        ),
      );
    } else {
      filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));
    }

    final compact = MediaQuery.sizeOf(context).width < 700;
    final horizontalPadding = compact ? 16.0 : 28.0;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 16 : 24,
                horizontalPadding,
                0,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chipWidth = compact
                      ? (constraints.maxWidth - 8) / 2
                      : 152.0;
                  final titleCluster = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: AppTheme.amber,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Trending',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TrackCountText(
                        isLoading: loadingTracks,
                        count: filtered.length,
                        labelBuilder: (count) =>
                            '$count tracks sorted by momentum score',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  );

                  final filterCluster = Wrap(
                    alignment: compact
                        ? WrapAlignment.start
                        : WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: chipWidth,
                        child: _FilterChip(
                          label: 'Genre',
                          value: selectedGenreLabel,
                          options: genres,
                          onChanged: (v) {
                            // Drive genre-aware live retrieval, not just a
                            // post-fetch filter over a genre-blind feed.
                            ref
                                .read(selectedGenreProvider.notifier)
                                .set(v == 'All' ? null : v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: chipWidth,
                        child: _FilterChip(
                          label: 'Region',
                          value: selectedRegionLabel,
                          options: regions,
                          onChanged: (v) {
                            ref
                                .read(selectedRegionProvider.notifier)
                                .set(v == 'All' ? 'Global' : v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: compact ? constraints.maxWidth : 160,
                        child: _TrendingSearchField(
                          onChanged: (v) => setState(() => _search = v),
                        ),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleCluster,
                        const SizedBox(height: 12),
                        filterCluster,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: titleCluster),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: filterCluster),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Grid
            Expanded(
              child: loadingTracks
                  ? const Center(child: RadarLoader(message: 'Loading tracks…'))
                  : filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No tracks match your filters',
                        style: TextStyle(color: AppTheme.textTertiary),
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        28,
                      ),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: compact ? 180 : 200,
                        childAspectRatio: compact ? 0.68 : 0.72,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) =>
                          _TrackCard(track: filtered[i], rank: i + 1, ref: ref),
                    ),
            ),
          ],
        ),
        // Floating "Add All to Setlist" button
        if (filtered.isNotEmpty)
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton.extended(
              heroTag: 'trending_crate',
              onPressed: () => showBulkAddToCrate(context, ref, filtered),
              backgroundColor: AppTheme.cyan,
              foregroundColor: AppTheme.ink,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: Text(
                compact
                    ? 'Add ${filtered.length}'
                    : 'Add ${filtered.length} to Setlist',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrendingSearchField extends StatelessWidget {
  const _TrendingSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        hintText: 'Search...',
        hintStyle: const TextStyle(color: AppTheme.textTertiary),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 16,
          color: AppTheme.textTertiary,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        filled: true,
        fillColor: AppTheme.panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          borderSide: const BorderSide(color: AppTheme.hairline),
        ),
      ),
    );
  }
}

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  const _TrackCard({
    required this.track,
    required this.rank,
    required this.ref,
  });

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  // On touch platforms hover never fires, so the play affordance would be
  // invisible/unreachable. Always reveal it there; keep hover-gating on desktop.
  bool get _isTouch =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    final isTop3 = widget.rank <= 3;
    final rankColor = widget.rank == 1
        ? AppTheme.amber
        : widget.rank == 2
        ? const Color(0xFFC0C0C0)
        : widget.rank == 3
        ? const Color(0xFFCD7F32)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(
          context,
          widget.ref,
          t,
          position: details.globalPosition,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: AppTheme.glass(
            radius: 14,
            border: isTop3
                ? rankColor!.withValues(alpha: _hovered ? 0.55 : 0.34)
                : (_hovered
                      ? AppTheme.cyan.withValues(alpha: 0.32)
                      : AppTheme.hairline),
            glowShadow: _hovered
                ? AppTheme.glow(
                    isTop3 ? rankColor! : AppTheme.cyan,
                    blur: 20,
                    opacity: 0.10,
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _ArtPlaceholder(),
                              )
                            : _ArtPlaceholder(),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isTop3
                              ? rankColor!.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.rank}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isTop3
                                ? FontWeight.w800
                                : FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Score
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$score',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Play affordance (hover on desktop, always on touch)
                    if (_hovered || _isTouch)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(13),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.cyan.withValues(alpha: 0.5),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          formatBpm(t.bpm),
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.edge.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            t.keySignature,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SourceBadges(
                          sources: t.effectiveSources,
                          compact: true,
                        ),
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

class _ArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.edge, AppTheme.panelRaised],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppTheme.textTertiary,
          size: 32,
        ),
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
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppTheme.hairline),
      ),
      child: Row(
        children: [
          Text(
            '$label:',
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: options.contains(value) ? value : options.first,
                isDense: true,
                isExpanded: true,
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                ),
                selectedItemBuilder: (context) => options
                    .map(
                      (o) =>
                          Text(o, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )
                    .toList(),
                items: options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o,
                        child: Text(
                          o,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
