import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate_track.dart';

void main() {
  test('round-trips through toMap/fromMap', () {
    const t = CrateTrack(
      trackId: 'abc123',
      title: 'Essence',
      artist: 'Wizkid',
      bpm: 104,
      key: '8A',
      spotifyUrl: 'https://sp/1',
      artworkUrl: 'https://art/1',
    );
    final back = CrateTrack.fromMap(t.toMap());
    expect(back.trackId, 'abc123');
    expect(back.title, 'Essence');
    expect(back.artist, 'Wizkid');
    expect(back.bpm, 104);
    expect(back.key, '8A');
    expect(back.spotifyUrl, 'https://sp/1');
    expect(back.artworkUrl, 'https://art/1');
  });

  test('bestUrl prefers spotify, then apple, then youtube', () {
    expect(
      const CrateTrack(
        title: 't',
        artist: 'a',
        appleUrl: 'ap',
        youtubeUrl: 'yt',
      ).bestUrl,
      'ap',
    );
    expect(
      const CrateTrack(title: 't', artist: 'a', youtubeUrl: 'yt').bestUrl,
      'yt',
    );
    expect(const CrateTrack(title: 't', artist: 'a').hasUrl, false);
  });

  test('stableKey uses trackId when present, else artist|title lowercased', () {
    expect(
      const CrateTrack(trackId: 'id1', title: 'T', artist: 'A').stableKey,
      'id1',
    );
    expect(
      const CrateTrack(title: 'Essence', artist: 'Wizkid').stableKey,
      'wizkid|essence',
    );
  });

  test('reference factory builds an id-only entry', () {
    final r = CrateTrack.reference('xyz');
    expect(r.trackId, 'xyz');
    expect(r.title, '');
    expect(r.artist, '');
    expect(r.isReference, true);
  });
}
