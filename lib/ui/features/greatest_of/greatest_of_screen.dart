import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';

class GreatestOfScreen extends ConsumerStatefulWidget {
  const GreatestOfScreen({super.key});
  @override
  ConsumerState<GreatestOfScreen> createState() => _GreatestOfScreenState();
}

class _GreatestOfScreenState extends ConsumerState<GreatestOfScreen> {
  String _selectedGenre = 'All';
  String _selectedRegion = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    final genres = ['All', ...{for (final t in allTracks) if (t.genre.isNotEmpty) t.genre}];
    final regions = ['All', ...{for (final t in allTracks) if (t.leadRegion.isNotEmpty) t.leadRegion}];

    var filtered = allTracks.toList();
    if (_selectedGenre != 'All') {
      filtered = filtered.where((t) => t.genre == _selectedGenre).toList();
    }
    if (_selectedRegion != 'All') {
      filtered = filtered.where((t) => t.leadRegion == _selectedRegion).toList();
    }
    filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final topTracks = filtered.take(60).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + filters
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded, color: AppTheme.amber, size: 24),
                      const SizedBox(width: 10),
                      Text('Greatest Of',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The highest-scoring tracks in your radar, ranked by trend momentum.',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              _FilterChip(
                label: 'Genre',
                value: _selectedGenre,
                options: genres,
                onChanged: (v) => setState(() => _selectedGenre = v),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Region',
                value: _selectedRegion,
                options: regions,
                onChanged: (v) => setState(() => _selectedRegion = v),
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
              : CustomScrollView(
                  slivers: [
                    // Top 3 podium
                    if (topTracks.length >= 3)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                          child: _PodiumSection(tracks: topTracks.take(3).toList()),
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
                            );
                          },
                          childCount: topTracks.length >= 3
                              ? topTracks.length - 3
                              : topTracks.length,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top 3 Podium — hero layout with large artwork
// ─────────────────────────────────────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<Track> tracks;
  const _PodiumSection({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // #1 — Hero card (large)
        Expanded(
          flex: 5,
          child: _HeroCard(track: tracks[0], rank: 1),
        ),
        const SizedBox(width: 12),
        // #2 and #3 stacked
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _RunnerUpCard(track: tracks[1], rank: 2),
              const SizedBox(height: 12),
              _RunnerUpCard(track: tracks[2], rank: 3),
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
  const _HeroCard({required this.track, required this.rank});

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
        onTap: () => _openTrack(t),
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
                              // Score
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$score',
                                  style: const TextStyle(
                                    color: AppTheme.cyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 22,
                                  ),
                                ),
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
                    onTap: () => _openTrack(t),
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
  const _RunnerUpCard({required this.track, required this.rank});

  @override
  State<_RunnerUpCard> createState() => _RunnerUpCardState();
}

class _RunnerUpCardState extends State<_RunnerUpCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final rank = widget.rank;
    final score = (t.trendScore * 100).toInt();
    final accent = rank == 2 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _openTrack(t),
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
                        Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 16)),
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
  const _TrackCard({required this.track, required this.rank});

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
        onTap: () => _openTrack(t),
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
                                errorWidget: (_, e, s) => _ArtPlaceholder(size: double.infinity, rounded: false),
                              )
                            : _ArtPlaceholder(size: double.infinity, rounded: false),
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$score',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10),
                        ),
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

Future<void> _openTrack(Track track) async {
  final url = _bestUrl(track);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
