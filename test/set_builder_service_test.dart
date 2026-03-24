import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/data/sources/mock_track_seed.dart';
import 'package:viberadar/services/set_builder_service.dart';

void main() {
  test(
    'buildSet returns an ordered shortlist within the requested BPM lane',
    () {
      final service = SetBuilderService();
      final tracks = buildMockTracks();

      final generated = service.buildSet(
        tracks: tracks,
        durationMinutes: 60,
        genre: 'All',
        vibe: 'All',
        minBpm: 110,
        maxBpm: 132,
      );

      expect(generated, isNotEmpty);
      expect(
        generated.every((track) => track.bpm >= 110 && track.bpm <= 132),
        isTrue,
      );
      expect(generated.length, inInclusiveRange(6, 20));
    },
  );
}
