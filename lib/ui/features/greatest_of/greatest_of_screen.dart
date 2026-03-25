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

    // Get unique genres and regions
    final genres = ['All', ...{for (final t in allTracks) if (t.genre.isNotEmpty) t.genre}];
    final regions = ['All', ...{for (final t in allTracks) if (t.leadRegion.isNotEmpty) t.leadRegion}];

    // Filter
    var filtered = allTracks.toList();
    if (_selectedGenre != 'All') {
      filtered = filtered.where((t) => t.genre == _selectedGenre).toList();
    }
    if (_selectedRegion != 'All') {
      filtered = filtered.where((t) => t.leadRegion == _selectedRegion).toList();
    }

    // Sort by trend score descending — "greatest" = highest scoring
    filtered.sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final topTracks = filtered.take(50).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Greatest Of',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Top-scoring tracks across your library — filter by genre or region.',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _FilterChip(
                    label: 'Genre',
                    value: _selectedGenre,
                    options: genres,
                    onChanged: (v) => setState(() => _selectedGenre = v),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    label: 'Region',
                    value: _selectedRegion,
                    options: regions,
                    onChanged: (v) => setState(() => _selectedRegion = v),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${topTracks.length} tracks',
                      style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: topTracks.isEmpty
              ? const Center(
                  child: Text('No tracks match your filters',
                      style: TextStyle(color: AppTheme.textTertiary)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  itemCount: topTracks.length,
                  itemBuilder: (context, i) {
                    final track = topTracks[i];
                    final rank = i + 1;
                    return _TrackRow(track: track, rank: rank);
                  },
                ),
        ),
      ],
    );
  }
}

class _TrackRow extends StatefulWidget {
  final Track track;
  final int rank;
  const _TrackRow({required this.track, required this.rank});

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final rank = widget.rank;
    final isTop3 = rank <= 3;
    final rankColor = rank == 1
        ? AppTheme.amber
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : AppTheme.textTertiary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isTop3
                ? rankColor.withValues(alpha: 0.3)
                : AppTheme.edge.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 32,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: rankColor,
                  fontWeight: isTop3 ? FontWeight.w800 : FontWeight.w600,
                  fontSize: isTop3 ? 16 : 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: t.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: t.artworkUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, e, s) => _ArtPlaceholder(),
                    )
                  : _ArtPlaceholder(),
            ),
            const SizedBox(width: 14),
            // Title + Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
                ],
              ),
            ),
            // Genre
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.violet.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.genre,
                style: const TextStyle(color: AppTheme.violet, fontSize: 10, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 12),
            // BPM + Key
            SizedBox(
              width: 60,
              child: Text(
                '${t.bpm} BPM',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.edge.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.keySignature,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Region
            Text(t.leadRegion,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            const SizedBox(width: 12),
            // Score
            Text(
              '${(t.trendScore * 100).toInt()}',
              style: const TextStyle(
                color: AppTheme.cyan,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            // Play button
            if (_bestUrl(t) != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton(
                  icon: const Icon(Icons.play_circle_filled_rounded,
                      color: AppTheme.cyan, size: 24),
                  onPressed: () async {
                    final uri = Uri.tryParse(_bestUrl(t)!);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Play',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _bestUrl(Track track) {
    const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
    for (final key in priority) {
      final url = track.platformLinks[key];
      if (url != null && url.isNotEmpty) return url;
    }
    return track.platformLinks.values.firstOrNull;
  }
}

class _ArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.edge,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 18),
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
