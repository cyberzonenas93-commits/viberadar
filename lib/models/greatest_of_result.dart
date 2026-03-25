class GreatestOfResult {
  const GreatestOfResult({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.bpm,
    required this.key,
    required this.genre,
    required this.releaseYear,
    required this.greatestScore,
    required this.components,
    required this.rank,
  });

  final String trackId;
  final String title;
  final String artist;
  final String bpm;
  final String key;
  final String genre;
  final int releaseYear;
  final int rank;
  final double greatestScore;

  /// Keys: peakTrend, longevity, culturalImpact, regionalDominance — all in [0, 1]
  final Map<String, double> components;
}
