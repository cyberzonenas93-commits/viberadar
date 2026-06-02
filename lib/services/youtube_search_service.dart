import 'package:cloud_functions/cloud_functions.dart';

/// Searches YouTube for music videos via the server-side [youtubeProxy]
/// Cloud Function. No API key is held in the app bundle.
///
/// Accepts an optional [functions] parameter so unit tests can supply a fake
/// [FirebaseFunctions] without initialising a live Firebase app.
class YoutubeSearchService {
  YoutubeSearchService({FirebaseFunctions? functions})
      : _injectedFunctions = functions;

  final FirebaseFunctions? _injectedFunctions;

  /// Returns the injected instance if provided, otherwise falls back to
  /// [FirebaseFunctions.instance]. The lazy lookup defers Firebase init
  /// until the first actual API call.
  FirebaseFunctions get _functions =>
      _injectedFunctions ?? FirebaseFunctions.instance;

  // ── Core proxy helper ──────────────────────────────────────────────────────

  /// Calls the [youtubeProxy] callable with [path] and [query], returns the
  /// parsed JSON map. Throws on network / Firebase errors.
  Future<Map<String, dynamic>> _youtubeGet(
    String path,
    Map<String, dynamic> query,
  ) async {
    final callable = _functions.httpsCallable(
      'youtubeProxy',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Object?>({'path': path, 'query': query});
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Search YouTube for music videos matching [query].
  /// Filtered to the Music category (videoCategoryId=10).
  Future<List<YoutubeVideoResult>> searchMusic(String query,
      {int limit = 15}) async {
    try {
      final data = await _youtubeGet('search', {
        'part': 'snippet',
        'q': '$query music',
        'type': 'video',
        'videoCategoryId': '10',
        'maxResults': '$limit',
        'order': 'relevance',
        // NOTE: the server injects its own API key — no key sent from client
      });

      final items = data['items'] as List? ?? [];

      return items.map((item) {
        final snippet =
            item['snippet'] as Map<String, dynamic>? ?? {};
        final id = item['id']?['videoId'] as String? ?? '';
        final thumbs =
            snippet['thumbnails'] as Map<String, dynamic>? ?? {};
        final thumb =
            (thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>? ??
                {};

        return YoutubeVideoResult(
          videoId: id,
          title: _cleanTitle(snippet['title'] as String? ?? 'Unknown'),
          channelName:
              _cleanChannel(snippet['channelTitle'] as String? ?? ''),
          thumbnailUrl: thumb['url'] as String?,
          youtubeUrl: 'https://www.youtube.com/watch?v=$id',
        );
      }).where((v) => v.videoId.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Static helpers ─────────────────────────────────────────────────────────

  static String _cleanTitle(String title) {
    return title
        .replaceAll(
            RegExp(
                r'\(Official (Music )?(Video|Audio|Lyric Video|Lyrics)\)',
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'\[Official (Music )?(Video|Audio|Lyric Video|Lyrics)\]',
                caseSensitive: false),
            '')
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

// ── Data model ─────────────────────────────────────────────────────────────────

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
