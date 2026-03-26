import '../models/artist_model.dart';
import '../models/track.dart';

/// Builds [ArtistModel] aggregates from the existing Firestore [Track] list.
/// Does NOT call any external API and does NOT write to Firestore.
/// Uses [SpotifyArtistService] data only if it is already present on tracks
/// via [platformLinks] — no new network calls are made here.
class ArtistService {
  // ── public API ────────────────────────────────────────────────────────────

  /// Build the full artist catalogue from a flat list of tracks.
  /// Returned list is sorted by [ArtistModel.trendScore] descending.
  List<ArtistModel> buildArtistCatalog(List<Track> allTracks) {
    final grouped = _groupByArtist(allTracks);
    final models = grouped.entries
        .map((e) => _buildModel(e.key, e.value))
        .toList()
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    return models;
  }

  /// Retrieve a single [ArtistModel] by name (case-insensitive).
  /// Returns null if the artist has no tracks in [allTracks].
  ArtistModel? getArtist(String name, List<Track> allTracks) {
    final key = name.trim().toLowerCase();
    final tracks = allTracks
        .where((t) => t.artist.trim().toLowerCase() == key)
        .toList();
    if (tracks.isEmpty) return null;
    return _buildModel(name.trim(), tracks);
  }

  // ── private helpers ───────────────────────────────────────────────────────

  Map<String, List<Track>> _groupByArtist(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      final name = t.artist.trim();
      if (name.isEmpty) continue;
      map.putIfAbsent(name, () => []).add(t);
    }
    return map;
  }

  ArtistModel _buildModel(String name, List<Track> tracks) {
    // Sort all tracks by trendScore descending once
    final sorted = [...tracks]
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));

    // Popularity = avg trend across all tracks
    final popularityScore = tracks.isEmpty
        ? 0.0
        : tracks.map((t) => t.trendScore).reduce((a, b) => a + b) /
              tracks.length;

    // Trend score = avg of top 5
    final top5 = sorted.take(5).toList();
    final trendScore = top5.isEmpty
        ? 0.0
        : top5.map((t) => t.trendScore).reduce((a, b) => a + b) / top5.length;

    // Trending = tracks above artist avg
    final trendingTracks = tracks
        .where((t) => t.trendScore > popularityScore)
        .toList()
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));

    // Genres — most common first
    final genreCounts = <String, int>{};
    for (final t in tracks) {
      if (t.genre.isNotEmpty) {
        genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      }
    }
    final genres = (genreCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .toList();

    // Era grouping
    final tracksByEra = _groupByEra(tracks);

    // BPM range (exclude 0-BPM unknowns)
    final bpms = tracks.map((t) => t.bpm).where((b) => b > 0).toList();
    final bpmRange = bpms.isEmpty
        ? <int>[]
        : [
            bpms.reduce((a, b) => a < b ? a : b),
            bpms.reduce((a, b) => a > b ? a : b),
          ];

    // Lead region — region with highest avg score
    final regionTotals = <String, double>{};
    final regionCounts = <String, int>{};
    for (final t in tracks) {
      for (final entry in t.regionScores.entries) {
        regionTotals[entry.key] =
            (regionTotals[entry.key] ?? 0.0) + entry.value;
        regionCounts[entry.key] = (regionCounts[entry.key] ?? 0) + 1;
      }
    }
    String leadRegion = 'Global';
    if (regionTotals.isNotEmpty) {
      final avgScores = regionTotals.map(
        (k, v) => MapEntry(k, v / (regionCounts[k] ?? 1)),
      );
      leadRegion = (avgScores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    }

    // Artwork + Spotify URL from best track
    final best = sorted.first;
    return ArtistModel(
      id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
      name: name,
      genres: genres,
      popularityScore: popularityScore,
      trendScore: trendScore,
      trackCount: tracks.length,
      topTracks: top5,
      trendingTracks: trendingTracks,
      tracksByEra: tracksByEra,
      bpmRange: bpmRange,
      leadRegion: leadRegion,
      artworkUrl: best.artworkUrl.isNotEmpty ? best.artworkUrl : null,
      spotifyUrl: best.platformLinks['spotify'],
    );
  }

  Map<String, List<Track>> _groupByEra(List<Track> tracks) {
    final map = <String, List<Track>>{};
    for (final t in tracks) {
      final y = t.createdAt.year;
      final era = y < 2010 ? '2000s' : (y < 2020 ? '2010s' : '2020s');
      map.putIfAbsent(era, () => []).add(t);
    }
    // Sort within each era by trendScore descending
    for (final era in map.keys) {
      map[era]!.sort((a, b) => b.trendScore.compareTo(a.trendScore));
    }
    return map;
  }
}
