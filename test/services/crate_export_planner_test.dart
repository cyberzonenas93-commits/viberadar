import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate_track.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/crate_export_planner.dart';

Track _track({
  required String id,
  required String title,
  required String artist,
  int bpm = 0,
  String key = '--',
  Map<String, String> links = const {},
  String art = '',
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Track(
    id: id,
    title: title,
    artist: artist,
    artworkUrl: art,
    bpm: bpm,
    keySignature: key,
    genre: 'Open Format',
    vibe: 'club',
    trendScore: 0,
    regionScores: const {},
    platformLinks: links,
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
  );
}

LibraryTrack _lib({
  required String path,
  required String title,
  required String artist,
  double bpm = 120,
}) {
  return LibraryTrack(
    id: path,
    filePath: path,
    fileName: '$artist - $title.mp3',
    title: title,
    artist: artist,
    album: '',
    genre: '',
    bpm: bpm,
    key: '8A',
    durationSeconds: 200,
    fileSizeBytes: 8000000,
    fileExtension: '.mp3',
    md5Hash: '',
    bitrate: 320,
    sampleRate: 44100,
  );
}

void main() {
  group('crateTrackFromTrack', () {
    test('captures metadata + platform links so the entry is self-contained', () {
      final t = _track(
        id: 'sha1id',
        title: 'Essence',
        artist: 'Wizkid',
        bpm: 104,
        key: '8A',
        links: {'spotify': 'sp', 'apple': 'ap', 'youtube': 'yt'},
        art: 'art',
      );
      final ct = crateTrackFromTrack(t);
      expect(ct.trackId, 'sha1id');
      expect(ct.title, 'Essence');
      expect(ct.artist, 'Wizkid');
      expect(ct.bpm, 104);
      expect(ct.key, '8A');
      expect(ct.spotifyUrl, 'sp');
      expect(ct.appleUrl, 'ap');
      expect(ct.youtubeUrl, 'yt');
      expect(ct.artworkUrl, 'art');
      // Carries an id (stable) AND metadata (decay-proof) → not a bare reference.
      expect(ct.isReference, false);
      expect(ct.stableKey, 'sha1id');
    });
  });

  group('resolveCrateTracks', () {
    test('rich entry is used directly even when absent from the live feed', () {
      const rich = CrateTrack(
        title: 'Local Banger',
        artist: 'Underground',
        bpm: 126,
        spotifyUrl: 'sp',
      );
      final r = resolveCrateTracks([rich], const [], now: DateTime.utc(2026));
      expect(r.tracks.length, 1);
      expect(r.tracks.first.title, 'Local Banger');
      expect(r.tracks.first.artist, 'Underground');
      expect(r.tracks.first.bpm, 126);
      expect(r.tracks.first.platformLinks['spotify'], 'sp');
      expect(r.droppedReferences, 0);
    });

    test('reference entry is enriched from the live feed', () {
      final live = _track(id: 'live1', title: 'Calm Down', artist: 'Rema');
      final r = resolveCrateTracks(
        [CrateTrack.reference('live1')],
        [live],
        now: DateTime.utc(2026),
      );
      expect(r.tracks.length, 1);
      expect(r.tracks.first.id, 'live1');
      expect(r.tracks.first.title, 'Calm Down');
      expect(r.droppedReferences, 0);
    });

    test('reference with no live match is dropped and counted', () {
      final r = resolveCrateTracks(
        [CrateTrack.reference('decayed')],
        const [],
        now: DateTime.utc(2026),
      );
      expect(r.tracks, isEmpty);
      expect(r.droppedReferences, 1);
    });
  });

  group('exportStudioId', () {
    test(
      'encodes title/artist so the Export Studio can resolve it locally',
      () {
        final t = _track(id: 'x', title: 'Essence', artist: 'Wizkid');
        expect(exportStudioId(t), 'vibe:Essence:Wizkid');
      },
    );

    test('strips colons so the ":"-delimited decode stays aligned', () {
      final t = _track(id: 'x', title: 'Intro: Part 1', artist: 'DJ: X');
      expect(exportStudioId(t), 'vibe:Intro Part 1:DJ X');
    });
  });

  group('planLocalExport', () {
    test('splits tracks into matched local files and missing labels', () async {
      final library = [
        _lib(
          path: '/music/Wizkid - Essence.mp3',
          title: 'Essence',
          artist: 'Wizkid',
        ),
      ];
      final tracks = [
        _track(id: 'a', title: 'Essence', artist: 'Wizkid'),
        _track(id: 'b', title: 'Not Owned', artist: 'Someone'),
      ];
      final plan = await planLocalExport(tracks: tracks, library: library);
      expect(plan.matched.length, 1);
      expect(plan.matched.first.filePath, '/music/Wizkid - Essence.mp3');
      expect(plan.missing, ['Someone - Not Owned']);
      expect(plan.total, 2);
    });
  });
}
