import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';

/// Apple Music artist service backed by the server-side [appleProxy]
/// Cloud Function. No developer token is held in the app bundle.
///
/// Accepts an optional [functions] parameter so unit tests can supply a fake
/// [FirebaseFunctions] without initialising a live Firebase app.
class AppleMusicArtistService {
  AppleMusicArtistService({FirebaseFunctions? functions})
      : _injectedFunctions = functions;

  final FirebaseFunctions? _injectedFunctions;

  /// Returns the injected instance if provided, otherwise falls back to
  /// [FirebaseFunctions.instance]. The lazy lookup defers Firebase init
  /// until the first actual API call.
  FirebaseFunctions get _functions =>
      _injectedFunctions ?? FirebaseFunctions.instance;

  // ── Core proxy helper ──────────────────────────────────────────────────────

  /// Calls the [appleProxy] callable with [path] and [query], returns the
  /// parsed JSON map. Throws on network / Firebase errors.
  Future<Map<String, dynamic>> _appleGet(
    String path,
    Map<String, dynamic> query,
  ) async {
    final callable = _functions.httpsCallable(
      'appleProxy',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Object?>({'path': path, 'query': query});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Search Apple Music for songs matching [query]. Returns up to [limit] results.
  Future<List<AppleMusicTrack>> searchSongs(String query,
      {int limit = 20}) async {
    try {
      final data = await _appleGet('catalog/us/search', {
        'term': query,
        'types': 'songs',
        'limit': '$limit',
      });
      final items = data['results']?['songs']?['data'] as List? ?? [];
      return items.map((item) => AppleMusicTrack.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Search for an artist by name. Returns the best-matching artist ID.
  Future<String?> findArtistId(String artistName) async {
    final data = await _appleGet('catalog/us/search', {
      'term': artistName,
      'types': 'artists',
      'limit': '1',
    });
    final items = data['results']?['artists']?['data'] as List?;
    if (items != null && items.isNotEmpty) {
      return items[0]['id'] as String;
    }
    return null;
  }

  /// Get top songs (up to 20) for an artist ID.
  /// Returns empty on 400/404 (many artists lack this relationship).
  Future<List<AppleMusicTrack>> getTopSongs(String artistId) async {
    try {
      final data = await _appleGet(
        'catalog/us/artists/$artistId/top-songs',
        {'limit': '20'},
      );
      final items = data['data'] as List? ?? [];
      return items.map((item) => AppleMusicTrack.fromJson(item)).toList();
    } catch (_) {
      return []; // 400/404 = artist has no top-songs relationship
    }
  }

  /// Get all albums for an artist (single page, up to 100).
  Future<List<AppleMusicAlbum>> getAlbums(String artistId) async {
    final albums = <AppleMusicAlbum>[];
    try {
      final data = await _appleGet(
        'catalog/us/artists/$artistId/albums',
        {'limit': '100'},
      );
      final items = data['data'] as List? ?? [];
      albums.addAll(items.map((a) => AppleMusicAlbum.fromJson(a)));
    } catch (e, st) {
      developer.log('Failed to fetch Apple Music albums for artist "$artistId"', name: 'AppleMusicArtist', error: e, stackTrace: st);
    }
    return albums;
  }

  /// Get all tracks in an album (single page, up to 100).
  Future<List<AppleMusicTrack>> getAlbumTracks(String albumId) async {
    final tracks = <AppleMusicTrack>[];
    try {
      final data = await _appleGet(
        'catalog/us/albums/$albumId/tracks',
        {'limit': '100'},
      );
      final items = data['data'] as List? ?? [];
      tracks.addAll(items.map((t) => AppleMusicTrack.fromJson(t)));
    } catch (e, st) {
      developer.log('Failed to fetch Apple Music tracks for album "$albumId"', name: 'AppleMusicArtist', error: e, stackTrace: st);
    }
    return tracks;
  }

  /// Full discography: all tracks across all albums, deduped.
  Future<List<AppleMusicTrack>> getFullDiscography(String artistName) async {
    final artistId = await findArtistId(artistName);
    if (artistId == null) return [];

    // Fetch top songs and albums concurrently; top-songs may 404 on some artists
    final results = await Future.wait([
      getTopSongs(artistId).catchError((_) => <AppleMusicTrack>[]),
      getAlbums(artistId).catchError((_) => <AppleMusicAlbum>[]),
    ]);
    final topSongs = results[0] as List<AppleMusicTrack>;
    final albums = results[1] as List<AppleMusicAlbum>;

    final all = <AppleMusicTrack>[...topSongs];
    final seen = <String>{...topSongs.map((t) => t.id)};

    // Fetch album tracks in batches of 5
    for (var i = 0; i < albums.length; i += 5) {
      final batch = albums.skip(i).take(5);
      final batchTracks =
          await Future.wait(batch.map((a) => getAlbumTracks(a.id)));
      for (final tracks in batchTracks) {
        for (final t in tracks) {
          if (seen.add(t.id)) all.add(t);
        }
      }
    }

    return all;
  }

  /// Quick flow: just top tracks for an artist name (fast, used for initial load).
  Future<List<AppleMusicTrack>> getTopTracksForArtist(
      String artistName) async {
    final artistId = await findArtistId(artistName);
    if (artistId == null) return [];
    return getTopSongs(artistId);
  }

  /// Fetch Apple Music charts (top songs). Used by [PlaylistAggregationService].
  Future<Map<String, dynamic>> getCharts({int limit = 100}) async {
    return _appleGet('catalog/us/charts', {
      'types': 'songs',
      'limit': '$limit',
    });
  }
}

// ── Data models ────────────────────────────────────────────────────────────────

class AppleMusicAlbum {
  final String id;
  final String name;
  final String? artworkUrl;
  final String? releaseDate;
  final int trackCount;

  const AppleMusicAlbum({
    required this.id,
    required this.name,
    this.artworkUrl,
    this.releaseDate,
    this.trackCount = 0,
  });

  factory AppleMusicAlbum.fromJson(Map<String, dynamic> json) {
    final attrs = json['attributes'] as Map<String, dynamic>? ?? {};
    final rawArt = attrs['artwork']?['url'] as String?;
    return AppleMusicAlbum(
      id: json['id'] as String? ?? '',
      name: attrs['name'] as String? ?? 'Unknown',
      artworkUrl: rawArt?.replaceAll('{w}', '300').replaceAll('{h}', '300'),
      releaseDate: attrs['releaseDate'] as String?,
      trackCount: attrs['trackCount'] as int? ?? 0,
    );
  }
}

class AppleMusicTrack {
  final String id;
  final String name;
  final String albumName;
  final String artistName;
  final String? artworkUrl;
  final String? previewUrl;
  final String? appleUrl;
  final int durationMs;
  final String? releaseDate;

  const AppleMusicTrack({
    required this.id,
    required this.name,
    required this.albumName,
    required this.artistName,
    this.artworkUrl,
    this.previewUrl,
    this.appleUrl,
    required this.durationMs,
    this.releaseDate,
  });

  factory AppleMusicTrack.fromJson(Map<String, dynamic> json) {
    final attrs = json['attributes'] as Map<String, dynamic>? ?? {};
    final rawArtwork = attrs['artwork']?['url'] as String?;
    final artworkUrl =
        rawArtwork?.replaceAll('{w}', '300').replaceAll('{h}', '300');
    final previews = attrs['previews'] as List?;
    final previewUrl =
        previews?.isNotEmpty == true ? previews![0]['url'] as String? : null;
    return AppleMusicTrack(
      id: json['id'] as String? ?? '',
      name: attrs['name'] as String? ?? 'Unknown',
      albumName: attrs['albumName'] as String? ?? '',
      artistName: attrs['artistName'] as String? ?? '',
      artworkUrl: artworkUrl,
      previewUrl: previewUrl,
      appleUrl: attrs['url'] as String?,
      durationMs: attrs['durationInMillis'] as int? ?? 0,
      releaseDate: attrs['releaseDate'] as String?,
    );
  }

  String get durationFormatted {
    final minutes = durationMs ~/ 60000;
    final seconds = (durationMs % 60000) ~/ 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
