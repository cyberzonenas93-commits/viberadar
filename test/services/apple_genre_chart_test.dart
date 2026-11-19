import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:viberadar/services/apple_music_artist_service.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/spotify_artist_service.dart';
import 'package:viberadar/services/youtube_search_service.dart';

/// Records the genre-chart call and returns canned chart rows; everything else
/// is empty so the genre chart is unambiguously the source under test.
class _FakeApple extends AppleMusicArtistService {
  _FakeApple(this.genreChart);

  final List<AppleMusicTrack> genreChart;
  int? seenGenreId;
  String? seenRegion;
  List<String> seenPreferred = const [];

  @override
  Future<List<AppleMusicTrack>> getGenreChartSongs({
    required int genreId,
    int limit = 100,
    String? region,
    List<String> preferredStorefronts = const [],
  }) async {
    seenGenreId = genreId;
    seenRegion = region;
    seenPreferred = preferredStorefronts;
    return genreChart;
  }

  @override
  Future<List<AppleMusicTrack>> searchSongs(
    String query, {
    int limit = 20,
    String? region,
  }) async => const [];

  @override
  Future<List<AppleMusicTrack>> getChartSongs({
    int limit = 100,
    String? region,
  }) async => const [];
}

class _EmptySpotify extends SpotifyArtistService {
  @override
  Future<List<SpotifyTrackInfo>> searchTracks(
    String query, {
    int limit = 20,
    String market = 'US',
  }) async => const [];
}

class _EmptyYoutube extends YoutubeSearchService {
  @override
  Future<List<YoutubeVideoResult>> searchMusic(
    String query, {
    int limit = 15,
  }) async => const [];
}

PlatformSearchService _service(_FakeApple apple) => PlatformSearchService(
  apple: apple,
  spotify: _EmptySpotify(),
  youtube: _EmptyYoutube(),
  httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
);

void main() {
  group('appleGenreChartStorefront', () {
    test('a global genre uses the selected region storefront', () {
      expect(appleGenreChartStorefront('ZA', const []), 'za');
      expect(appleGenreChartStorefront('US', const []), 'us');
    });

    test(
      'a regional genre falls back to preferred when the region lacks it',
      () {
        expect(appleGenreChartStorefront('US', const ['ng', 'gh', 'za']), 'ng');
        expect(appleGenreChartStorefront('Global', const ['za', 'ng']), 'za');
      },
    );

    test('a regional genre keeps the selected region when it carries it', () {
      expect(appleGenreChartStorefront('ZA', const ['za', 'ng']), 'za');
      expect(appleGenreChartStorefront('NG', const ['za', 'ng']), 'ng');
    });
  });

  test(
    'fetchTrendingChartTracks sources a mapped genre from Apple genre charts',
    () async {
      final apple = _FakeApple(const [
        AppleMusicTrack(
          id: 'a1',
          name: 'Piano Heat',
          albumName: 'Piano Heat',
          artistName: 'SA Artist',
          appleUrl: 'https://music.apple.com/za/song/piano-heat',
          artworkUrl: 'https://is1-ssl.mzstatic.com/image/piano-heat',
          durationMs: 200000,
          genreNames: ['Amapiano'],
        ),
      ]);

      final results = await _service(
        apple,
      ).fetchTrendingChartTracks(region: 'ZA', genre: 'Amapiano', limit: 20);

      expect(apple.seenGenreId, 42);
      final row = results.firstWhere((r) => r.title == 'Piano Heat');
      expect(row.appleChartRank, isNotNull);
      expect(row.genre, 'Amapiano');
    },
  );

  test(
    'fetchTrendingChartTracks does not call the genre chart for an unmapped lane',
    () async {
      final apple = _FakeApple(const []);

      await _service(
        apple,
      ).fetchTrendingChartTracks(region: 'US', genre: 'Disco', limit: 20);

      expect(apple.seenGenreId, isNull);
    },
  );
}
