import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/video_playback_item.dart';
import 'package:viberadar/providers/video_player_provider.dart';

void main() {
  // ── VideoPlayerState tests ────────────────────────────────────────────────

  group('VideoPlayerState', () {
    test('default state is not visible and not loading', () {
      const state = VideoPlayerState();
      expect(state.isVisible, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.item, isNull);
      expect(state.error, isNull);
      expect(state.track, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const state = VideoPlayerState(isVisible: true, isLoading: true);
      final updated = state.copyWith(isLoading: false);
      expect(updated.isVisible, isTrue); // preserved
      expect(updated.isLoading, isFalse); // changed
    });

    test('copyWith can set item to null', () {
      final state = VideoPlayerState(
        item: VideoPlaybackItem.youtube(
          trackId: 't1',
          videoId: 'abc',
        ),
      );
      final cleared = state.copyWith(item: null);
      expect(cleared.item, isNull);
    });

    test('copyWith can set error to null', () {
      const state = VideoPlayerState(error: 'Something broke');
      final cleared = state.copyWith(error: null);
      expect(cleared.error, isNull);
    });
  });

  // ── VideoPlaybackItem integration ─────────────────────────────────────────

  group('VideoPlaybackItem for video player', () {
    test('YouTube item has correct watch URL', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't1',
        videoId: 'dQw4w9WgXcQ',
        rawTitle: 'Never Gonna Give You Up',
        channelName: 'Rick Astley',
      );
      expect(item.sourceType, VideoSourceType.youtube);
      expect(item.youtubeWatchUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(item.hasVideo, isTrue);
    });

    test('local item has file path', () {
      final item = VideoPlaybackItem.local(
        trackId: 't2',
        filePath: '/music/video.mp4',
        title: 'My Video',
      );
      expect(item.sourceType, VideoSourceType.local);
      expect(item.localFilePath, '/music/video.mp4');
      expect(item.hasVideo, isTrue);
    });

    test('detects official video from title', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't3',
        videoId: 'abc',
        rawTitle: 'Artist - Song (Official Music Video)',
        channelName: 'ArtistVEVO',
        artistName: 'Artist',
      );
      expect(item.isOfficialVideo, isTrue);
      expect(item.isLyricVideo, isFalse);
    });

    test('detects lyric video from title', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't4',
        videoId: 'def',
        rawTitle: 'Artist - Song (Lyric Video)',
      );
      expect(item.isLyricVideo, isTrue);
      expect(item.isOfficialVideo, isFalse);
    });

    test('detects live performance from title', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't5',
        videoId: 'ghi',
        rawTitle: 'Artist - Song (Live at Glastonbury)',
      );
      expect(item.isLivePerformance, isTrue);
    });

    test('VEVO channel name detects official', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't6',
        videoId: 'jkl',
        rawTitle: 'Artist - Song',
        channelName: 'ArtistVEVO',
      );
      expect(item.isOfficialVideo, isTrue);
    });

    test('artist name matching channel detects official', () {
      final item = VideoPlaybackItem.youtube(
        trackId: 't7',
        videoId: 'mno',
        rawTitle: 'Song Title',
        channelName: 'Wizkid',
        artistName: 'Wizkid',
      );
      expect(item.isOfficialVideo, isTrue);
    });
  });
}
