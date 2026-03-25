import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A lightweight Spotify client that fetches an artist's full catalogue
/// using Client Credentials flow (no user auth needed).
class SpotifyArtistService {
  String? _accessToken;
  DateTime? _tokenExpiry;

  Future<String?> _getToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    final clientId = dotenv.env['SPOTIFY_CLIENT_ID'];
    final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET'];
    if (clientId == null || clientSecret == null) return null;

    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _tokenExpiry = DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600));
        return _accessToken;
      }
    } catch (_) {}
    return null;
  }

  /// Search for a Spotify artist by name, return the best match artist ID.
  Future<String?> findArtistId(String artistName) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(artistName)}&type=artist&limit=1'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['artists']?['items'] as List?;
        if (items != null && items.isNotEmpty) {
          return items[0]['id'];
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch an artist's top tracks.
  Future<List<SpotifyTrackInfo>> getTopTracks(String artistId, {String market = 'US'}) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/artists/$artistId/top-tracks?market=$market'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseTracks(data['tracks'] as List? ?? []);
      }
    } catch (_) {}
    return [];
  }

  /// Fetch ALL albums for an artist (singles, albums, compilations).
  Future<List<SpotifyAlbumInfo>> getAlbums(String artistId) async {
    final token = await _getToken();
    if (token == null) return [];

    final albums = <SpotifyAlbumInfo>[];
    String? nextUrl = 'https://api.spotify.com/v1/artists/$artistId/albums?include_groups=album,single&limit=50';

    while (nextUrl != null) {
      try {
        final response = await http.get(
          Uri.parse(nextUrl),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (response.statusCode != 200) break;

        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        for (final album in items) {
          albums.add(SpotifyAlbumInfo(
            id: album['id'],
            name: album['name'],
            type: album['album_type'] ?? 'album',
            imageUrl: (album['images'] as List?)?.firstOrNull?['url'],
            releaseDate: album['release_date'],
            totalTracks: album['total_tracks'] ?? 0,
          ));
        }
        nextUrl = data['next'];
      } catch (_) {
        break;
      }
    }
    return albums;
  }

  /// Fetch all tracks from a specific album.
  Future<List<SpotifyTrackInfo>> getAlbumTracks(String albumId) async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId?market=US'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albumArt = (data['images'] as List?)?.firstOrNull?['url'];
        final tracks = data['tracks']?['items'] as List? ?? [];
        return tracks.map((t) => SpotifyTrackInfo(
          id: t['id'] ?? '',
          name: t['name'] ?? 'Unknown',
          artists: (t['artists'] as List?)?.map((a) => a['name'].toString()).join(', ') ?? '',
          durationMs: t['duration_ms'] ?? 0,
          spotifyUrl: t['external_urls']?['spotify'] ?? '',
          albumName: data['name'] ?? '',
          albumArt: albumArt,
          releaseDate: data['release_date'],
          popularity: 0, // album tracks don't have popularity
          trackNumber: t['track_number'] ?? 0,
        )).toList();
      }
    } catch (_) {}
    return [];
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
    return allTracks.map((t) => t.copyWith(isTopTrack: topIds.contains(t.id))).toList();
  }

  List<SpotifyTrackInfo> _parseTracks(List items) {
    return items.map((t) {
      final albumArt = (t['album']?['images'] as List?)?.firstOrNull?['url'];
      return SpotifyTrackInfo(
        id: t['id'] ?? '',
        name: t['name'] ?? 'Unknown',
        artists: (t['artists'] as List?)?.map((a) => a['name'].toString()).join(', ') ?? '',
        durationMs: t['duration_ms'] ?? 0,
        spotifyUrl: t['external_urls']?['spotify'] ?? '',
        albumName: t['album']?['name'] ?? '',
        albumArt: albumArt,
        releaseDate: t['album']?['release_date'],
        popularity: t['popularity'] ?? 0,
        trackNumber: t['track_number'] ?? 0,
      );
    }).toList();
  }
}

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
