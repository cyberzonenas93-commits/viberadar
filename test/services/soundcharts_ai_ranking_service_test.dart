import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/soundcharts_ai_ranking_service.dart';

void main() {
  group('SoundchartsAiRankingService', () {
    test(
      'applies AI ordering to Soundcharts-backed candidate windows',
      () async {
        final service = SoundchartsAiRankingService(
          requestJson: (_) async => '{"ids":["c1","c0"]}',
        );
        final soundcharts = const PlatformTrackResult(
          title: 'Chart Heat',
          artist: 'DJ Signal',
          soundchartsUrl: 'https://soundcharts.com/chart-heat',
          soundchartsSource: 'shazam',
          soundchartsRegion: 'GH',
          popularity: 60,
          trendScore: 0.6,
        );
        final spotify = const PlatformTrackResult(
          title: 'Streaming Giant',
          artist: 'DJ Signal',
          spotifyUrl: 'https://open.spotify.com/track/1',
          popularity: 95,
        );

        final ranked = await service.rankForSetBuilder(
          results: [soundcharts, spotify],
          mode: 'Top Trending',
          genre: 'Afrobeats',
          region: 'GH',
        );

        expect(ranked.first.title, 'Streaming Giant');
        expect(ranked.last.title, 'Chart Heat');
      },
    );

    test('falls back to chart-aware deterministic ranking', () async {
      final service = SoundchartsAiRankingService(
        requestJson: (_) async => throw StateError('AI unavailable'),
      );
      final generic = const PlatformTrackResult(
        title: 'Generic Hit',
        artist: 'Popular Artist',
        spotifyUrl: 'https://open.spotify.com/track/2',
        popularity: 90,
      );
      final charted = const PlatformTrackResult(
        title: 'Regional Breakout',
        artist: 'Chart Artist',
        soundchartsUrl: 'https://soundcharts.com/regional-breakout',
        soundchartsSource: 'tiktok',
        soundchartsRegion: 'NG',
        popularity: 45,
        trendScore: 0.55,
      );

      final ranked = await service.rankForSetBuilder(
        results: [generic, charted],
        mode: 'Rising Fast',
        genre: 'Afrobeats',
        region: 'NG',
      );

      expect(ranked.first.title, 'Regional Breakout');
    });

    test('applies AI ordering to platform-only candidate windows', () async {
      var called = false;
      final service = SoundchartsAiRankingService(
        requestJson: (_) async {
          called = true;
          return '{"ids":["c1"]}';
        },
      );

      final ranked = await service.rankForGreatestOf(
        results: const [
          PlatformTrackResult(
            title: 'Low',
            artist: 'Artist',
            spotifyUrl: 'https://open.spotify.com/track/low',
            popularity: 20,
          ),
          PlatformTrackResult(
            title: 'High',
            artist: 'Artist',
            appleUrl: 'https://music.apple.com/high',
            popularity: 80,
          ),
        ],
        genre: 'All',
        region: 'All',
        artist: '',
      );

      expect(called, isTrue);
      expect(ranked.first.title, 'Low');
    });
  });
}
