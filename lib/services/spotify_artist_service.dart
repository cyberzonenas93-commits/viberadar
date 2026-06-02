import 'package:cloud_functions/cloud_functions.dart';

/// A lightweight Spotify client that fetches an artist's full catalogue
/// via the server-side [spotifyProxy] Cloud Function. No API keys are
/// held in the app bundle; authentication is handled server-side.
///
/// Accepts an optional [functions] parameter so unit tests can supply a fake
/// [FirebaseFunctions] without initialising a live Firebase app.
class SpotifyArtistService {
  SpotifyArtistService({FirebaseFunctions? functions})
      : _injectedFunctions = functions;

  final FirebaseFunctions? _injectedFunctions;

  /// Returns the injected instance if provided, otherwise falls back to
  /// [FirebaseFunctions.instance]. The lazy lookup is intentional: it defers
  /// the [Firebase.initializeApp] requirement until the first actual API call.
  FirebaseFunctions get _functions =>
      _injectedFunctions ?? FirebaseFunctions.instance;

  // ── Core proxy helper ──────────────────────────────────────────────────────

  /// Calls the [spotifyProxy] callable with [path] and [query], returns the
  /// parsed JSON map. Throws on network / Firebase errors.
  Future<Map<String, dynamic>> _spotifyGet(
    String path,
    Map<String, dynamic> query,
  ) async {
    final callable = _functions.httpsCallable(
      'spotifyProxy',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Object?>({'path': path, 'query': query});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Search Spotify for tracks matching [query]. Returns up to [limit] results.
  Future<List<SpotifyTrackInfo>> searchTracks(String query,
      {int limit = 20}) async {
    try {
      final data = await _spotifyGet('search', {
        'q': query,
        'type': 'track',
        'limit': '$limit',
        'market': 'US',
      });
      final items = data['tracks']?['items'] as List? ?? [];
      return _parseTracks(items);
    } catch (_) {
      return [];
    }
  }

  /// Search for artists by name, returns up to 20 results.
  Future<List<SpotifyArtistResult>> searchArtistsByName(String query) async {
    try {
      final data = await _spotifyGet('search', {
        'q': query,
        'type': 'artist',
        'limit': '20',
      });
      final items = data['artists']?['items'] as List? ?? [];
      return items
          .map((a) => SpotifyArtistResult(
                id: a['id'] ?? '',
                name: a['name'] ?? 'Unknown',
                imageUrl:
                    (a['images'] as List?)?.firstOrNull?['url'] as String?,
                genres: (a['genres'] as List?)
                        ?.map((g) => g.toString())
                        .toList() ??
                    [],
                followers: a['followers']?['total'] as int? ?? 0,
                popularity: a['popularity'] as int? ?? 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Search for a Spotify artist by name, return the best match artist ID.
  Future<String?> findArtistId(String artistName) async {
    try {
      final data = await _spotifyGet('search', {
        'q': artistName,
        'type': 'artist',
        'limit': '1',
      });
      final items = data['artists']?['items'] as List?;
      if (items != null && items.isNotEmpty) {
        return items[0]['id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch an artist's top tracks.
  Future<List<SpotifyTrackInfo>> getTopTracks(String artistId,
      {String market = 'US'}) async {
    try {
      final data = await _spotifyGet(
        'artists/$artistId/top-tracks',
        {'market': market},
      );
      return _parseTracks(data['tracks'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  /// Fetch ALL albums for an artist (singles, albums, compilations).
  /// NOTE: The proxy does not support cursor-based pagination (`next` URLs),
  /// so we fetch a single page of up to 50 items.
  Future<List<SpotifyAlbumInfo>> getAlbums(String artistId) async {
    final albums = <SpotifyAlbumInfo>[];
    try {
      final data = await _spotifyGet(
        'artists/$artistId/albums',
        {'include_groups': 'album,single', 'limit': '50'},
      );
      final items = data['items'] as List? ?? [];
      for (final album in items) {
        albums.add(SpotifyAlbumInfo(
          id: album['id'] as String,
          name: album['name'] as String,
          type: album['album_type'] as String? ?? 'album',
          imageUrl: (album['images'] as List?)?.firstOrNull?['url'] as String?,
          releaseDate: album['release_date'] as String?,
          totalTracks: album['total_tracks'] as int? ?? 0,
        ));
      }
    } catch (_) {}
    return albums;
  }

  /// Fetch all tracks from a specific album.
  Future<List<SpotifyTrackInfo>> getAlbumTracks(String albumId) async {
    try {
      final data = await _spotifyGet(
        'albums/$albumId',
        {'market': 'US'},
      );
      final albumArt =
          (data['images'] as List?)?.firstOrNull?['url'] as String?;
      final tracks = data['tracks']?['items'] as List? ?? [];
      return tracks
          .map((t) => SpotifyTrackInfo(
                id: t['id'] as String? ?? '',
                name: t['name'] as String? ?? 'Unknown',
                artists: (t['artists'] as List?)
                        ?.map((a) => a['name'].toString())
                        .join(', ') ??
                    '',
                durationMs: t['duration_ms'] as int? ?? 0,
                spotifyUrl: t['external_urls']?['spotify'] as String? ?? '',
                albumName: data['name'] as String? ?? '',
                albumArt: albumArt,
                releaseDate: data['release_date'] as String?,
                popularity: 0, // album tracks don't have popularity
                trackNumber: t['track_number'] as int? ?? 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Full catalogue: top tracks + all album tracks, deduplicated.
  Future<List<SpotifyTrackInfo>> getFullCatalogue(String artistName) async {
    final artistId = await findArtistId(artistName);
    if (artistId == null) return [];

    // Fetch top tracks and albums concurrently
    final results = await Future.wait([
      getTopTracks(artistId),
      getAlbums(artistId),
    ]);

    final topTracks = results[0] as List<SpotifyTrackInfo>;
    final albums = results[1] as List<SpotifyAlbumInfo>;

    // Fetch tracks from all albums (batch 5 at a time)
    final allTracks = <SpotifyTrackInfo>[...topTracks];
    final seen = <String>{...topTracks.map((t) => t.id)};

    for (var i = 0; i < albums.length; i += 5) {
      final batch = albums.skip(i).take(5);
      final batchResults = await Future.wait(
        batch.map((album) => getAlbumTracks(album.id)),
      );
      for (final tracks in batchResults) {
        for (final track in tracks) {
          if (!seen.contains(track.id)) {
            seen.add(track.id);
            allTracks.add(track);
          }
        }
      }
    }

    // Mark top tracks
    final topIds = topTracks.map((t) => t.id).toSet();
    return allTracks
        .map((t) => t.copyWith(isTopTrack: topIds.contains(t.id)))
        .toList();
  }

  /// Get artist profile (name, images, genres, followers, popularity).
  Future<SpotifyArtistProfile?> getArtistProfile(String artistId) async {
    try {
      final data = await _spotifyGet('artists/$artistId', {});
      return SpotifyArtistProfile(
        id: data['id'] as String? ?? '',
        name: data['name'] as String? ?? '',
        imageUrl: (data['images'] as List?)?.firstOrNull?['url'] as String?,
        genres: (data['genres'] as List?)?.map((g) => g.toString()).toList() ??
            [],
        followers: data['followers']?['total'] as int? ?? 0,
        popularity: data['popularity'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get full artist profile by searching name first.
  Future<SpotifyArtistProfile?> getArtistProfileByName(String name) async {
    final id = await findArtistId(name);
    if (id == null) return null;
    return getArtistProfile(id);
  }

  /// Get artists related to a given artist ID.
  Future<List<SpotifyArtistProfile>> getRelatedArtists(String artistId) async {
    try {
      final data = await _spotifyGet('artists/$artistId/related-artists', {});
      final items = data['artists'] as List? ?? [];
      return items
          .map((a) => SpotifyArtistProfile(
                id: a['id'] as String? ?? '',
                name: a['name'] as String? ?? '',
                imageUrl:
                    (a['images'] as List?)?.firstOrNull?['url'] as String?,
                genres: (a['genres'] as List?)
                        ?.map((g) => g.toString())
                        .toList() ??
                    [],
                followers: a['followers']?['total'] as int? ?? 0,
                popularity: a['popularity'] as int? ?? 0,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Get the most recent album/single for an artist.
  Future<SpotifyAlbumInfo?> getLatestRelease(String artistId) async {
    try {
      final data = await _spotifyGet(
        'artists/$artistId/albums',
        {'include_groups': 'album,single', 'limit': '1', 'market': 'US'},
      );
      final items = data['items'] as List? ?? [];
      if (items.isEmpty) return null;
      final album = items[0] as Map;
      return SpotifyAlbumInfo(
        id: album['id'] as String,
        name: album['name'] as String,
        type: album['album_type'] as String? ?? 'album',
        imageUrl:
            (album['images'] as List?)?.firstOrNull?['url'] as String?,
        releaseDate: album['release_date'] as String?,
        totalTracks: album['total_tracks'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  List<SpotifyTrackInfo> _parseTracks(List<dynamic> items) {
    return items.map((t) {
      final albumArt =
          (t['album']?['images'] as List?)?.firstOrNull?['url'] as String?;
      return SpotifyTrackInfo(
        id: t['id'] as String? ?? '',
        name: t['name'] as String? ?? 'Unknown',
        artists: (t['artists'] as List?)
                ?.map((a) => a['name'].toString())
                .join(', ') ??
            '',
        durationMs: t['duration_ms'] as int? ?? 0,
        spotifyUrl: t['external_urls']?['spotify'] as String? ?? '',
        albumName: t['album']?['name'] as String? ?? '',
        albumArt: albumArt,
        releaseDate: t['album']?['release_date'] as String?,
        popularity: t['popularity'] as int? ?? 0,
        trackNumber: t['track_number'] as int? ?? 0,
      );
    }).toList();
  }
}

// ── Data models ────────────────────────────────────────────────────────────────

class SpotifyTrackInfo {
  final String id;
  final String name;
  final String artists;
  final int durationMs;
  final String spotifyUrl;
  final String albumName;
  final String? albumArt;
  final String? releaseDate;
  final int popularity;
  final int trackNumber;
  final bool isTopTrack;

  SpotifyTrackInfo({
    required this.id,
    required this.name,
    required this.artists,
    required this.durationMs,
    required this.spotifyUrl,
    required this.albumName,
    this.albumArt,
    this.releaseDate,
    this.popularity = 0,
    this.trackNumber = 0,
    this.isTopTrack = false,
  });

  SpotifyTrackInfo copyWith({bool? isTopTrack}) => SpotifyTrackInfo(
        id: id,
        name: name,
        artists: artists,
        durationMs: durationMs,
        spotifyUrl: spotifyUrl,
        albumName: albumName,
        albumArt: albumArt,
        releaseDate: releaseDate,
        popularity: popularity,
        trackNumber: trackNumber,
        isTopTrack: isTopTrack ?? this.isTopTrack,
      );

  String get durationFormatted {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class SpotifyAlbumInfo {
  final String id;
  final String name;
  final String type;
  final String? imageUrl;
  final String? releaseDate;
  final int totalTracks;

  SpotifyAlbumInfo({
    required this.id,
    required this.name,
    required this.type,
    this.imageUrl,
    this.releaseDate,
    this.totalTracks = 0,
  });
}

class SpotifyArtistResult {
  final String id;
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final int followers;
  final int popularity;

  const SpotifyArtistResult({
    required this.id,
    required this.name,
    this.imageUrl,
    this.genres = const [],
    this.followers = 0,
    this.popularity = 0,
  });
}

class SpotifyArtistProfile {
  final String id;
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final int followers;
  final int popularity;

  const SpotifyArtistProfile({
    required this.id,
    required this.name,
    this.imageUrl,
    this.genres = const [],
    this.followers = 0,
    this.popularity = 0,
  });
}
