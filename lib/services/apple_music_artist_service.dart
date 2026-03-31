import 'dart:convert';
import 'dart:developer' as dev;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Apple Music artist service using the MusicKit REST API.
/// The developer token is pre-generated (valid 180 days) and stored in .env.
class AppleMusicArtistService {
  static const _baseUrl = 'https://api.music.apple.com/v1/catalog/us';

  String? get _token => dotenv.env['APPLE_MUSIC_TOKEN'];

  // NOTE: no Content-Type on GET requests — Apple Music returns 400 with it
  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${_token ?? ''}',
  };

  /// Search Apple Music for songs matching [query]. Returns up to [limit] results.
  Future<List<AppleMusicTrack>> searchSongs(String query, {int limit = 20}) async {
    if (_token == null || _token!.isEmpty) {
      dev.log('[AppleMusic] No token configured', name: 'AppleMusic');
      return [];
    }
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'term': query,
        'types': 'songs',
        'limit': '$limit',
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        dev.log('[AppleMusic] Search failed: ${response.statusCode} — ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}', name: 'AppleMusic');
        return [];
      }
      final data = jsonDecode(response.body);
      final items = data['results']?['songs']?['data'] as List? ?? [];
      dev.log('[AppleMusic] Got ${items.length} results for "$query"', name: 'AppleMusic');
      return items.map((item) => AppleMusicTrack.fromJson(item)).toList();
    } catch (e) {
      dev.log('[AppleMusic] Search error: $e', name: 'AppleMusic');
      return [];
    }
  }

  /// Search Apple Music for albums matching [query]. Returns up to [limit] results.
  Future<List<AppleMusicAlbum>> searchAlbums(String query, {int limit = 20}) async {
    if (_token == null || _token!.isEmpty) {
      dev.log('[AppleMusic] No token configured', name: 'AppleMusic');
      return [];
    }
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'term': query,
        'types': 'albums',
        'limit': '$limit',
      });
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        dev.log('[AppleMusic] Album search failed: ${response.statusCode}', name: 'AppleMusic');
        return [];
      }
      final data = jsonDecode(response.body);
      final items = data['results']?['albums']?['data'] as List? ?? [];
      dev.log('[AppleMusic] Got ${items.length} album results for "$query"', name: 'AppleMusic');
      return items.map((item) => AppleMusicAlbum.fromJson(item)).toList();
    } catch (e) {
      dev.log('[AppleMusic] Album search error: $e', name: 'AppleMusic');
      return [];
    }
  }

  /// Search for an artist by name. Returns the best-matching artist ID.
  Future<String?> findArtistId(String artistName) async {
    if (_token == null) throw Exception('Apple Music token not configured in .env');
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'term': artistName,
      'types': 'artists',
      'limit': '1',
    });
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 401) throw Exception('Apple Music token invalid or expired (401)');
    if (response.statusCode != 200) {
      throw Exception('Apple Music search failed: ${response.statusCode} — ${response.body}');
    }
    final data = jsonDecode(response.body);
    final items = data['results']?['artists']?['data'] as List?;
    if (items != null && items.isNotEmpty) {
      return items[0]['id'] as String;
    }
    return null;
  }

  /// Get top songs (up to 20) for an artist ID. Returns empty on 400/404 (many artists lack this relationship).
  Future<List<AppleMusicTrack>> getTopSongs(String artistId) async {
    if (_token == null) throw Exception('Apple Music token not configured');
    final uri = Uri.parse('$_baseUrl/artists/$artistId/top-songs').replace(queryParameters: {
      'limit': '20',
    });
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 401) throw Exception('Apple Music token invalid or expired (401)');
    if (response.statusCode != 200) return []; // 400/404 = artist has no top-songs relationship
    final data = jsonDecode(response.body);
    final items = data['data'] as List? ?? [];
    return items.map((item) => AppleMusicTrack.fromJson(item)).toList();
  }

  /// Get all albums for an artist (paginated).
  Future<List<AppleMusicAlbum>> getAlbums(String artistId) async {
    if (_token == null) throw Exception('Apple Music token not configured');
    final albums = <AppleMusicAlbum>[];
    String? nextUrl = '$_baseUrl/artists/$artistId/albums?limit=100';
    while (nextUrl != null) {
      final response = await http.get(Uri.parse(nextUrl), headers: _headers);
      if (response.statusCode != 200) break;
      final data = jsonDecode(response.body);
      final items = data['data'] as List? ?? [];
      albums.addAll(items.map((a) => AppleMusicAlbum.fromJson(a)));
      final next = data['next'] as String?;
      nextUrl = next != null ? 'https://api.music.apple.com$next' : null;
    }
    return albums;
  }

  /// Get all tracks in an album.
  Future<List<AppleMusicTrack>> getAlbumTracks(String albumId) async {
    if (_token == null) throw Exception('Apple Music token not configured');
    final tracks = <AppleMusicTrack>[];
    String? nextUrl = '$_baseUrl/albums/$albumId/tracks?limit=100';
    while (nextUrl != null) {
      final response = await http.get(Uri.parse(nextUrl), headers: _headers);
      if (response.statusCode != 200) break;
      final data = jsonDecode(response.body);
      final items = data['data'] as List? ?? [];
      tracks.addAll(items.map((t) => AppleMusicTrack.fromJson(t)));
      final next = data['next'] as String?;
      nextUrl = next != null ? 'https://api.music.apple.com$next' : null;
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
      final batchTracks = await Future.wait(batch.map((a) => getAlbumTracks(a.id)));
      for (final tracks in batchTracks) {
        for (final t in tracks) {
          if (seen.add(t.id)) all.add(t);
        }
      }
    }

    return all;
  }

  /// Quick flow: just top tracks for an artist name (fast, used for initial load).
  Future<List<AppleMusicTrack>> getTopTracksForArtist(String artistName) async {
    final artistId = await findArtistId(artistName);
    if (artistId == null) return [];
    return getTopSongs(artistId);
  }
}

class AppleMusicAlbum {
  final String id;
  final String name;
  final String? artistName;
  final String? artworkUrl;
  final String? releaseDate;
  final int trackCount;

  const AppleMusicAlbum({
    required this.id,
    required this.name,
    this.artistName,
    this.artworkUrl,
    this.releaseDate,
    this.trackCount = 0,
  });

  factory AppleMusicAlbum.fromJson(Map<String, dynamic> json) {
    final attrs = json['attributes'] as Map<String, dynamic>? ?? {};
    final rawArt = attrs['artwork']?['url'] as String?;
    return AppleMusicAlbum(
      id: json['id'] ?? '',
      name: attrs['name'] ?? 'Unknown',
      artistName: attrs['artistName'] as String?,
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
    final artworkUrl = rawArtwork?.replaceAll('{w}', '300').replaceAll('{h}', '300');
    final previews = attrs['previews'] as List?;
    final previewUrl = previews?.isNotEmpty == true ? previews![0]['url'] as String? : null;
    return AppleMusicTrack(
      id: json['id'] ?? '',
      name: attrs['name'] ?? 'Unknown',
      albumName: attrs['albumName'] ?? '',
      artistName: attrs['artistName'] ?? '',
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
