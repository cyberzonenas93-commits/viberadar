import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/track.dart';
import 'source_badges.dart';

class TrackDetailPanel extends StatelessWidget {
  const TrackDetailPanel({
    super.key,
    required this.selectedTrack,
    required this.allTracks,
    required this.watchlist,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleWatchlist,
  });

  final Track? selectedTrack;
  final List<Track> allTracks;
  final Set<String> watchlist;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onToggleWatchlist;

  @override
  Widget build(BuildContext context) {
    final track = selectedTrack;
    final theme = Theme.of(context);

    if (track == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppTheme.edge),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'Select a track to see artwork, metadata, momentum, and platform links.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
      );
    }

    final relatedTracks = allTracks
        .where((candidate) => candidate.id != track.id)
        .sorted(
          (a, b) =>
              _similarityScore(track, b).compareTo(_similarityScore(track, a)),
        )
        .take(4)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
            child: Row(
              children: [
                Text(
                  'Track Detail',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleExpanded,
                  tooltip: 'Space to toggle detail density',
                  icon: Icon(
                    expanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: expanded ? 1.35 : 1.1,
                    child: track.artworkUrl.isEmpty
                        ? _FallbackArtwork(title: track.title)
                        : Image.network(
                            track.artworkUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: AppTheme.panelRaised,
                                alignment: Alignment.center,
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress
                                              .cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: AppTheme.cyan,
                                  strokeWidth: 2,
                                ),
                              );
                            },
                            errorBuilder: (_, _, _) =>
                                _FallbackArtwork(title: track.title),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            track.artist,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => onToggleWatchlist(track.id),
                      icon: Icon(
                        watchlist.contains(track.id)
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                      ),
                      label: Text(
                        watchlist.contains(track.id) ? 'Watching' : 'Watch',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (track.isRisingFast)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: AppTheme.pink.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppTheme.pink.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          color: AppTheme.pink,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Rising fast: momentum is spiking across sources.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                _MetadataGrid(track: track),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.panelRaised,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Trend graph',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Updated ${formatUpdatedAt(track.updatedAt)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: expanded ? 190 : 150,
                        child: LineChart(
                          LineChartData(
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 0.25,
                              getDrawingHorizontalLine: (_) => FlLine(
                                color: Colors.white.withValues(alpha: 0.08),
                                strokeWidth: 1,
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  getTitlesWidget: (value, meta) => Text(
                                    '${(value * 100).round()}',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index < 0 ||
                                        index >= track.trendHistory.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        track.trendHistory[index].label,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(color: Colors.white38),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            minY: 0,
                            maxY: 1,
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                color: AppTheme.cyan,
                                barWidth: 3,
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: AppTheme.cyan.withValues(alpha: 0.12),
                                ),
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter:
                                      (spot, percent, barData, index) =>
                                          FlDotCirclePainter(
                                            color: AppTheme.violet,
                                            radius: 3.4,
                                          ),
                                ),
                                spots: track.trendHistory.indexed
                                    .map(
                                      (entry) => FlSpot(
                                        entry.$1.toDouble(),
                                        entry.$2.score,
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Platform links',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                SourceBadges(sources: track.platformLinks.keys),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: track.platformLinks.entries
                      .map(
                        (entry) => FilledButton.tonalIcon(
                          onPressed: () => _openLink(entry.value),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(entry.key.toUpperCase()),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                Text(
                  'Similar tracks',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                for (final similar in relatedTracks) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.edge),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                similar.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${similar.artist} · ${similar.genre}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${similar.bpm} BPM',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppTheme.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _similarityScore(Track seed, Track candidate) {
    final genreScore = seed.genre == candidate.genre ? 0.35 : 0;
    final vibeScore = seed.vibe == candidate.vibe ? 0.25 : 0;
    final bpmScore = 1 - ((seed.bpm - candidate.bpm).abs() / 30).clamp(0, 1);
    final trendScore = candidate.trendScore * 0.15;
    return genreScore + vibeScore + (bpmScore * 0.25) + trendScore;
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final tiles = <({String label, String value})>[
      (label: 'BPM', value: track.bpm == 0 ? '--' : '${track.bpm}'),
      (label: 'Key', value: track.keySignature),
      (label: 'Genre', value: track.genre),
      (label: 'Vibe', value: track.vibe),
      (label: 'Trend', value: formatTrendScore(track.trendScore)),
      (label: 'Energy', value: formatEnergy(track.energyLevel)),
      (label: 'Lead region', value: track.leadRegion),
      (label: 'Updated', value: formatUpdatedAt(track.updatedAt)),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: tiles
          .map(
            (tile) => Container(
              width: 144,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.panelRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.edge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: Colors.white54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tile.value,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FallbackArtwork extends StatelessWidget {
  const _FallbackArtwork({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.violet, AppTheme.pink, AppTheme.cyan],
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
