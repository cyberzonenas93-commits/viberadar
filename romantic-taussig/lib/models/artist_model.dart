import 'track.dart';

/// Aggregated intelligence for a single artist, derived entirely from
/// the existing [Track] data already in Firestore — no new fields added.
class ArtistModel {
  const ArtistModel({
    required this.id,
    required this.name,
    required this.genres,
    required this.popularityScore,
    required this.trendScore,
    required this.trackCount,
    required this.topTracks,
    required this.trendingTracks,
    required this.tracksByEra,
    required this.bpmRange,
    required this.leadRegion,
    required this.artworkUrl,
    required this.spotifyUrl,
    this.collaborators = const [],
    this.tracksByVibe = const {},
    this.tracksByBpmBucket = const {},
    this.greatestOfScore = 0.0,
    this.allTracks = const [],
    this.activeSources = const {},
    this.yearRange = const [],
  });

  /// Unique stable id — normalised lowercase name.
  final String id;
  final String name;

  /// All genres represented in the artist's catalogue (most common first).
  final List<String> genres;

  /// 0.0–1.0: average trend_score across all artist tracks.
  final double popularityScore;

  /// 0.0–1.0: average of the top-5 tracks by trend_score.
  final double trendScore;

  final int trackCount;

  /// Top 5 tracks by trend_score descending.
  final List<Track> topTracks;

  /// Tracks whose trend_score is above the artist's own average (rising).
  final List<Track> trendingTracks;

  /// Tracks bucketed by era key: 'Pre-2000', '2000s', '2010s', '2020s'.
  final Map<String, List<Track>> tracksByEra;

  /// [minBpm, maxBpm] across the catalogue (ignoring 0-BPM tracks).
  final List<int> bpmRange;

  /// Region with the highest average region_score across the catalogue.
  final String leadRegion;

  /// Artwork URL from the highest-trend track.
  final String? artworkUrl;

  /// Spotify URL from the highest-trend track (if available).
  final String? spotifyUrl;

  /// Artists that appear as collaborators (feat., &, x, etc.)
  final List<String> collaborators;

  /// Tracks grouped by vibe (e.g. 'club', 'chill', 'afro').
  final Map<String, List<Track>> tracksByVibe;

  /// Tracks grouped by BPM bucket (e.g. '90–99', '100–109').
  final Map<String, List<Track>> tracksByBpmBucket;

  /// Average greatest-of score across the catalogue.
  final double greatestOfScore;

  /// All tracks for this artist sorted by trendScore descending.
  final List<Track> allTracks;

  /// Sources this artist appears on (e.g. {"spotify","youtube","billboard"}).
  final Set<String> activeSources;

  /// Year range spanned by the artist's catalogue: [minYear, maxYear].
  final List<int> yearRange;

  // ── convenience getters ──────────────────────────────────────────────────

  String get primaryGenre => genres.isNotEmpty ? genres.first : 'Open Format';

  bool get hasBpmData => bpmRange.length == 2 && bpmRange[0] > 0;

  String get bpmRangeLabel =>
      hasBpmData ? '${bpmRange[0]}–${bpmRange[1]} BPM' : '—';

  bool get hasYearData => yearRange.length == 2;

  String get yearRangeLabel =>
      hasYearData ? '${yearRange[0]}–${yearRange[1]}' : '—';

  bool get hasCollaborators => collaborators.isNotEmpty;

  int get sourceCount => activeSources.length;
}
