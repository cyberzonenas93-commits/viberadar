import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Searches the YouTube Data API v3 for music videos.
/// Requires YOUTUBE_DATA_API_KEY in the .env file.
/// Returns an empty list (no crash) if the key is absent.
class YoutubeSearchService {
  static const _baseUrl = 'https://www.googleapis.com/youtube/v3';

  String? get _apiKey => dotenv.env['YOUTUBE_DATA_API_KEY'];

  /// Search YouTube for music videos matching [query].
  /// Filtered to the Music category (videoCategoryId=10).
  Future<List<YoutubeVideoResult>> searchMusic(String query, {int limit = 15}) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
        'part': 'snippet',
        'q': '$query music',
        'type': 'video',
        'videoCategoryId': '10',
        'maxResults': '$limit',
        'order': 'relevance',
        'key': key,
      });

      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final items = data['items'] as List? ?? [];

      return items.map((item) {
        final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
        final id = item['id']?['videoId'] as String? ?? '';
        final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final thumb = (thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>? ?? {};

        return YoutubeVideoResult(
          videoId: id,
          title: _cleanTitle(snippet['title'] as String? ?? 'Unknown'),
          channelName: _cleanChannel(snippet['channelTitle'] as String? ?? ''),
          thumbnailUrl: thumb['url'] as String?,
          youtubeUrl: 'https://www.youtube.com/watch?v=$id',
        );
      }).where((v) => v.videoId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(Official (Music )?(Video|Audio|Lyric Video|Lyrics)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[Official (Music )?(Video|Audio|Lyric Video|Lyrics)\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\|\s*.*$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }

  static String _cleanChannel(String channel) {
    return channel
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .trim();
  }
}

class YoutubeVideoResult {
  final String videoId;
  final String title;
  final String channelName;
  final String? thumbnailUrl;
  final String youtubeUrl;

  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.thumbnailUrl,
    required this.youtubeUrl,
  });
}
