import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/track.dart';
import '../../../models/user_profile.dart';
import '../../widgets/track_action_menu.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.allTracks,
    required this.userProfile,
  });

  final List<Track> allTracks;
  final UserProfile userProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sorted = [...allTracks]..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final top = sorted.take(50).toList();
    final rising = allTracks.where((t) => t.isRisingFast).toList()
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final risingTop = rising.take(10).toList();

    final region = userProfile.preferredRegion;
    final regional = [...allTracks]..sort((a, b) {
      return _regionalRelevance(b, region).compareTo(_regionalRelevance(a, region));
    });
    final regionalTop = regional.where((t) => _regionalRelevance(t, region) > 0.3).take(12).toList();

    // Genre breakdown
    final genreCounts = <String, int>{};
    for (final t in allTracks) {
      if (t.genre.isNotEmpty) genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
    }
    final topGenres = genreCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return CustomScrollView(
      slivers: [
        // ── Welcome Banner ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(28, 20, 28, 0),
            padding: const EdgeInsets.all(24),
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
            child: Row(
              children: [
                // Left: greeting + stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome to Vibe Radar',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 8),
                      Text(
                        'Your DJ intelligence dashboard. ${allTracks.length} tracks from 8 sources across 6 regions.',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      // Stat pills row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatPill(icon: Icons.music_note_rounded, label: '${allTracks.length}', sublabel: 'tracks', color: AppTheme.cyan),
                          _StatPill(icon: Icons.trending_up_rounded, label: '${rising.length}', sublabel: 'rising', color: AppTheme.pink),
                          _StatPill(icon: Icons.people_rounded, label: '${_uniqueArtists(allTracks)}', sublabel: 'artists', color: AppTheme.violet),
                          if (topGenres.isNotEmpty)
                            _StatPill(icon: Icons.album_rounded, label: topGenres.first.key, sublabel: '${topGenres.first.value}', color: AppTheme.amber),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Right: live indicator + region badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
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
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: AppTheme.lime, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppTheme.lime.withValues(alpha: 0.5), blurRadius: 6)],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Live', style: TextStyle(color: AppTheme.lime, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.cyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('Region: ${formatRegionLabel(region)}',
                          style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── #1 Trending Hero ──────────────────────────────────────────────
        if (top.length >= 3)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _SectionHeader(icon: Icons.whatshot_rounded, label: 'Top Trending', color: AppTheme.amber),
            ),
          ),
        if (top.length >= 3)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero #1
                  Expanded(flex: 5, child: _HeroCard(track: top[0], ref: ref)),
                  const SizedBox(width: 12),
                  // #2 and #3
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _RunnerCard(track: top[1], rank: 2, ref: ref, accent: const Color(0xFFC0C0C0)),
                        const SizedBox(height: 12),
                        _RunnerCard(track: top[2], rank: 3, ref: ref, accent: const Color(0xFFCD7F32)),
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
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: topGenres.take(8).length,
                separatorBuilder: (_, i) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final genre = topGenres[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(genre.key, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${genre.value}', style: const TextStyle(color: AppTheme.violet, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ],
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
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: _SectionHeader(icon: Icons.local_fire_department_rounded, label: 'Hot Right Now', color: AppTheme.amber, count: '${(top.length - 3).clamp(0, 24)}'),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final idx = i + 3;
                if (idx >= top.length) return null;
                return _TrackCard(track: top[idx], rank: idx + 1, ref: ref);
              },
              childCount: (top.length - 3).clamp(0, 24),
            ),
          ),
        ),

        // ── Rising Fast ──────────────────────────────────────────────────
        if (risingTop.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
              child: _SectionHeader(icon: Icons.rocket_launch_rounded, label: 'Rising Fast', color: AppTheme.pink, count: '${risingTop.length}'),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
                itemCount: risingTop.length,
                separatorBuilder: (_, i) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) => _RisingCard(track: risingTop[i], ref: ref),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],

        // ── Hot in Region ────────────────────────────────────────────────
        if (regionalTop.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
              child: _SectionHeader(icon: Icons.public_rounded, label: 'Hot in ${formatRegionLabel(region)}', color: AppTheme.cyan, count: '${regionalTop.length}'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TrackCard(track: regionalTop[i], rank: i + 1, ref: ref),
                childCount: regionalTop.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  int _uniqueArtists(List<Track> tracks) => {for (final t in tracks) t.artist}.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header with icon, label, count
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? count;
  const _SectionHeader({required this.icon, required this.label, required this.color, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
            child: Text(count!, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat pills for the welcome banner
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  const _StatPill({required this.icon, required this.label, required this.sublabel, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(sublabel, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero #1 card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatefulWidget {
  final Track track;
  final WidgetRef ref;
  const _HeroCard({required this.track, required this.ref});
  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(context, widget.ref, t, position: d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.amber.withValues(alpha: _hovered ? 0.15 : 0.08), AppTheme.panel, AppTheme.panel],
            ),
          ),
          child: Stack(
            children: [
              if (t.artworkUrl.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ShaderMask(
                      shaderCallback: (b) => LinearGradient(
                        begin: Alignment.centerRight, end: Alignment.centerLeft,
                        colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
                      ).createShader(b),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover, color: Colors.black.withValues(alpha: 0.5), colorBlendMode: BlendMode.darken, errorWidget: (_, e, s) => const SizedBox.shrink()),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: t.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(imageUrl: t.artworkUrl, width: 170, height: 170, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholder(170))
                          : _ArtPlaceholder(170),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.amber, Color(0xFFFF8C00)]), borderRadius: BorderRadius.circular(6)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.emoji_events_rounded, color: Colors.white, size: 12),
                                  SizedBox(width: 4),
                                  Text('#1 TRENDING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 0.5)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(t.genre, style: const TextStyle(color: AppTheme.violet, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(t.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(t.artist, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Pill('${t.bpm} BPM'), const SizedBox(width: 6),
                              _Pill(t.keySignature), const SizedBox(width: 6),
                              _Pill(t.leadRegion),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w800, fontSize: 20)),
                              ),
                            ],
                          ),
                        ],
                      ),
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
// Runner-up card (#2, #3)
// ─────────────────────────────────────────────────────────────────────────────

class _RunnerCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  final Color accent;
  const _RunnerCard({required this.track, required this.rank, required this.ref, required this.accent});
  @override
  State<_RunnerCard> createState() => _RunnerCardState();
}

class _RunnerCardState extends State<_RunnerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(context, widget.ref, t, position: d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 114,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [widget.accent.withValues(alpha: _hovered ? 0.1 : 0.05), AppTheme.panel]),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: t.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(imageUrl: t.artworkUrl, width: 86, height: 86, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholder(86))
                    : _ArtPlaceholder(86),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: widget.accent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(5)),
                          child: Text('#${widget.rank}', style: TextStyle(color: widget.accent, fontWeight: FontWeight.w800, fontSize: 10)),
                        ),
                        const Spacer(),
                        Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
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
// Standard track grid card
// ─────────────────────────────────────────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  const _TrackCard({required this.track, required this.rank, required this.ref});
  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(context, widget.ref, t, position: d.globalPosition),
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
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholderFull())
                            : _ArtPlaceholderFull(),
                      ),
                    ),
                    Positioned(top: 8, left: 8, child: _Badge('#${widget.rank}', Colors.black.withValues(alpha: 0.6))),
                    Positioned(top: 8, right: 8, child: _Badge('$score', AppTheme.cyan.withValues(alpha: 0.9))),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: const BorderRadius.vertical(top: Radius.circular(13))),
                          child: Center(child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: AppTheme.cyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)]),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          )),
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
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text('${t.bpm}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                          child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 9)),
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
// Rising fast horizontal card
// ─────────────────────────────────────────────────────────────────────────────

class _RisingCard extends StatefulWidget {
  final Track track;
  final WidgetRef ref;
  const _RisingCard({required this.track, required this.ref});
  @override
  State<_RisingCard> createState() => _RisingCardState();
}

class _RisingCardState extends State<_RisingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(context, widget.ref, t, position: d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 170,
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.pink.withValues(alpha: _hovered ? 0.4 : 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork top
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholderFull())
                            : _ArtPlaceholderFull(),
                      ),
                    ),
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.pink.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(5)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.trending_up_rounded, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text('RISING', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                    Positioned(top: 8, right: 8, child: _Badge('$score', AppTheme.cyan.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
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

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  final double size;
  const _ArtPlaceholder(this.size);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised]), borderRadius: BorderRadius.circular(size * 0.08)),
      child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: size * 0.3),
    );
  }
}

class _ArtPlaceholderFull extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised])),
      child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
    );
  }
}

double _regionalRelevance(Track track, String region) {
  final rawScore = track.regionScores[region.toUpperCase()] ?? 0.0;
  final genre = track.genre.toLowerCase();
  double genreBoost = 0.0;
  final r = region.toUpperCase();
  if (r == 'GH' || r == 'NG') {
    if (genre.contains('afrobeats') || genre.contains('afro')) genreBoost = 0.4;
    if (genre.contains('dancehall')) genreBoost = 0.25;
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.15;
  } else if (r == 'ZA') {
    if (genre.contains('amapiano')) genreBoost = 0.45;
    if (genre.contains('gqom') || genre.contains('house')) genreBoost = 0.3;
  } else if (r == 'GB') {
    if (genre.contains('drill') || genre.contains('garage')) genreBoost = 0.35;
    if (genre.contains('house') || genre.contains('dance')) genreBoost = 0.2;
  } else if (r == 'US') {
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.3;
    if (genre.contains('latin')) genreBoost = 0.2;
  }
  return (rawScore + genreBoost + track.trendScore * 0.3).clamp(0.0, 1.0);
}
