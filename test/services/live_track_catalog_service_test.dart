import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/services/live_track_catalog_service.dart';
import 'package:viberadar/services/platform_search_service.dart';

class _FakePlatformSearchService extends PlatformSearchService {
  _FakePlatformSearchService(this.results);

  final List<PlatformTrackResult> results;
  String? seenRegion;
  String? seenGenre;

  @override
  Future<List<PlatformTrackResult>> fetchTrendingChartTracks({
    String? region,
    String? genre,
    int limit = 100,
  }) async {
    seenRegion = region;
    seenGenre = genre;
    return results;
  }
}

void main() {
  test(
    'fetchTrendingTracks keeps chart-backed tracks and drops platform-only rows',
    () async {
      final platform = _FakePlatformSearchService([
        const PlatformTrackResult(
          title: 'Market Heat',
          artist: 'Accra Artist',
          artworkUrl: 'https://example.com/art.jpg',
          appleUrl: 'https://music.apple.com/gh/song/market-heat',
          soundchartsUrl: 'https://soundcharts.com/song/market-heat',
          soundchartsSource: 'Shazam',
          soundchartsRegion: 'GH',
          appleChartRank: 4,
          genre: 'Afrobeats',
          popularity: 98,
          trendScore: 0.91,
        ),
        const PlatformTrackResult(
          title: 'Spotify Market Result',
          artist: 'Platform Artist',
          spotifyUrl: 'https://open.spotify.com/track/global',
          popularity: 94,
        ),
      ]);
      final service = LiveTrackCatalogService(platformSearch: platform);

      final tracks = await service.fetchTrendingTracks(region: 'GH');

      expect(platform.seenRegion, 'GH');
      expect(tracks, hasLength(1));
      expect(tracks.first.title, 'Market Heat');
      expect(tracks.first.regionScores, containsPair('GH', 0.91));
      expect(
        tracks.first.platformLinks.keys,
        containsAll(['apple', 'soundcharts']),
      );
      expect(tracks.first.sources, containsAll(['Shazam', 'apple']));
    },
  );

  test(
    'fetchTrendingTracks treats Global as global instead of Ghana',
    () async {
      final platform = _FakePlatformSearchService([
        const PlatformTrackResult(
          title: 'Global Heat',
          artist: 'World Artist',
          spotifyUrl: 'https://open.spotify.com/track/global',
          soundchartsUrl: 'https://soundcharts.com/song/global-heat',
          soundchartsSource: 'Shazam',
          popularity: 92,
        ),
      ]);
      final service = LiveTrackCatalogService(platformSearch: platform);

      final tracks = await service.fetchTrendingTracks(region: 'Global');

      expect(platform.seenRegion, isNull);
      expect(tracks, hasLength(1));
      expect(tracks.single.regionScores, containsPair('Global', 0.92));
    },
  );

  test('fetchTrendingTracks drops platform-only rows on Global', () async {
    final platform = _FakePlatformSearchService([
      const PlatformTrackResult(
        title: 'Chart Anchored',
        artist: 'Chart Artist',
        soundchartsUrl: 'https://soundcharts.com/song/anchored',
        soundchartsSource: 'Shazam',
        popularity: 70,
      ),
      const PlatformTrackResult(
        title: 'Best Music Songs Result',
        artist: 'Search Junk',
        spotifyUrl: 'https://open.spotify.com/track/junk',
        popularity: 96,
      ),
    ]);
    final service = LiveTrackCatalogService(platformSearch: platform);

    final tracks = await service.fetchTrendingTracks(region: 'Global');

    expect(tracks, hasLength(1));
    expect(tracks.map((track) => track.title), contains('Chart Anchored'));
    expect(
      tracks.map((track) => track.title),
      isNot(contains('Best Music Songs Result')),
    );
  });

  test('fetchTrendingTracks accepts Soundcharts region lists', () async {
    final platform = _FakePlatformSearchService([
      const PlatformTrackResult(
        title: 'Lagos to Accra',
        artist: 'Regional Artist',
        soundchartsUrl: 'https://soundcharts.com/song/regional',
        soundchartsRegions: ['NG', 'GH'],
        popularity: 80,
      ),
    ]);
    final service = LiveTrackCatalogService(platformSearch: platform);

    final tracks = await service.fetchTrendingTracks(region: 'GH');

    expect(tracks, hasLength(1));
    expect(tracks.single.regionScores, containsPair('GH', 0.8));
  });

  test(
    'fetchTrendingTracks accepts Spotify chart evidence for its region',
    () async {
      final platform = _FakePlatformSearchService([
        const PlatformTrackResult(
          title: 'US Spotify Hit',
          artist: 'Chart Artist',
          spotifyUrl: 'https://open.spotify.com/track/us-hit',
          spotifyChartRegion: 'US',
          spotifyChartRank: 2,
          popularity: 99,
        ),
      ]);
      final service = LiveTrackCatalogService(platformSearch: platform);

      final tracks = await service.fetchTrendingTracks(region: 'US');

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'US Spotify Hit');
      expect(tracks.single.sources, contains('spotify'));
    },
  );

  test(
    'fetchTrendingTracks does not treat global Spotify as local evidence',
    () async {
      final platform = _FakePlatformSearchService([
        const PlatformTrackResult(
          title: 'Global Spotify Hit',
          artist: 'World Artist',
          spotifyUrl: 'https://open.spotify.com/track/global-hit',
          spotifyChartRegion: 'GLOBAL',
          spotifyChartRank: 1,
          popularity: 100,
        ),
      ]);
      final service = LiveTrackCatalogService(platformSearch: platform);

      final tracks = await service.fetchTrendingTracks(region: 'GH');

      expect(tracks, isEmpty);
    },
  );

  test('fetchTrendingTracks forwards the selected genre lane', () async {
    final platform = _FakePlatformSearchService([
      const PlatformTrackResult(
        title: 'House Cut',
        artist: 'DJ House',
        appleUrl: 'https://music.apple.com/us/song/house-cut',
        appleChartRank: 8,
        spotifyUrl: 'https://open.spotify.com/track/house',
        genre: 'House',
        popularity: 70,
      ),
    ]);
    final service = LiveTrackCatalogService(platformSearch: platform);

    final tracks = await service.fetchTrendingTracks(
      region: 'US',
      genre: 'House',
    );

    expect(platform.seenGenre, 'House');
    expect(tracks.single.genre, 'House');
  });
}
