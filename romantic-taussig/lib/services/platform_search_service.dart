import '../services/spotify_artist_service.dart';
import '../services/apple_music_artist_service.dart';
import '../services/youtube_search_service.dart';

/// A lightweight track result from platform search (not a full Firestore Track).
class PlatformTrackResult {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? youtubeUrl;
  final String? deezerUrl;
  final int durationMs;
  final int popularity;

  const PlatformTrackResult({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.spotifyUrl,
    this.appleUrl,
    this.youtubeUrl,
    this.deezerUrl,
    this.durationMs = 0,
    this.popularity = 0,
  });

  String get bestUrl => appleUrl ?? spotifyUrl ?? youtubeUrl ?? deezerUrl ?? '';
  bool get hasUrl => bestUrl.isNotEmpty;
}

/// Searches Spotify, Apple Music, and YouTube for tracks by genre, artist, or
/// freeform query. Returns merged, deduplicated results with URLs from all
/// three platforms.
class PlatformSearchService {
  final _spotify = SpotifyArtistService();
  final _apple = AppleMusicArtistService();
  final _youtube = YoutubeSearchService();

  /// Search all three platforms for tracks matching [query].
  /// Returns up to [limit] merged results.
  Future<List<PlatformTrackResult>> search(
    String query, {
    int limit = 50,
  }) async {
    final results = await Future.wait([
      _searchSpotify(query, limit: limit),
      _searchApple(query, limit: limit),
      _searchYouTube(query, limit: (limit * 0.6).round().clamp(5, 30)),
    ]);

    final spotifyResults = results[0];
    final appleResults = results[1];
    final youtubeResults = results[2];

    return _merge(spotifyResults, appleResults, youtubeResults, limit: limit);
  }

  /// Search for tracks by genre. Searches multiple representative queries
  /// for broader coverage.
  Future<List<PlatformTrackResult>> searchByGenre(
    String genre, {
    int limit = 100,
    String? era,
  }) async {
    final queries = <String>[
      '$genre',
      '$genre music',
      'best $genre songs',
      'top $genre hits',
      '$genre playlist',
      '$genre new releases',
      'popular $genre',
      '$genre classics',
      '$genre party',
      '$genre mix',
    ];

    if (era != null && era != 'All') {
      queries.add('$genre $era hits');
      queries.add('best $genre songs $era');
      queries.add('$genre $era classics');
    }

    final allResults = <PlatformTrackResult>[];
    final seen = <String>{};

    for (final query in queries) {
      if (allResults.length >= limit) break;

      final batchSize = (limit - allResults.length).clamp(20, 50);
      final batch = await search(query, limit: batchSize);
      for (final r in batch) {
        final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          allResults.add(r);
        }
      }
    }

    allResults.sort((a, b) => b.popularity.compareTo(a.popularity));
    return allResults.take(limit).toList();
  }

  /// Search for tracks by a specific artist.
  Future<List<PlatformTrackResult>> searchByArtist(
    String artistName, {
    int limit = 50,
  }) async {
    final artists = artistName.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
    final allResults = <PlatformTrackResult>[];
    final seen = <String>{};

    for (final artist in artists) {
      final perArtist = (limit / artists.length).ceil().clamp(10, limit);
      final batch = await search(artist, limit: perArtist);
      for (final r in batch) {
        final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
        if (!seen.contains(key)) {
          seen.add(key);
          allResults.add(r);
        }
      }
    }

    final results = allResults.isNotEmpty ? allResults : await search(artistName, limit: limit);
    // Filter: keep tracks where ANY of the searched artist names appear
    final normalizedParts = artists.map((a) => a.toLowerCase()).toList();
    final filtered = results.where((r) {
      final rArtist = r.artist.toLowerCase();
      return normalizedParts.any((a) => rArtist.contains(a) || a.contains(rArtist));
    }).toList();
    return filtered.isEmpty ? results.take(limit).toList() : filtered.take(limit).toList();
  }

  Future<List<PlatformTrackResult>> _searchSpotify(String query, {int limit = 50}) async {
    try {
      final results = await _spotify.searchTracks(query, limit: limit);
      return results.map((t) => PlatformTrackResult(
        title: t.name,
        artist: t.artists,
        artworkUrl: t.albumArt,
        spotifyUrl: t.spotifyUrl,
        durationMs: t.durationMs,
        popularity: t.popularity,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchApple(String query, {int limit = 50}) async {
    try {
      final results = await _apple.searchSongs(query, limit: limit);
      return results.map((t) => PlatformTrackResult(
        title: t.name,
        artist: t.artistName,
        artworkUrl: t.artworkUrl,
        appleUrl: t.appleUrl,
        durationMs: t.durationMs,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<PlatformTrackResult>> _searchYouTube(String query, {int limit = 15}) async {
    try {
      final results = await _youtube.searchMusic(query, limit: limit);
      return results.map((v) => PlatformTrackResult(
        title: v.title,
        artist: v.channelName,
        artworkUrl: v.thumbnailUrl,
        youtubeUrl: v.youtubeUrl,
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Merge Spotify, Apple Music, and YouTube results, deduplicating by title+artist.
  List<PlatformTrackResult> _merge(
    List<PlatformTrackResult> spotify,
    List<PlatformTrackResult> apple,
    List<PlatformTrackResult> youtube, {
    int limit = 50,
  }) {
    final map = <String, PlatformTrackResult>{};

    // Spotify first (usually best metadata)
    for (final t in spotify) {
      final key = _normalizeKey(t.title, t.artist);
      map[key] = t;
    }

    // Merge Apple Music
    for (final t in apple) {
      final key = _normalizeKey(t.title, t.artist);
      if (map.containsKey(key)) {
        final existing = map[key]!;
        map[key] = PlatformTrackResult(
          title: existing.title,
          artist: existing.artist,
          artworkUrl: existing.artworkUrl ?? t.artworkUrl,
          spotifyUrl: existing.spotifyUrl,
          appleUrl: t.appleUrl,
          youtubeUrl: existing.youtubeUrl,
          durationMs: existing.durationMs > 0 ? existing.durationMs : t.durationMs,
          popularity: existing.popularity,
        );
      } else {
        map[key] = t;
      }
    }

    // Merge YouTube
    for (final t in youtube) {
      final key = _normalizeKey(t.title, t.artist);
      // Try exact match first
      if (map.containsKey(key)) {
        final existing = map[key]!;
        map[key] = PlatformTrackResult(
          title: existing.title,
          artist: existing.artist,
          artworkUrl: existing.artworkUrl ?? t.artworkUrl,
          spotifyUrl: existing.spotifyUrl,
          appleUrl: existing.appleUrl,
          youtubeUrl: t.youtubeUrl,
          durationMs: existing.durationMs,
          popularity: existing.popularity,
        );
      } else {
        // Try fuzzy match — YouTube titles often include extras like "(Official Video)"
        final fuzzyKey = _fuzzyMatchKey(t.title, t.artist, map.keys);
        if (fuzzyKey != null) {
          final existing = map[fuzzyKey]!;
          map[fuzzyKey] = PlatformTrackResult(
            title: existing.title,
            artist: existing.artist,
            artworkUrl: existing.artworkUrl ?? t.artworkUrl,
            spotifyUrl: existing.spotifyUrl,
            appleUrl: existing.appleUrl,
            youtubeUrl: t.youtubeUrl,
            durationMs: existing.durationMs,
            popularity: existing.popularity,
          );
        } else {
          // Unique YouTube result — add it
          map[key] = t;
        }
      }
    }

    final merged = map.values.toList()
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return merged.take(limit).toList();
  }

  String _normalizeKey(String title, String artist) {
    final t = title.toLowerCase().trim()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final a = artist.toLowerCase().trim()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$t::$a';
  }

  /// Try to find a fuzzy match for a YouTube title among existing keys.
  String? _fuzzyMatchKey(String ytTitle, String ytArtist, Iterable<String> keys) {
    final normalized = _normalizeKey(ytTitle, ytArtist);
    final titlePart = normalized.split('::').first;
    if (titlePart.length < 4) return null;

    for (final key in keys) {
      final existingTitle = key.split('::').first;
      // Check if one title contains the other
      if (existingTitle.contains(titlePart) || titlePart.contains(existingTitle)) {
        return key;
      }
    }
    return null;
  }
}
