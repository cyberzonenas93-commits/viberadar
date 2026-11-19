import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate_track.dart';
import 'package:viberadar/providers/setlist_provider.dart';

void main() {
  test('mergeTracks appends new entries and dedupes by stableKey', () {
    final existing = [
      const CrateTrack(trackId: 'a', title: '', artist: ''),
      const CrateTrack(title: 'Essence', artist: 'Wizkid'),
    ];
    final incoming = [
      const CrateTrack(title: 'Essence', artist: 'Wizkid'), // dup by key
      const CrateTrack(title: 'Calm Down', artist: 'Rema'), // new
    ];
    final merged = mergeTracks(existing, incoming);
    expect(merged.length, 3);
    expect(merged.last.title, 'Calm Down');
  });
}
