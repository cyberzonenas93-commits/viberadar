import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/services/youtube_video_match_service.dart';

void main() {
  // ── YouTubeVideoMatch model tests ─────────────────────────────────────────

  group('YouTubeVideoMatch', () {
    test('isHighConfidence true for confidence >= 0.75', () {
      const match = YouTubeVideoMatch(
        videoId: 'abc',
        title: 'Test',
        channelName: 'Channel',
        youtubeUrl: 'https://youtube.com/watch?v=abc',
        confidence: 0.85,
        matchType: 'official_video',
      );
      expect(match.isHighConfidence, isTrue);
      expect(match.isLowConfidence, isFalse);
    });

    test('isLowConfidence true for confidence < 0.5', () {
      const match = YouTubeVideoMatch(
        videoId: 'abc',
        title: 'Test',
        channelName: 'Channel',
        youtubeUrl: 'https://youtube.com/watch?v=abc',
        confidence: 0.35,
        matchType: 'fallback',
      );
      expect(match.isLowConfidence, isTrue);
      expect(match.isHighConfidence, isFalse);
    });

    test('confidenceLabel returns correct labels', () {
      expect(
        const YouTubeVideoMatch(
          videoId: '', title: '', channelName: '', youtubeUrl: '',
          confidence: 0.95, matchType: '',
        ).confidenceLabel,
        'Exact',
      );
      expect(
        const YouTubeVideoMatch(
          videoId: '', title: '', channelName: '', youtubeUrl: '',
          confidence: 0.80, matchType: '',
        ).confidenceLabel,
        'High',
      );
      expect(
        const YouTubeVideoMatch(
          videoId: '', title: '', channelName: '', youtubeUrl: '',
          confidence: 0.55, matchType: '',
        ).confidenceLabel,
        'Medium',
      );
      expect(
        const YouTubeVideoMatch(
          videoId: '', title: '', channelName: '', youtubeUrl: '',
          confidence: 0.30, matchType: '',
        ).confidenceLabel,
        'Low',
      );
    });

    test('toJson / fromJson roundtrip preserves all fields', () {
      const original = YouTubeVideoMatch(
        videoId: 'dQw4w9WgXcQ',
        title: 'Rick Astley - Never Gonna Give You Up',
        channelName: 'Rick Astley',
        thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
        youtubeUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        confidence: 0.95,
        matchType: 'official_video',
        isOfficialVideo: true,
        isLyricVideo: false,
        isLivePerformance: false,
      );

      final json = original.toJson();
      final restored = YouTubeVideoMatch.fromJson(json);

      expect(restored.videoId, original.videoId);
      expect(restored.title, original.title);
      expect(restored.channelName, original.channelName);
      expect(restored.thumbnailUrl, original.thumbnailUrl);
      expect(restored.youtubeUrl, original.youtubeUrl);
      expect(restored.confidence, original.confidence);
      expect(restored.matchType, original.matchType);
      expect(restored.isOfficialVideo, original.isOfficialVideo);
      expect(restored.isLyricVideo, original.isLyricVideo);
      expect(restored.isLivePerformance, original.isLivePerformance);
    });

    test('fromJson handles missing fields gracefully', () {
      final match = YouTubeVideoMatch.fromJson(const {});
      expect(match.videoId, '');
      expect(match.confidence, 0.0);
      expect(match.matchType, 'fallback');
      expect(match.isOfficialVideo, isFalse);
    });
  });

  // ── Match type constants ──────────────────────────────────────────────────

  group('Match type constants', () {
    test('all match types are distinct strings', () {
      final types = {
        YoutubeVideoMatchService.matchTypeOfficialVideo,
        YoutubeVideoMatchService.matchTypeOfficialAudio,
        YoutubeVideoMatchService.matchTypeLyricVideo,
        YoutubeVideoMatchService.matchTypeFallback,
      };
      expect(types.length, 4);
    });
  });
}
