import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Apple Music artist service using the MusicKit REST API.
/// The developer token is pre-generated (valid 180 days) and stored in .env.
class AppleMusicArtistService {
  static const _baseUrl = 'https://api.music.apple.com/v1/catalog/us';

  String? get _token => dotenv.env['APPLE_MUSIC_TOKEN'];

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${_token ?? ''}',
    'Content-Type': 'application/json',
  };

  /// Search for an artist by name. Returns the best-matching artist ID.
  Future<String?> findArtistId(String artistName) async {
    if (_token == null) return null;
    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'term': artistName,
        'types': 'artists',
        'limit': '1',
      });
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['results']?['artists']?['data'] as List?;
        if (items != null && items.isNotEmpty) {
          return items[0]['id'];
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get top songs for an artist ID.
  Future<List<AppleMusicTrack>> getTopSongs(String artistId) async {
    if (_token == null) return [];
    try {
      final uri = Uri.parse('$_baseUrl/artists/$artistId/top-songs').replace(queryParameters: {
        'limit': '20',
      });
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data'] as List? ?? [];
        return items.map((item) => AppleMusicTrack.fromJson(item)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Full flow: search by name then fetch top songs.
  Future<List<AppleMusicTrack>> getTopTracksForArtist(String artistName) async {
    final artistId = await findArtistId(artistName);
    if (artistId == null) return [];
    return getTopSongs(artistId);
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
    // Replace template placeholders with a reasonable size
    final artworkUrl = rawArtwork
        ?.replaceAll('{w}', '300')
        .replaceAll('{h}', '300');

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
