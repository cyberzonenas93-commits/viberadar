import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/duplicate_detector_service.dart';

LibraryTrack _track({
  required String id,
  required String title,
  required String artist,
  String fileName = 'track.mp3',
  String md5Hash = 'abc123',
}) =>
    LibraryTrack(
      id: id,
      filePath: '/music/$fileName',
      fileName: fileName,
      title: title,
      artist: artist,
      album: 'Album',
      genre: 'House',
      bpm: 128,
      key: '1A',
      durationSeconds: 360,
      fileSizeBytes: 10000000,
      fileExtension: '.mp3',
      md5Hash: md5Hash,
      bitrate: 320,
      sampleRate: 44100,
    );

void main() {
  late DuplicateDetectorService svc;

  setUp(() => svc = DuplicateDetectorService());

  group('Exact MD5 match', () {
    test('two tracks with identical MD5 form one duplicate group', () {
      final t1 = _track(id: '1', title: 'Song A', artist: 'Artist A', md5Hash: 'aaa');
      final t2 = _track(id: '2', title: 'Song A copy', artist: 'Artist A', md5Hash: 'aaa');
      final t3 = _track(id: '3', title: 'Song B', artist: 'Artist B', md5Hash: 'bbb');

      final groups = svc.findDuplicates([t1, t2, t3]);

      expect(groups.length, 1);
      expect(groups.first.reason, 'exact_hash');
      expect(groups.first.tracks.map((t) => t.id), containsAll(['1', '2']));
    });

    test('three tracks with the same hash form one group with all three', () {
      final tracks = List.generate(
        3,
        (i) => _track(id: '$i', title: 'Same', artist: 'X', md5Hash: 'same'),
      );
      final groups = svc.findDuplicates(tracks);

      expect(groups.length, 1);
      expect(groups.first.tracks.length, 3);
    });

    test('unique hashes produce no groups', () {
      final tracks = List.generate(
        5,
        (i) => _track(id: '$i', title: 'Track $i', artist: 'A', md5Hash: 'hash$i'),
      );
      expect(svc.findDuplicates(tracks), isEmpty);
    });
  });

  group('Title + artist match', () {
    test('same title/artist with different hashes form a title_artist group', () {
      final t1 = _track(id: '1', title: 'Burna Boy - Last Last', artist: 'Burna Boy',
          md5Hash: 'h1', fileName: 'burna_v1.mp3');
      final t2 = _track(id: '2', title: 'Burna Boy - Last Last', artist: 'Burna Boy',
          md5Hash: 'h2', fileName: 'burna_v2.mp3');

      final groups = svc.findDuplicates([t1, t2]);

      expect(groups.length, 1);
      expect(groups.first.reason, 'same_title_artist');
    });

    test('different artists with same title are NOT duplicates', () {
      final t1 = _track(id: '1', title: 'Last Last', artist: 'Burna Boy', md5Hash: 'h1');
      final t2 = _track(id: '2', title: 'Last Last', artist: 'Another Artist', md5Hash: 'h2');

      expect(svc.findDuplicates([t1, t2]), isEmpty);
    });

    test('title matching is case-insensitive and ignores punctuation', () {
      final t1 = _track(id: '1', title: 'On The Floor!', artist: 'J.Lo', md5Hash: 'h1');
      final t2 = _track(id: '2', title: 'on the floor', artist: 'J.Lo', md5Hash: 'h2');

      final groups = svc.findDuplicates([t1, t2]);
      expect(groups.length, 1);
    });
  });

  group('Fuzzy filename match', () {
    test('filenames with Levenshtein distance <= 4 are grouped', () {
      final t1 = _track(id: '1', title: 'A', artist: 'X', md5Hash: 'h1',
          fileName: 'wizkid_essence.mp3');
      final t2 = _track(id: '2', title: 'B', artist: 'Y', md5Hash: 'h2',
          fileName: 'wizkid_essenc.mp3'); // 1 char shorter

      final groups = svc.findDuplicates([t1, t2]);
      expect(groups.length, 1);
      expect(groups.first.reason, 'similar_name');
    });

    test('filenames with Levenshtein distance > 4 are NOT grouped', () {
      final t1 = _track(id: '1', title: 'A', artist: 'X', md5Hash: 'h1',
          fileName: 'track_alpha.mp3');
      final t2 = _track(id: '2', title: 'B', artist: 'Y', md5Hash: 'h2',
          fileName: 'track_zeta_remix.mp3');

      expect(svc.findDuplicates([t1, t2]), isEmpty);
    });
  });

  group('Edge cases', () {
    test('empty list returns empty', () {
      expect(svc.findDuplicates([]), isEmpty);
    });

    test('single track returns empty', () {
      expect(svc.findDuplicates([_track(id: '1', title: 'A', artist: 'B')]), isEmpty);
    });

    test('exact-hash duplicates are not double-counted in title/artist pass', () {
      final t1 = _track(id: '1', title: 'Same', artist: 'Same', md5Hash: 'x');
      final t2 = _track(id: '2', title: 'Same', artist: 'Same', md5Hash: 'x');
      final groups = svc.findDuplicates([t1, t2]);
      // Should be only 1 group (exact_hash), not 2
      expect(groups.length, 1);
      expect(groups.first.reason, 'exact_hash');
    });
  });
}
