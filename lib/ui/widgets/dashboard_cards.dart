import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/track.dart';

class DashboardCards extends StatelessWidget {
  const DashboardCards({
    super.key,
    required this.tracks,
    required this.preferredRegion,
  });

  final List<Track> tracks;
  final String preferredRegion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final regional = [...tracks]
      ..sort(
        (a, b) => regionScoreForTrack(
          b,
          preferredRegion,
        ).compareTo(regionScoreForTrack(a, preferredRegion)),
      );
    final global = [...tracks]
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final rising = tracks.where((track) => track.isRisingFast).toList()
      ..sort(
        (a, b) =>
            b.trendHistory.last.score.compareTo(a.trendHistory.last.score),
      );

    final cards = [
      _InsightCardData(
        title: 'Trending in ${formatRegionLabel(preferredRegion)}',
        subtitle: regional.isEmpty
            ? 'No regional data yet'
            : '${regional.first.title} · ${regional.first.artist}',
        metric: regional.isEmpty
            ? '--'
            : '${(regionScoreForTrack(regional.first, preferredRegion) * 100).round()}',
        accent: AppTheme.cyan,
        caption: 'Regional trend score',
      ),
      _InsightCardData(
        title: 'Global trends',
        subtitle: global.isEmpty
            ? 'No tracks ingested'
            : '${global.first.title} · ${global.first.artist}',
        metric: global.isEmpty
            ? '--'
            : formatTrendScore(global.first.trendScore),
        accent: AppTheme.violet,
        caption: 'Global momentum',
      ),
      _InsightCardData(
        title: 'Fastest rising',
        subtitle: rising.isEmpty
            ? 'Waiting for deltas'
            : '${rising.first.title} · ${rising.first.artist}',
        metric: rising.isEmpty
            ? '--'
            : '+${((rising.first.trendHistory.last.score - rising.first.trendHistory.first.score) * 100).round()}',
        accent: AppTheme.pink,
        caption: '7-day acceleration',
      ),
    ];

    return Row(
      children: cards
          .map(
            (card) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: AppTheme.panel,
                  border: Border.all(color: AppTheme.edge),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      card.accent.withValues(alpha: 0.16),
                      AppTheme.panel,
                      AppTheme.panel,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      card.metric,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      card.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: Text(
                        card.caption,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _InsightCardData {
  const _InsightCardData({
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.accent,
    required this.caption,
  });

  final String title;
  final String subtitle;
  final String metric;
  final Color accent;
  final String caption;
}
