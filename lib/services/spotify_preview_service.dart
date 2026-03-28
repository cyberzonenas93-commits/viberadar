import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as dev;

class SpotifyTrack {
  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUrl,
    this.previewUrl,
    this.durationMs,
    this.spotifyUri,
  });
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
  final String? previewUrl;
  final int? durationMs;
  final String? spotifyUri;

  bool get hasPreview => previewUrl != null && previewUrl!.isNotEmpty;
  String get deepLink => 'spotify:track:$id';

  double get durationSeconds => durationMs != null ? durationMs! / 1000.0 : 0.0;
}

/// Spotify service — uses Client Credentials for search + preview URLs.
/// Full track playback opens in the Spotify desktop app via deep link.
class SpotifyPreviewService {
  // Public fields — user can configure in settings
  String clientId;
  String clientSecret;

  SpotifyPreviewService({this.clientId = '', this.clientSecret = ''});

  String? _accessToken;
  DateTime? _tokenExpiry;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  Future<bool> authenticate() async {
    if (!isConfigured) return false;
    try {
      final credentials = base64.encode(utf8.encode('$clientId:$clientSecret'));
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'grant_type=client_credentials',
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = json['access_token'] as String?;
        final expiresIn = json['expires_in'] as int? ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        return _accessToken != null;
      }
    } catch (e) {
      dev.log('Spotify auth error: $e', name: 'SpotifyService');
    }
    return false;
  }

  Future<bool> _ensureToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return true;
    }
    return authenticate();
  }

  Future<List<SpotifyTrack>> search(String query, {int limit = 25}) async {
    if (!await _ensureToken()) return [];
    try {
      final uri = Uri.parse('https://api.spotify.com/v1/search').replace(
        queryParameters: {'q': query, 'type': 'track', 'limit': '$limit'},
      );
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (json['tracks']?['items'] as List?) ?? [];
        return items.map((item) {
          final m = item as Map<String, dynamic>;
          final images = (m['album']?['images'] as List?) ?? [];
          final artworkUrl = images.isNotEmpty ? images[0]['url'] as String? : null;
          final artists =
              (m['artists'] as List?)?.map((a) => a['name'] as String).join(', ') ?? '';
          return SpotifyTrack(
            id: m['id'] as String? ?? '',
            title: m['name'] as String? ?? '',
            artist: artists,
            album: m['album']?['name'] as String? ?? '',
            artworkUrl: artworkUrl,
            previewUrl: m['preview_url'] as String?,
            durationMs: m['duration_ms'] as int?,
            spotifyUri: m['uri'] as String?,
          );
        }).where((t) => t.id.isNotEmpty).toList();
      }
    } catch (e) {
      dev.log('Spotify search error: $e', name: 'SpotifyService');
    }
    return [];
  }
}
