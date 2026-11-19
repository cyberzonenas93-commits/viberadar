import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/ttl_cache.dart';

/// Searches YouTube for music videos via the server-side [youtubeProxy]
/// Cloud Function. No API key is held in the app bundle.
///
/// Accepts an optional [functions] parameter so unit tests can supply a fake
/// [FirebaseFunctions] without initialising a live Firebase app.
class YoutubeSearchService {
  YoutubeSearchService({FirebaseFunctions? functions})
    : _injectedFunctions = functions;

  final FirebaseFunctions? _injectedFunctions;
  static final _proxyCache = TtlCache<String, Map<String, dynamic>>(
    ttl: const Duration(minutes: 30),
    maxEntries: 240,
  );

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
    final cacheKey = _cacheKey(path, query);
    final cached = _proxyCache.get(cacheKey);
    if (cached != null) {
      return Map<String, dynamic>.from(cached);
    }

    final callable = _functions.httpsCallable(
      'youtubeProxy',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );
    final result = await callable.call<Object?>({'path': path, 'query': query});
    final data = Map<String, dynamic>.from(result.data as Map);
    _proxyCache.put(cacheKey, data);
    return Map<String, dynamic>.from(data);
  }

  String _cacheKey(String path, Map<String, dynamic> query) {
    final queryKey = (query.keys.toList()..sort())
        .map((key) => '$key=${query[key]}')
        .join('&');
    return '$path?$queryKey';
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Search YouTube for music videos matching [query].
  /// Filtered to the Music category (videoCategoryId=10).
  Future<List<YoutubeVideoResult>> searchMusic(
    String query, {
    int limit = 15,
  }) async {
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

      return items
          .map((item) {
            final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
            final id = item['id']?['videoId'] as String? ?? '';
            final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
            final thumb =
                (thumbs['medium'] ?? thumbs['default'])
                    as Map<String, dynamic>? ??
                {};

            return YoutubeVideoResult(
              videoId: id,
              title: _cleanTitle(snippet['title'] as String? ?? 'Unknown'),
              channelName: _cleanChannel(
                snippet['channelTitle'] as String? ?? '',
              ),
              thumbnailUrl: thumb['url'] as String?,
              youtubeUrl: 'https://www.youtube.com/watch?v=$id',
            );
          })
          .where((v) => v.videoId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch YouTube's most-popular music videos for a region.
  Future<List<YoutubeVideoResult>> fetchTrendingMusic({
    int limit = 20,
    String? region,
  }) async {
    try {
      final data = await _youtubeGet('videos', {
        'part': 'snippet,statistics',
        'chart': 'mostPopular',
        'videoCategoryId': '10',
        'maxResults': '${limit.clamp(1, 50)}',
        if (region != null && region.trim().isNotEmpty)
          'regionCode': region.trim().toUpperCase(),
      });

      final items = data['items'] as List? ?? [];
      return items
          .map((item) {
            final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
            final stats = item['statistics'] as Map<String, dynamic>? ?? {};
            final id = item['id'] as String? ?? '';
            final thumbs = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
            final thumb =
                (thumbs['medium'] ?? thumbs['high'] ?? thumbs['default'])
                    as Map<String, dynamic>? ??
                {};

            return YoutubeVideoResult(
              videoId: id,
              title: _cleanTitle(snippet['title'] as String? ?? 'Unknown'),
              channelName: _cleanChannel(
                snippet['channelTitle'] as String? ?? '',
              ),
              thumbnailUrl: thumb['url'] as String?,
              youtubeUrl: 'https://www.youtube.com/watch?v=$id',
              viewCount: _asInt(stats['viewCount']),
              likeCount: _asInt(stats['likeCount']),
              publishedAt: snippet['publishedAt'] as String?,
            );
          })
          .where((v) => v.videoId.isNotEmpty)
          .toList();
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
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[Official (Music )?(Video|Audio|Lyric Video|Lyrics)\]',
            caseSensitive: false,
          ),
          '',
        )
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

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class YoutubeVideoResult {
  final String videoId;
  final String title;
  final String channelName;
  final String? thumbnailUrl;
  final String youtubeUrl;
  final int viewCount;
  final int likeCount;
  final String? publishedAt;

  const YoutubeVideoResult({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.thumbnailUrl,
    required this.youtubeUrl,
    this.viewCount = 0,
    this.likeCount = 0,
    this.publishedAt,
  });
}
