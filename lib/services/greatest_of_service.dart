import '../models/greatest_of_result.dart';
import '../models/track.dart';

class GreatestOfService {
  /// Greatest Score formula:
  ///   greatestScore = (peakTrend * 0.35) + (longevity * 0.25) + (culturalImpact * 0.25) + (regionalDominance * 0.15)
  GreatestOfResult _score(Track track, int rank) {
    // peakTrend: highest score ever seen in trendHistory, fallback to current trendScore
    final double peakTrend = track.trendHistory.isEmpty
        ? track.trendScore
        : track.trendHistory
            .map((p) => p.score)
            .reduce((a, b) => a > b ? a : b);

    // longevity: fraction of history points with score >= 0.7, normalised to [0,1]
    final double longevity = track.trendHistory.isEmpty
        ? 0.0
        : (() {
            final weeksAbove =
                track.trendHistory.where((p) => p.score >= 0.7).length;
            return (weeksAbove / 52.0).clamp(0.0, 1.0);
          })();

    // culturalImpact: (platformLinks.length / 6) * trendScore
    final double culturalImpact =
        ((track.platformLinks.length / 6.0) * track.trendScore).clamp(0.0, 1.0);

    // regionalDominance: average of top-3 regionScores
    final double regionalDominance = (() {
      if (track.regionScores.isEmpty) return 0.0;
      final sorted = track.regionScores.values.toList()
        ..sort((a, b) => b.compareTo(a));
      final top3 = sorted.take(3).toList();
      return (top3.reduce((a, b) => a + b) / top3.length).clamp(0.0, 1.0);
    })();

    final double greatestScore = (peakTrend * 0.35) +
        (longevity * 0.25) +
        (culturalImpact * 0.25) +
        (regionalDominance * 0.15);

    return GreatestOfResult(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      bpm: track.bpm.toString(),
      key: track.keySignature,
      genre: track.genre,
      releaseYear: track.createdAt.year,
      greatestScore: greatestScore.clamp(0.0, 1.0),
      components: {
        'peakTrend': peakTrend.clamp(0.0, 1.0),
        'longevity': longevity,
        'culturalImpact': culturalImpact,
        'regionalDominance': regionalDominance,
      },
      rank: rank,
    );
  }

  List<GreatestOfResult> _rankAndTrim(List<Track> tracks) {
    if (tracks.isEmpty) return const [];

    // Score all tracks then sort descending
    final scored = tracks
        .map((t) => _score(t, 0))
        .toList()
      ..sort((a, b) => b.greatestScore.compareTo(a.greatestScore));

    // Assign 1-based rank and return top 20
    return List.generate(
      scored.length.clamp(0, 20),
      (i) => GreatestOfResult(
        trackId: scored[i].trackId,
        title: scored[i].title,
        artist: scored[i].artist,
        bpm: scored[i].bpm,
        key: scored[i].key,
        genre: scored[i].genre,
        releaseYear: scored[i].releaseYear,
        greatestScore: scored[i].greatestScore,
        components: scored[i].components,
        rank: i + 1,
      ),
    );
  }

  List<GreatestOfResult> computeForArtist(
      String artistName, List<Track> allTracks) {
    final filtered = allTracks
        .where((t) =>
            t.artist.toLowerCase().trim() ==
            artistName.toLowerCase().trim())
        .toList();
    return _rankAndTrim(filtered);
  }

  List<GreatestOfResult> computeForGenre(
      String genre, List<Track> allTracks) {
    final filtered = allTracks
        .where((t) =>
            t.genre.toLowerCase().trim() == genre.toLowerCase().trim())
        .toList();
    return _rankAndTrim(filtered);
  }
}
