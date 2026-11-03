import 'package:intl/intl.dart';

import '../../models/track.dart';

String formatTrendScore(double score) => '${(score * 100).round()}';

String formatCompactNumber(num value) =>
    NumberFormat.compact().format(value).replaceAll('.0', '');

String formatUpdatedAt(DateTime dateTime) =>
    DateFormat('MMM d, HH:mm').format(dateTime.toLocal());

String formatEnergy(double energy) => '${(energy * 100).round()}%';

String formatRegionLabel(String region) =>
    region == 'Global' ? 'Global' : region.toUpperCase();

double regionScoreForTrack(Track track, String region) {
  if (region == 'Global') {
    return track.trendScore;
  }

  return track.regionScores[region.toUpperCase()] ?? 0;
}
