import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Searches the YouTube Data API v3 for music videos.
///
/// Implements a multi-layered quota protection system:
/// 1. **In-memory cache** — identical queries within the same session are free.
/// 2. **Persistent disk cache** — results survive app restarts (24h TTL).
/// 3. **Daily quota tracking** — counts API calls and stops before the limit.
/// 4. **Rate limiting** — minimum 500ms between API calls.
/// 5. **Quota-exceeded detection** — auto-disables calls for the rest of the day
///    when a 403/quotaExceeded response is received.
///
/// YouTube Data API v3 grants 10,000 units/day.
/// Each `search.list` call costs 100 units → max ~100 searches/day.
/// We budget conservatively: 80 searches/day, reserving 20 for headroom.
class YoutubeSearchService {
  static const _baseUrl = 'https://www.googleapis.com/youtube/v3';
  static const _maxDailySearches = 80;
  static const _cachePrefix = 'yt_search_cache_';
  static const _quotaCounterKey = 'yt_quota_count';
  static const _quotaDateKey = 'yt_quota_date';
  static const _quotaExceededKey = 'yt_quota_exceeded_date';
  static const _cacheTtlHours = 24;

  String? get _apiKey => dotenv.env['YOUTUBE_DATA_API_KEY'];

  /// Last error message from the most recent search attempt.
  String? lastError;

  /// Tracks which API key the quota state belongs to. When the key changes
  /// (e.g. user sets a new one), the persisted quota state is automatically
  /// invalidated so the new key starts fresh.
  static String _quotaKeyFingerprint = '';

  /// Whether the quota is currently exceeded (detected via 403 or counter).
  bool get isQuotaExceeded => _quotaExceededToday;

  /// How many API calls remain today (approximate).
  int get remainingQuota => (_maxDailySearches - _todayCallCount).clamp(0, _maxDailySearches);

  // ── In-memory state ──────────────────────────────────────────────────────

  /// In-memory LRU cache: query → results. Avoids disk I/O for repeat queries.
  static final Map<String, List<YoutubeVideoResult>> _memCache = {};
  static const _memCacheMaxSize = 200;

  /// Rate limiter: timestamp of last API call.
  static DateTime _lastApiCall = DateTime(2000);
  static const _minCallInterval = Duration(milliseconds: 500);

  /// Daily quota tracking (in-memory, synced from prefs on first use).
  static int _todayCallCount = 0;
  static String _todayDate = '';
  static bool _quotaExceededToday = false;
  static bool _quotaLoaded = false;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Search YouTube for music videos matching [query].
  ///
  /// Results are served from cache when available. API calls are quota-gated.
  /// Returns an empty list (no crash) if the key is absent, quota is exceeded,
  /// or the search fails.
  Future<List<YoutubeVideoResult>> searchMusic(String query, {int limit = 5}) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return [];

    final key = _apiKey;
    if (key == null || key.isEmpty) {
      lastError = 'YouTube API key not configured';
      return [];
    }

    // 1. Check in-memory cache first (free, instant)
    if (_memCache.containsKey(normalizedQuery)) {
      dev.log('[YT] Memory cache hit: "$normalizedQuery"', name: 'YoutubeSearch');
      return _memCache[normalizedQuery]!;
    }

    // 2. Check disk cache (free, fast)
    final diskCached = await _loadDiskCache(normalizedQuery);
    if (diskCached != null) {
      dev.log('[YT] Disk cache hit: "$normalizedQuery"', name: 'YoutubeSearch');
      _memCache[normalizedQuery] = diskCached;
      return diskCached;
    }

    // 3. Check quota before making an API call
    await _loadQuotaIfNeeded();
    if (_quotaExceededToday) {
      lastError = 'YouTube daily quota exceeded. Resets at midnight Pacific Time.';
      dev.log('[YT] Quota exceeded, skipping API call', name: 'YoutubeSearch');
      return [];
    }
    if (_todayCallCount >= _maxDailySearches) {
      lastError = 'YouTube daily search budget reached ($_maxDailySearches/$_maxDailySearches). Resets tomorrow.';
      dev.log('[YT] Daily budget reached', name: 'YoutubeSearch');
      return [];
    }

    // 4. Rate limit — wait if needed
    final now = DateTime.now();
    final elapsed = now.difference(_lastApiCall);
    if (elapsed < _minCallInterval) {
      await Future<void>.delayed(_minCallInterval - elapsed);
    }

    // 5. Make the API call (costs 100 quota units)
    lastError = null;
    final results = await _doSearch(normalizedQuery, key, limit: limit);

    // 6. Increment quota counter
    _lastApiCall = DateTime.now();
    _todayCallCount++;
    await _saveQuota();

    // 7. Cache results (even empty — avoids retrying failed queries)
    _putMemCache(normalizedQuery, results);
    await _saveDiskCache(normalizedQuery, results);

    return results;
  }

  /// Reset the quota counter (useful for testing or when a new API key is set).
  Future<void> resetQuota() async {
    _todayCallCount = 0;
    _quotaExceededToday = false;
    _todayDate = _dateKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_quotaCounterKey, 0);
    await prefs.setString(_quotaDateKey, _todayDate);
    await prefs.remove(_quotaExceededKey);
  }

  /// Clear all cached search results.
  Future<void> clearCache() async {
    _memCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ── Core search ──────────────────────────────────────────────────────────

  Future<List<YoutubeVideoResult>> _doSearch(
    String query,
    String key, {
    required int limit,
  }) async {
    try {
      // Cap limit to 5 to conserve quota (search.list costs same regardless of maxResults,
      // but smaller responses are faster)
      final effectiveLimit = limit.clamp(1, 10);
      final params = <String, String>{
        'part': 'snippet',
        'q': query,
        'type': 'video',
        'videoCategoryId': '10',
        'maxResults': '$effectiveLimit',
        'order': 'relevance',
        'key': key,
      };

      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);
      dev.log('[YT] API call #$_todayCallCount: "$query"', name: 'YoutubeSearch');

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 403) {
        // Check if it's a quota exceeded error
        final body = response.body.toLowerCase();
        if (body.contains('quota') || body.contains('exceeded') || body.contains('rateLimitExceeded')) {
          _quotaExceededToday = true;
          lastError = 'YouTube API quota exceeded for today. Resets at midnight Pacific Time.';
          dev.log('[YT] ⚠️ QUOTA EXCEEDED — disabling API calls for today', name: 'YoutubeSearch');
          await _saveQuotaExceeded();
          return [];
        }
        lastError = 'YouTube API returned 403 (forbidden)';
        dev.log('[YT] 403 error: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}', name: 'YoutubeSearch');
        return [];
      }

      if (response.statusCode != 200) {
        lastError = 'YouTube API returned ${response.statusCode}';
        dev.log('[YT] Error ${response.statusCode}', name: 'YoutubeSearch');
        return [];
      }

      final data = jsonDecode(response.body);
      final items = data['items'] as List? ?? [];
      dev.log('[YT] Got ${items.length} results', name: 'YoutubeSearch');

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
    } catch (e) {
      lastError = 'YouTube search error: $e';
      dev.log('[YT] Exception: $e', name: 'YoutubeSearch');
      return [];
    }
  }

  // ── In-memory cache ──────────────────────────────────────────────────────

  void _putMemCache(String key, List<YoutubeVideoResult> results) {
    // Evict oldest if at capacity
    if (_memCache.length >= _memCacheMaxSize) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = results;
  }

  // ── Disk cache ───────────────────────────────────────────────────────────

  Future<List<YoutubeVideoResult>?> _loadDiskCache(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_cachePrefix${query.hashCode}');
      if (json == null) return null;

      final map = jsonDecode(json) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(map['_cachedAt'] as String? ?? '');
      if (cachedAt == null || DateTime.now().difference(cachedAt).inHours > _cacheTtlHours) {
        await prefs.remove('$_cachePrefix${query.hashCode}');
        return null;
      }

      final items = (map['items'] as List?)?.map((item) {
        final m = item as Map<String, dynamic>;
        return YoutubeVideoResult(
          videoId: m['videoId'] as String? ?? '',
          title: m['title'] as String? ?? '',
          channelName: m['channelName'] as String? ?? '',
          thumbnailUrl: m['thumbnailUrl'] as String?,
          youtubeUrl: m['youtubeUrl'] as String? ?? '',
        );
      }).where((v) => v.videoId.isNotEmpty).toList();

      return items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveDiskCache(String query, List<YoutubeVideoResult> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        '_cachedAt': DateTime.now().toIso8601String(),
        'items': results.map((r) => {
          'videoId': r.videoId,
          'title': r.title,
          'channelName': r.channelName,
          'thumbnailUrl': r.thumbnailUrl,
          'youtubeUrl': r.youtubeUrl,
        }).toList(),
      };
      await prefs.setString('$_cachePrefix${query.hashCode}', jsonEncode(map));
    } catch (_) {
      // Non-critical — cache failure shouldn't break search
    }
  }

  // ── Quota tracking ───────────────────────────────────────────────────────

  String _dateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadQuotaIfNeeded() async {
    // Detect API key change — if key changed, reset all quota state
    final currentKey = _apiKey ?? '';
    final keyFp = currentKey.length > 8 ? currentKey.substring(currentKey.length - 8) : currentKey;
    if (_quotaKeyFingerprint.isNotEmpty && _quotaKeyFingerprint != keyFp) {
      dev.log('[YT] API key changed — resetting quota state', name: 'YoutubeSearch');
      _quotaLoaded = false;
      _todayCallCount = 0;
      _quotaExceededToday = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_quotaCounterKey);
      await prefs.remove(_quotaDateKey);
      await prefs.remove(_quotaExceededKey);
      await prefs.setString('yt_key_fingerprint', keyFp);
    }
    _quotaKeyFingerprint = keyFp;

    if (_quotaLoaded && _todayDate == _dateKey()) return;

    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    final savedDate = prefs.getString(_quotaDateKey) ?? '';

    // Also check if the saved key fingerprint matches current key
    final savedFp = prefs.getString('yt_key_fingerprint') ?? '';
    final keyChanged = savedFp.isNotEmpty && savedFp != keyFp;

    if (savedDate == today && !keyChanged) {
      _todayCallCount = prefs.getInt(_quotaCounterKey) ?? 0;
      _quotaExceededToday = prefs.getString(_quotaExceededKey) == today;
    } else {
      // New day or new key — reset
      _todayCallCount = 0;
      _quotaExceededToday = false;
      await prefs.setInt(_quotaCounterKey, 0);
      await prefs.setString(_quotaDateKey, today);
      await prefs.remove(_quotaExceededKey);
      await prefs.setString('yt_key_fingerprint', keyFp);
    }
    _todayDate = today;
    _quotaLoaded = true;
  }

  Future<void> _saveQuota() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_quotaCounterKey, _todayCallCount);
    await prefs.setString(_quotaDateKey, _todayDate);
  }

  Future<void> _saveQuotaExceeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_quotaExceededKey, _dateKey());
  }

  // ── Text cleaning ────────────────────────────────────────────────────────

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
