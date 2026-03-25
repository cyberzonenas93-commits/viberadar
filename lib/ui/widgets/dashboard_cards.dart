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
        (a, b) => regionScoreForTrack(b, preferredRegion)
            .compareTo(regionScoreForTrack(a, preferredRegion)),
      );
    final global = [...tracks]
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    final rising = tracks.where((track) => track.isRisingFast).toList()
      ..sort(
        (a, b) => b.trendHistory.last.score.compareTo(a.trendHistory.last.score),
      );

    final cards = [
      _InsightCardData(
        title: 'Regional Hot',
        region: formatRegionLabel(preferredRegion),
        subtitle: regional.isEmpty
            ? 'No regional data yet'
            : '${regional.first.title} · ${regional.first.artist}',
        metric: regional.isEmpty
            ? '--'
            : '${(regionScoreForTrack(regional.first, preferredRegion) * 100).round()}',
        accent: AppTheme.cyan,
        icon: Icons.location_on_rounded,
        caption: 'Regional trend score',
      ),
      _InsightCardData(
        title: 'Global #1',
        region: null,
        subtitle: global.isEmpty
            ? 'No tracks ingested'
            : '${global.first.title} · ${global.first.artist}',
        metric: global.isEmpty
            ? '--'
            : formatTrendScore(global.first.trendScore),
        accent: AppTheme.violet,
        icon: Icons.public_rounded,
        caption: 'Global momentum',
      ),
      _InsightCardData(
        title: 'Fastest Rising',
        region: null,
        subtitle: rising.isEmpty
            ? 'Waiting for deltas'
            : '${rising.first.title} · ${rising.first.artist}',
        metric: rising.isEmpty
            ? '--'
            : '+${((rising.first.trendHistory.last.score - rising.first.trendHistory.first.score) * 100).round()}',
        accent: AppTheme.pink,
        icon: Icons.trending_up_rounded,
        caption: '7-day acceleration',
      ),
    ];

    return Row(
      children: cards.asMap().entries.map((entry) {
        final i = entry.key;
        final card = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              left: i == 0 ? 0 : 8,
              right: i == cards.length - 1 ? 0 : 8,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppTheme.panel,
              border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  card.accent.withValues(alpha: 0.12),
                  AppTheme.panel.withValues(alpha: 0.95),
                  AppTheme.panel,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: card.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(card.icon, color: card.accent, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (card.region != null)
                          Text(
                            card.region!,
                            style: TextStyle(
                              color: card.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  card.metric,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 36,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  card.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: card.accent.withValues(alpha: 0.08),
                  ),
                  child: Text(
                    card.caption,
                    style: TextStyle(
                      color: card.accent.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _InsightCardData {
  const _InsightCardData({
    required this.title,
    required this.region,
    required this.subtitle,
    required this.metric,
    required this.accent,
    required this.icon,
    required this.caption,
  });

  final String title;
  final String? region;
  final String subtitle;
  final String metric;
  final Color accent;
  final IconData icon;
  final String caption;
}
