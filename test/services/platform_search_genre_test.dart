import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viberadar/core/config/music_genres.dart';
import 'package:viberadar/services/apple_music_artist_service.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/spotify_artist_service.dart';
import 'package:viberadar/services/youtube_search_service.dart';

class _CapturingSpotify extends SpotifyArtistService {
  _CapturingSpotify(this.build);

  final List<SpotifyTrackInfo> Function(String query) build;
  final List<String> queries = [];
  String? lastMarket;

  @override
  Future<List<SpotifyTrackInfo>> searchTracks(
    String query, {
    int limit = 20,
    String market = 'US',
  }) async {
    queries.add(query);
    lastMarket = market;
    return build(query);
  }
}

class _CapturingApple extends AppleMusicArtistService {
  _CapturingApple({this.charts = const []});

  final List<AppleMusicTrack> charts;

  @override
  Future<List<AppleMusicTrack>> searchSongs(
    String query, {
    int limit = 20,
    String? region,
  }) async => const [];

  @override
  Future<List<AppleMusicTrack>> getChartSongs({
    int limit = 50,
    String? region,
  }) async => charts;
}

class _EmptyYoutube extends YoutubeSearchService {
  @override
  Future<List<YoutubeVideoResult>> searchMusic(
    String query, {
    int limit = 15,
  }) async => const [];

  @override
  Future<List<YoutubeVideoResult>> fetchTrendingMusic({
    int limit = 20,
    String? region,
  }) async => const [];
}

http.Client _emptyDeezer() =>
    MockClient((_) async => http.Response('{"data": []}', 200));

SpotifyTrackInfo _spotify(String name, String artist, {int popularity = 50}) {
  return SpotifyTrackInfo(
    id: '$name-$artist',
    name: name,
    artists: artist,
    durationMs: 180000,
    spotifyUrl: 'https://open.spotify.com/track/${name.hashCode}',
    albumName: name,
    albumArt: 'https://i.scdn.co/image/${name.hashCode}',
    popularity: popularity,
  );
}

AppleMusicTrack _appleChart(String name, String artist, String genre) {
  return AppleMusicTrack(
    id: '$name-$artist',
    name: name,
    albumName: name,
    artistName: artist,
    appleUrl: 'https://music.apple.com/us/song/${name.hashCode}',
    artworkUrl: 'https://is1-ssl.mzstatic.com/image/${name.hashCode}',
    durationMs: 180000,
    genreNames: [genre],
  );
}

void main() {
  test(
    'genre-aware trending drives platform queries with the selected lane',
    () async {
      final spotify = _CapturingSpotify(
        (_) => [_spotify('House Banger', 'DJ A', popularity: 60)],
      );
      final apple = _CapturingApple(
        charts: [_appleChart('House Banger', 'DJ A', 'House')],
      );
      final service = PlatformSearchService(
        spotify: spotify,
        apple: apple,
        youtube: _EmptyYoutube(),
        httpClient: _emptyDeezer(),
      );

      final results = await service.fetchTrendingChartTracks(
        region: 'US',
        genre: 'House',
      );

      // The lane reached the live query (not a generic "US hits").
      expect(
        spotify.queries.any((q) => q.toLowerCase().contains('house')),
        isTrue,
        reason: 'Spotify query should be genre-scoped: ${spotify.queries}',
      );
      // A genre-discovered streaming row is stamped with the lane so the
      // downstream genre filter keeps it instead of discarding it as unknown.
      final row = results.firstWhere((r) => r.title == 'House Banger');
      expect(genreMatches(row.genre, 'House'), isTrue);
    },
  );

  test('a specific genre gates out a known off-genre chart hit', () async {
    final spotify = _CapturingSpotify(
      (_) => [_spotify('House Anthem', 'DJ C', popularity: 50)],
    );
    final apple = _CapturingApple(
      charts: [
        _appleChart('House Anthem', 'DJ C', 'House'),
        _appleChart('Country Number One', 'Singer B', 'Country'),
      ],
    );
    final service = PlatformSearchService(
      spotify: spotify,
      apple: apple,
      youtube: _EmptyYoutube(),
      httpClient: _emptyDeezer(),
    );

    final results = await service.fetchTrendingChartTracks(
      region: 'US',
      genre: 'House',
    );

    final titles = results.map((r) => r.title).toList();
    expect(
      titles,
      contains('House Anthem'),
      reason: 'genre-fit row must survive',
    );
    expect(
      titles,
      isNot(contains('Country Number One')),
      reason: 'a #1 Country chart hit must not pollute House results',
    );
  });

  test(
    'genre-blind trending keeps chart hits (no regression when genre is All)',
    () async {
      final spotify = _CapturingSpotify((_) => const []);
      final apple = _CapturingApple(
        charts: [_appleChart('Country Number One', 'Singer B', 'Country')],
      );
      final service = PlatformSearchService(
        spotify: spotify,
        apple: apple,
        youtube: _EmptyYoutube(),
        httpClient: _emptyDeezer(),
      );

      final results = await service.fetchTrendingChartTracks(region: 'US');

      expect(results.map((r) => r.title), contains('Country Number One'));
    },
  );

  test(
    'spotify chart rows anchor trending but search-only rows do not',
    () async {
      final spotify = _CapturingSpotify(
        (_) => [
          _spotify('Spotify Chart Hit', 'Chart Artist', popularity: 80),
          _spotify('Search Only Result', 'Noise Artist', popularity: 99),
        ],
      );
      final httpClient = MockClient((request) async {
        if (request.url.host == 'kworb.net') {
          return http.Response('''
<table id="spotifydaily"><tbody>
<tr><td class="np">1</td><td class="np">=</td><td class="text mp"><div><a href="../artist/chart.html">Chart Artist</a> - <a href="../track/spotify-chart-hit.html">Spotify Chart Hit</a></div></td></tr>
<tr><td class="np">2</td><td class="np">=</td><td class="text mp"><div><a href="../artist/junk.html">Loop Maker</a> - <a href="../track/instrumental.html">Instrumental Loop</a></div></td></tr>
</tbody></table>
''', 200);
        }
        return http.Response('{"data": []}', 200);
      });
      final service = PlatformSearchService(
        spotify: spotify,
        apple: _CapturingApple(),
        youtube: _EmptyYoutube(),
        httpClient: httpClient,
      );

      final results = await service.fetchTrendingChartTracks(region: 'US');
      final titles = results.map((r) => r.title).toList();

      expect(titles, contains('Spotify Chart Hit'));
      expect(titles, isNot(contains('Search Only Result')));
      expect(titles, isNot(contains('Instrumental Loop')));

      final chartHit = results.firstWhere(
        (r) => r.title == 'Spotify Chart Hit',
      );
      expect(chartHit.spotifyChartRank, 1);
      expect(chartHit.spotifyChartRegion, 'US');
      expect(chartHit.hasTrustedTrendEvidence, isTrue);
      expect(chartHit.hasChartEvidenceForRegion('US'), isTrue);
    },
  );
}
