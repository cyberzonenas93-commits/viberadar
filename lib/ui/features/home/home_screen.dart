import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final risingTop = rising.take(8).toList();

    // Regional hot — boost genre relevance for African markets
    final region = userProfile.preferredRegion;
    final regional = [...allTracks]..sort((a, b) {
      final scoreA = _regionalRelevance(a, region);
      final scoreB = _regionalRelevance(b, region);
      return scoreB.compareTo(scoreA);
    });
    final regionalTop = regional.take(12).toList();

    return CustomScrollView(
      slivers: [
        // ── Header ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.violet, AppTheme.pink],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text('DJ Intelligence Cockpit',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: AppTheme.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${allTracks.length} tracks monitored  ·  ${rising.length} rising fast  ·  ${_uniqueArtists(allTracks)} artists',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                // Live indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.lime.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.lime.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: AppTheme.lime,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppTheme.lime.withValues(alpha: 0.5), blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('Live', style: TextStyle(color: AppTheme.lime, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Hero #1 + Stats ─────────────────────────────────────────────
        if (top.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero card
                  Expanded(
                    flex: 5,
                    child: _HeroTrackCard(track: top[0], ref: ref),
                  ),
                  const SizedBox(width: 14),
                  // 3 stat cards stacked
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _StatCard(
                          icon: Icons.location_on_rounded,
                          accent: AppTheme.cyan,
                          label: 'Hot in ${formatRegionLabel(region)}',
                          value: regionalTop.isNotEmpty ? '${(_regionalRelevance(regionalTop[0], region) * 100).round()}' : '--',
                          subtitle: regionalTop.isNotEmpty ? '${regionalTop[0].title} · ${regionalTop[0].artist}' : 'No data',
                        ),
                        const SizedBox(height: 10),
                        _StatCard(
                          icon: Icons.trending_up_rounded,
                          accent: AppTheme.pink,
                          label: 'Fastest Rising',
                          value: risingTop.isNotEmpty ? '+${((risingTop[0].trendHistory.last.score - risingTop[0].trendHistory.first.score) * 100).round()}' : '--',
                          subtitle: risingTop.isNotEmpty ? '${risingTop[0].title} · ${risingTop[0].artist}' : 'Waiting for data',
                        ),
                        const SizedBox(height: 10),
                        _StatCard(
                          icon: Icons.library_music_rounded,
                          accent: AppTheme.violet,
                          label: 'Top Genre',
                          value: _topGenre(allTracks),
                          subtitle: '${_genreCount(allTracks, _topGenre(allTracks))} tracks in radar',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),

        // ── Section: Hot Right Now ──────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded, color: AppTheme.amber, size: 18),
                const SizedBox(width: 8),
                Text('Hot Right Now',
                    style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('Top 24', style: TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),

        // Grid of top 12 (skip #1 which is the hero)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.74,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final trackIndex = i + 1; // skip hero
                if (trackIndex >= top.length) return null;
                return _TrackGridCard(track: top[trackIndex], rank: trackIndex + 1, ref: ref);
              },
              childCount: (top.length - 1).clamp(0, 24),
            ),
          ),
        ),

        // ── Section: Rising Fast ────────────────────────────────────────
        if (risingTop.length > 1) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
              child: Row(
                children: [
                  const Icon(Icons.rocket_launch_rounded, color: AppTheme.pink, size: 18),
                  const SizedBox(width: 8),
                  Text('Rising Fast',
                      style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.pink.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('${risingTop.length} tracks', style: TextStyle(color: AppTheme.pink, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
                itemCount: risingTop.length,
                separatorBuilder: (_, i) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _RisingCard(track: risingTop[i], ref: ref),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],

        // ── Section: Regional Pulse ─────────────────────────────────────
        if (regionalTop.length > 1) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
              child: Row(
                children: [
                  const Icon(Icons.public_rounded, color: AppTheme.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text('Hot in ${formatRegionLabel(region)}',
                      style: theme.textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.74,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _TrackGridCard(track: regionalTop[i], rank: i + 1, ref: ref),
                childCount: regionalTop.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  int _uniqueArtists(List<Track> tracks) => {for (final t in tracks) t.artist}.length;

  String _topGenre(List<Track> tracks) {
    final counts = <String, int>{};
    for (final t in tracks) {
      if (t.genre.isNotEmpty) counts[t.genre] = (counts[t.genre] ?? 0) + 1;
    }
    if (counts.isEmpty) return '--';
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  int _genreCount(List<Track> tracks, String genre) => tracks.where((t) => t.genre == genre).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card — the #1 trending track
// ─────────────────────────────────────────────────────────────────────────────

class _HeroTrackCard extends StatefulWidget {
  final Track track;
  final WidgetRef ref;
  const _HeroTrackCard({required this.track, required this.ref});

  @override
  State<_HeroTrackCard> createState() => _HeroTrackCardState();
}

class _HeroTrackCardState extends State<_HeroTrackCard> {
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
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.violet.withValues(alpha: _hovered ? 0.16 : 0.1),
                AppTheme.panel,
                AppTheme.panel,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background artwork
              if (t.artworkUrl.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.55),
                        colorBlendMode: BlendMode.darken,
                        errorWidget: (_, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
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
                              width: 170,
                              height: 170,
                              fit: BoxFit.cover,
                              errorWidget: (_, e, s) => _ArtPlaceholder(size: 170),
                            )
                          : _ArtPlaceholder(size: 170),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.pink]),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.whatshot_rounded, color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('#1 TRENDING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 0.5)),
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
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            t.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1.2),
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
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _MetaPill(icon: Icons.speed_rounded, text: '${t.bpm}'),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.music_note_rounded, text: t.keySignature),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.public_rounded, text: t.leadRegion),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w800, fontSize: 22)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Play button
              if (_bestUrl(t) != null)
                Positioned(
                  left: 24 + 170 - 20,
                  bottom: 24,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.cyan,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.4), blurRadius: 12)],
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
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
// Stat card (replaces old DashboardCards)
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String subtitle;

  const _StatCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.08), AppTheme.panel],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 18)),
                Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid card (same style as Greatest Of)
// ─────────────────────────────────────────────────────────────────────────────

class _TrackGridCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  const _TrackGridCard({required this.track, required this.rank, required this.ref});

  @override
  State<_TrackGridCard> createState() => _TrackGridCardState();
}

class _TrackGridCardState extends State<_TrackGridCard> {
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
                                errorWidget: (_, e, s) => _ArtPlaceholder(size: double.infinity, rounded: false),
                              )
                            : _ArtPlaceholder(size: double.infinity, rounded: false),
                      ),
                    ),
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('#${widget.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
                      ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
                      ),
                    ),
                    if (_hovered && _bestUrl(t) != null)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
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
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
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
// Rising fast — horizontal scroll card
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.pink.withValues(alpha: _hovered ? 0.4 : 0.2)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.pink.withValues(alpha: _hovered ? 0.08 : 0.04), AppTheme.panel],
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: t.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(imageUrl: t.artworkUrl, width: 120, height: 150, fit: BoxFit.cover, errorWidget: (_, e, s) => _ArtPlaceholder(size: 120))
                    : _ArtPlaceholder(size: 120),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.pink.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.trending_up_rounded, color: AppTheme.pink, size: 10),
                          SizedBox(width: 3),
                          Text('RISING', style: TextStyle(color: AppTheme.pink, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('${t.bpm}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 6),
                        Text(t.keySignature, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${(t.trendScore * 100).toInt()} score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 13)),
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
// Shared
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.edge, AppTheme.panelRaised],
        ),
        borderRadius: rounded ? BorderRadius.circular(size * 0.16) : null,
      ),
      child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: size * 0.35),
    );
  }
}

/// Smarter regional relevance: combines the raw region score with genre
/// affinity for that market. E.g. Afrobeats/Highlife boosts GH/NG,
/// Amapiano/Gqom boosts ZA, Drill/UK Garage boosts GB.
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
    if (genre.contains('afrobeats')) genreBoost = 0.2;
  } else if (r == 'GB') {
    if (genre.contains('drill') || genre.contains('garage')) genreBoost = 0.35;
    if (genre.contains('house') || genre.contains('dance')) genreBoost = 0.2;
    if (genre.contains('afrobeats')) genreBoost = 0.15;
  } else if (r == 'US') {
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.3;
    if (genre.contains('latin')) genreBoost = 0.2;
    if (genre.contains('house') || genre.contains('dance')) genreBoost = 0.15;
  }

  return (rawScore + genreBoost + track.trendScore * 0.3).clamp(0.0, 1.0);
}

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}

Future<void> _openTrack(Track track) async {
  final url = _bestUrl(track);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}
