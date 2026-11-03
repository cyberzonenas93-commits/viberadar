import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/set_resolution_service.dart';

class _Calls {
  int spotify = 0, apple = 0, youtube = 0;
}

Track _lib(String id, String title, String artist) => Track(
  id: id,
  title: title,
  artist: artist,
  artworkUrl: 'art',
  bpm: 100,
  keySignature: '8A',
  genre: 'Afrobeats',
  vibe: 'Warm',
  trendScore: 0.5,
  regionScores: const {},
  platformLinks: const {'spotify': 'sp-lib'},
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  energyLevel: 0.5,
  trendHistory: const [],
  sources: const [],
);

void main() {
  test('local library match wins and makes no platform calls', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async {
        calls.spotify++;
        return null;
      },
      searchApple: (q) async {
        calls.apple++;
        return null;
      },
      searchYoutube: (q) async {
        calls.youtube++;
        return null;
      },
    );
    final out = await svc.resolve(
      [(title: 'Essence', artist: 'Wizkid', bpm: 0, key: '')],
      library: [_lib('realId', 'Essence', 'Wizkid')],
    );
    expect(out.single.trackId, 'realId');
    expect(out.single.spotifyUrl, 'sp-lib');
    expect(calls.spotify, 0);
    expect(calls.apple, 0);
    expect(calls.youtube, 0);
  });

  test('youtube only called when spotify and apple miss', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async {
        calls.spotify++;
        return null;
      },
      searchApple: (q) async {
        calls.apple++;
        return null;
      },
      searchYoutube: (q) async {
        calls.youtube++;
        return (url: 'yt', art: 'yart');
      },
    );
    final out = await svc.resolve([
      (title: 'Deep Cut', artist: 'Nobody', bpm: 0, key: ''),
    ], library: const []);
    expect(out.single.youtubeUrl, 'yt');
    expect(calls.spotify, 1);
    expect(calls.apple, 1);
    expect(calls.youtube, 1);
  });

  test('spotify hit short-circuits before apple/youtube', () async {
    final calls = _Calls();
    final svc = SetResolutionService.test(
      searchSpotify: (q) async {
        calls.spotify++;
        return (url: 'sp', art: 'a');
      },
      searchApple: (q) async {
        calls.apple++;
        return null;
      },
      searchYoutube: (q) async {
        calls.youtube++;
        return null;
      },
    );
    final out = await svc.resolve([
      (title: 'Hit', artist: 'Star', bpm: 0, key: ''),
    ], library: const []);
    expect(out.single.spotifyUrl, 'sp');
    expect(calls.apple, 0);
    expect(calls.youtube, 0);
  });
}
