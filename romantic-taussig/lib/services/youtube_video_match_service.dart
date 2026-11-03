import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/video_playback_item.dart';
import 'youtube_search_service.dart';

/// Resolves a [Track] to its best YouTube video match using the YouTube Data
/// API v3 (via [YoutubeSearchService]).
///
/// Features:
/// - Smart query building from artist + title + remix tokens
/// - Confidence-scored results (official video > official audio > lyric > fallback)
/// - SharedPreferences cache with 7-day TTL to avoid repeated API calls
/// - Returns null if no match above the minimum confidence threshold (0.3)
class YoutubeVideoMatchService {
  YoutubeVideoMatchService({YoutubeSearchService? searchService})
      : _search = searchService ?? YoutubeSearchService();

  final YoutubeSearchService _search;

  /// Exposes the last error from the underlying search service (e.g. quota exceeded).
  String? get lastSearchError => _search.lastError;

  static const _cachePrefix = 'yt_match_';
  static const _cacheTtlDays = 7;

  // ── Match types ──────────────────────────────────────────────────────────

  static const matchTypeOfficialVideo = 'official_video';
  static const matchTypeOfficialAudio = 'official_audio';
  static const matchTypeLyricVideo = 'lyric_video';
  static const matchTypeFallback = 'fallback';

  // ── Public API ───────────────────────────────────────────────────────────

  /// Minimum confidence to accept a match. Lowered from 0.3 to 0.15 because
  /// the title-mismatch penalty (-0.15) could filter out valid results where
  /// YouTube's title formatting differs from the track metadata.
  static const _minConfidence = 0.15;

  /// Resolve the best YouTube video for [track].
  ///
  /// Returns a [YouTubeVideoMatch] with confidence scoring, or null if no
  /// suitable match is found.
  Future<YouTubeVideoMatch?> resolve(Track track) async {
    // 1. Check cache
    final cached = await _loadFromCache(track.id);
    if (cached != null) return cached;

    // 2. Build search query
    final query = _buildQuery(track);

    // 3. Search YouTube
    final results = await _search.searchMusic(query, limit: 5);
    if (results.isEmpty) return null;

    // 4. Score and rank results
    final scored = results.map((r) => _scoreResult(r, track)).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    // 5. Take best above threshold
    final best = scored.firstOrNull;
    if (best == null || best.confidence < _minConfidence) return null;

    // 6. Cache and return
    await _saveToCache(track.id, best);
    return best;
  }

  /// Resolve a match for a track by title and artist (when Track model is
  /// not available, e.g. from LibraryTrack).
  Future<YouTubeVideoMatch?> resolveByMetadata({
    required String trackId,
    required String title,
    required String artist,
  }) async {
    final cached = await _loadFromCache(trackId);
    if (cached != null) return cached;

    final query = '$artist $title';
    final results = await _search.searchMusic(query, limit: 5);
    if (results.isEmpty) return null;

    final scored = results.map((r) {
      return _scoreResultByMetadata(r, title, artist);
    }).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final best = scored.firstOrNull;
    if (best == null || best.confidence < _minConfidence) return null;

    await _saveToCache(trackId, best);
    return best;
  }

  /// Clear the cached match for a given track.
  Future<void> clearCache(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_cachePrefix$trackId');
  }

  // ── Query building ───────────────────────────────────────────────────────

  String _buildQuery(Track track) {
    final parts = <String>[track.artist, track.title];

    // Extract remix tokens from title — e.g. "(DJ X Remix)" or "[Extended Mix]"
    final remixMatch = RegExp(r'[\(\[](.*?(?:remix|mix|edit|version|dub))[\)\]]',
            caseSensitive: false)
        .firstMatch(track.title);
    if (remixMatch != null) {
      // Already in the title, but emphasize it for YouTube search
    }

    return parts.where((p) => p.isNotEmpty).join(' ');
  }

  // ── Scoring ──────────────────────────────────────────────────────────────

  YouTubeVideoMatch _scoreResult(YoutubeVideoResult result, Track track) {
    return _scoreResultByMetadata(result, track.title, track.artist);
  }

  YouTubeVideoMatch _scoreResultByMetadata(
    YoutubeVideoResult result,
    String trackTitle,
    String trackArtist,
  ) {
    final item = VideoPlaybackItem.youtube(
      trackId: '',
      videoId: result.videoId,
      rawTitle: result.title,
      channelName: result.channelName,
      thumbnailUrl: result.thumbnailUrl,
      artistName: trackArtist,
    );

    double confidence;
    String matchType;

    if (item.isOfficialVideo) {
      confidence = 0.95;
      matchType = matchTypeOfficialVideo;
    } else if (_isOfficialAudio(result.title)) {
      confidence = 0.85;
      matchType = matchTypeOfficialAudio;
    } else if (item.isLyricVideo) {
      confidence = 0.75;
      matchType = matchTypeLyricVideo;
    } else {
      confidence = 0.50;
      matchType = matchTypeFallback;
    }

    // Boost if channel name matches artist
    final channelLower = result.channelName.toLowerCase();
    final artistLower = trackArtist.toLowerCase();
    if (channelLower.contains(artistLower) ||
        artistLower.contains(channelLower)) {
      confidence = (confidence + 0.05).clamp(0.0, 1.0);
    }

    // Penalize based on word overlap between YouTube title and track title.
    // Old approach: exact substring match → -0.15 penalty was too aggressive.
    // New approach: measure word overlap ratio for a softer, fairer penalty.
    final resultTitleLower = result.title.toLowerCase();
    final trackTitleLower = trackTitle.toLowerCase();

    if (!resultTitleLower.contains(trackTitleLower) &&
        !trackTitleLower.contains(resultTitleLower)) {
      // Check word-level overlap
      final trackWords = trackTitleLower.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
      final resultWords = resultTitleLower.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
      if (trackWords.isNotEmpty) {
        final overlap = trackWords.intersection(resultWords).length / trackWords.length;
        if (overlap >= 0.5) {
          // Good word overlap — mild penalty
          confidence = (confidence - 0.05).clamp(0.0, 1.0);
        } else if (overlap > 0) {
          // Partial overlap
          confidence = (confidence - 0.10).clamp(0.0, 1.0);
        } else {
          // No overlap at all
          confidence = (confidence - 0.15).clamp(0.0, 1.0);
        }
      }
    }

    return YouTubeVideoMatch(
      videoId: result.videoId,
      title: result.title,
      channelName: result.channelName,
      thumbnailUrl: result.thumbnailUrl,
      youtubeUrl: result.youtubeUrl,
      confidence: confidence,
      matchType: matchType,
      isOfficialVideo: item.isOfficialVideo,
      isLyricVideo: item.isLyricVideo,
      isLivePerformance: item.isLivePerformance,
    );
  }

  bool _isOfficialAudio(String title) {
    final lower = title.toLowerCase();
    return lower.contains('official audio') ||
        lower.contains('audio only') ||
        lower.contains('official visualizer');
  }

  // ── Cache ────────────────────────────────────────────────────────────────

  Future<YouTubeVideoMatch?> _loadFromCache(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_cachePrefix$trackId');
    if (json == null) return null;

    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(map['_cachedAt'] as String? ?? '');
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt).inDays > _cacheTtlDays) {
        await prefs.remove('$_cachePrefix$trackId');
        return null;
      }
      return YouTubeVideoMatch.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(String trackId, YouTubeVideoMatch match) async {
    final prefs = await SharedPreferences.getInstance();
    final map = match.toJson();
    map['_cachedAt'] = DateTime.now().toIso8601String();
    await prefs.setString('$_cachePrefix$trackId', jsonEncode(map));
  }
}

// ── Result model ──────────────────────────────────────────────────────────────

class YouTubeVideoMatch {
  const YouTubeVideoMatch({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.thumbnailUrl,
    required this.youtubeUrl,
    required this.confidence,
    required this.matchType,
    this.isOfficialVideo = false,
    this.isLyricVideo = false,
    this.isLivePerformance = false,
  });

  final String videoId;
  final String title;
  final String channelName;
  final String? thumbnailUrl;
  final String youtubeUrl;

  /// 0.0–1.0. Below 0.3 is considered unreliable.
  final double confidence;

  /// One of: official_video, official_audio, lyric_video, fallback
  final String matchType;

  final bool isOfficialVideo;
  final bool isLyricVideo;
  final bool isLivePerformance;

  bool get isHighConfidence => confidence >= 0.75;
  bool get isLowConfidence => confidence < 0.5;

  String get confidenceLabel {
    if (confidence >= 0.9) return 'Exact';
    if (confidence >= 0.75) return 'High';
    if (confidence >= 0.5) return 'Medium';
    return 'Low';
  }

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelName': channelName,
        'thumbnailUrl': thumbnailUrl,
        'youtubeUrl': youtubeUrl,
        'confidence': confidence,
        'matchType': matchType,
        'isOfficialVideo': isOfficialVideo,
        'isLyricVideo': isLyricVideo,
        'isLivePerformance': isLivePerformance,
      };

  factory YouTubeVideoMatch.fromJson(Map<String, dynamic> json) =>
      YouTubeVideoMatch(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        channelName: json['channelName'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        youtubeUrl: json['youtubeUrl'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        matchType: json['matchType'] as String? ?? 'fallback',
        isOfficialVideo: json['isOfficialVideo'] as bool? ?? false,
        isLyricVideo: json['isLyricVideo'] as bool? ?? false,
        isLivePerformance: json['isLivePerformance'] as bool? ?? false,
      );
}
