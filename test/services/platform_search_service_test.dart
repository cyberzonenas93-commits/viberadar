import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:viberadar/services/apple_music_artist_service.dart';
import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/services/spotify_artist_service.dart';
import 'package:viberadar/services/youtube_search_service.dart';

class _FakeSpotifyService extends SpotifyArtistService {
  @override
  Future<List<SpotifyTrackInfo>> searchTracks(
    String query, {
    int limit = 20,
    String market = 'US',
  }) async {
    return [
      SpotifyTrackInfo(
        id: 'sp-market-heat',
        name: 'Market Heat',
        artists: 'Accra Artist',
        durationMs: 198000,
        spotifyUrl: 'https://open.spotify.com/track/market-heat',
        albumName: 'Market Heat',
        albumArt: 'https://i.scdn.co/image/market-heat',
        popularity: 88,
      ),
    ];
  }
}

class _FakeAppleService extends AppleMusicArtistService {
  @override
  Future<List<AppleMusicTrack>> searchSongs(
    String query, {
    int limit = 20,
    String? region,
  }) async {
    return const [
      AppleMusicTrack(
        id: 'apple-market-heat',
        name: 'Market Heat',
        albumName: 'Market Heat',
        artistName: 'Accra Artist',
        appleUrl: 'https://music.apple.com/gh/song/market-heat',
        artworkUrl: 'https://is1-ssl.mzstatic.com/image/market-heat',
        durationMs: 198000,
        genreNames: ['Afrobeats'],
      ),
    ];
  }
}

class _FakeYoutubeService extends YoutubeSearchService {
  @override
  Future<List<YoutubeVideoResult>> searchMusic(
    String query, {
    int limit = 15,
  }) async {
    return const [
      YoutubeVideoResult(
        videoId: 'yt-market-heat',
        title: 'Accra Artist - Market Heat (Official Audio)',
        channelName: 'Accra Artist',
        youtubeUrl: 'https://www.youtube.com/watch?v=yt-market-heat',
      ),
    ];
  }
}

void main() {
  test('searchMusicPlatforms returns only playback-platform sources', () async {
    final httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'data': [
            {
              'title_short': 'Market Heat',
              'artist': {'name': 'Accra Artist'},
              'album': {
                'cover_medium': 'https://e-cdns-images.dzcdn.net/market',
              },
              'link': 'https://www.deezer.com/track/market-heat',
              'duration': 198,
              'rank': 900000,
            },
          ],
        }),
        200,
      );
    });
    final service = PlatformSearchService(
      spotify: _FakeSpotifyService(),
      apple: _FakeAppleService(),
      youtube: _FakeYoutubeService(),
      httpClient: httpClient,
    );

    final results = await service.searchMusicPlatforms('market heat');
    final result = results.firstWhere((row) => row.title == 'Market Heat');

    expect(result.spotifyUrl, 'https://open.spotify.com/track/market-heat');
    expect(result.appleUrl, 'https://music.apple.com/gh/song/market-heat');
    expect(result.deezerUrl, 'https://www.deezer.com/track/market-heat');
    expect(result.soundchartsUrl, isNull);
    expect(result.soundchartsSource, isNull);
  });

  test(
    'enrichPlaybackLinksForResults restores music-platform play links',
    () async {
      final httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'title_short': 'Market Heat',
                'artist': {'name': 'Accra Artist'},
                'album': {
                  'cover_medium': 'https://e-cdns-images.dzcdn.net/market',
                },
                'link': 'https://www.deezer.com/track/market-heat',
                'duration': 198,
                'rank': 900000,
              },
            ],
          }),
          200,
        );
      });
      final service = PlatformSearchService(
        spotify: _FakeSpotifyService(),
        apple: _FakeAppleService(),
        youtube: _FakeYoutubeService(),
        httpClient: httpClient,
      );

      final enriched = await service.enrichPlaybackLinksForResults(const [
        PlatformTrackResult(
          title: 'Market Heat',
          artist: 'Accra Artist',
          soundchartsUrl: 'https://soundcharts.com/song/market-heat',
          soundchartsSource: 'Shazam',
          soundchartsRegion: 'GH',
          popularity: 70,
        ),
      ], region: 'GH');

      final result = enriched.single;
      expect(result.soundchartsUrl, 'https://soundcharts.com/song/market-heat');
      expect(result.spotifyUrl, 'https://open.spotify.com/track/market-heat');
      expect(result.appleUrl, 'https://music.apple.com/gh/song/market-heat');
      expect(
        result.youtubeUrl,
        'https://www.youtube.com/watch?v=yt-market-heat',
      );
      expect(result.deezerUrl, 'https://www.deezer.com/track/market-heat');
      expect(result.bestUrl, result.appleUrl);
    },
  );
}
