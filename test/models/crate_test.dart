import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/crate_track.dart';

Crate _crate(List<CrateTrack> tracks) => Crate(
  id: 'c1',
  name: 'Set',
  context: 'AI set',
  tracks: tracks,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  test('legacy track_ids map to reference entries', () {
    final c = Crate.fromMap({
      'id': 'c1',
      'name': 'Old',
      'context': 'x',
      'track_ids': ['a', 'b'],
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    expect(c.tracks.length, 2);
    expect(c.tracks.first.trackId, 'a');
    expect(c.tracks.first.isReference, true);
  });

  test('new rich tracks array round-trips', () {
    final c = _crate([
      const CrateTrack(title: 'Essence', artist: 'Wizkid', spotifyUrl: 'sp'),
    ]);
    final back = Crate.fromMap(c.toMap());
    expect(back.tracks.single.title, 'Essence');
    expect(back.tracks.single.spotifyUrl, 'sp');
  });

  test('toMap mirrors track_ids for legacy/desktop readers', () {
    final map = _crate([
      const CrateTrack(trackId: 'realId', title: 'T', artist: 'A'),
      const CrateTrack(title: 'Essence', artist: 'Wizkid'),
    ]).toMap();
    expect(map['track_ids'], ['realId', 'wizkid|essence']);
  });

  test('trackIds getter stays available for read-only consumers', () {
    final c = _crate([CrateTrack.reference('z')]);
    expect(c.trackIds, ['z']);
  });
}
