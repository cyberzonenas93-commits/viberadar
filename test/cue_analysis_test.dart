import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/cue_analysis_service.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

LibraryTrack _track({
  String id          = 'track-1',
  String title       = 'Test Track',
  String artist      = 'Test Artist',
  double bpm         = 128.0,
  double duration    = 360.0, // 6 minutes
  String genre       = 'House',
  String key         = '8A',
}) {
  return LibraryTrack(
    id:              id,
    title:           title,
    artist:          artist,
    filePath:        '/music/$title.mp3',
    fileName:        '$title.mp3',
    bpm:             bpm,
    durationSeconds: duration,
    genre:           genre,
    key:             key,
    album:           '',
    year:            2023,
    fileSizeBytes:   10000000,
    fileExtension:   '.mp3',
    md5Hash:         'abc123',
    bitrate:         320,
    sampleRate:      44100,
  );
}

void main() {
  final service = CueAnalysisService();

  group('CueAnalysisService — genre classification & candidate generation', () {

    test('House track produces intro, mix-in, drop, mix-out cues', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'House', bpm: 128, duration: 360), useAi: false);

      expect(result.cues, isNotEmpty);
      final types = result.cues.map((c) => c.cueType).toSet();
      expect(types, contains(CueType.intro));
      expect(types, contains(CueType.mixIn));
      expect(types, contains(CueType.drop));
    });

    test('Amapiano track produces log drum mix-in cue', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'Amapiano', bpm: 113, duration: 300), useAi: false);

      final cueTypes = result.cues.map((c) => c.cueType).toSet();
      expect(cueTypes, contains(CueType.intro));
      expect(cueTypes, contains(CueType.mixIn));
      expect(result.cues.any((c) => c.notes?.contains('log drum') == true), isTrue);
    });

    test('Afrobeats track produces vocal-in cue', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'Afrobeats', bpm: 105, duration: 240), useAi: false);

      expect(result.cues.any((c) => c.cueType == CueType.vocalIn), isTrue);
    });

    test('Hip-hop track produces hook and verse cues', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'Hip-Hop', bpm: 90, duration: 200), useAi: false);

      final types = result.cues.map((c) => c.cueType).toSet();
      expect(types, contains(CueType.hook));
      expect(types, contains(CueType.vocalIn));
    });

    test('Unknown genre with no BPM produces duration-based cues', () async {
      final result = await service.analyzeTrack(
          _track(genre: '', bpm: 0, duration: 240), useAi: false);

      expect(result.cues, isNotEmpty);
      expect(result.warning, contains('No BPM'));
      expect(result.hasWeakConfidence, isTrue);
    });
  });

  group('CueAnalysisService — timing correctness', () {

    test('Intro cue is always at time 0', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      final intro = result.cues.firstWhere((c) => c.cueType == CueType.intro);
      expect(intro.timeSeconds, equals(0.0));
    });

    test('Cues are sorted chronologically', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      for (var i = 1; i < result.cues.length; i++) {
        expect(result.cues[i].timeSeconds,
            greaterThan(result.cues[i - 1].timeSeconds));
      }
    });

    test('No cue exceeds track duration', () async {
      const dur = 240.0;
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: dur), useAi: false);
      for (final c in result.cues) {
        expect(c.timeSeconds, lessThan(dur),
            reason: 'Cue ${c.label} at ${c.timeSeconds}s exceeds duration ${dur}s');
      }
    });

    test('No two cues within 3 seconds of each other', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      for (var i = 1; i < result.cues.length; i++) {
        final gap = result.cues[i].timeSeconds - result.cues[i - 1].timeSeconds;
        expect(gap, greaterThanOrEqualTo(3.0),
            reason: 'Cues too close: ${result.cues[i - 1].label} & ${result.cues[i].label}');
      }
    });

    test('House mix-in at ~8 bars (at 128 BPM ≈ 15s)', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'House', bpm: 128, duration: 360), useAi: false);
      final mixIn = result.cues.firstWhere((c) => c.cueType == CueType.mixIn);
      // 8 bars at 128 BPM: 60/128 * 4 * 8 ≈ 15.0 s
      expect(mixIn.timeSeconds, closeTo(15.0, 1.0));
    });
  });

  group('CueAnalysisService — slot assignment', () {

    test('Cue indexes are sequential starting from 0', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      for (var i = 0; i < result.cues.length; i++) {
        expect(result.cues[i].cueIndex, equals(i));
      }
    });

    test('Maximum 8 cues generated (VirtualDJ slot limit)', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 600), useAi: false);
      expect(result.cues.length, lessThanOrEqualTo(8));
    });
  });

  group('CueAnalysisService — confidence', () {

    test('Confidence between 0 and 1 for all cues', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      for (final c in result.cues) {
        expect(c.confidence, inInclusiveRange(0.0, 1.0));
      }
    });

    test('Known BPM yields higher confidence than zero BPM', () async {
      final withBpm    = await service.analyzeTrack(
          _track(bpm: 128, duration: 300), useAi: false);
      final withoutBpm = await service.analyzeTrack(
          _track(bpm: 0, duration: 300), useAi: false);
      final avgWith    = withBpm.cues.map((c) => c.confidence).reduce((a, b) => a + b)
          / withBpm.cues.length;
      final avgWithout = withoutBpm.cues.map((c) => c.confidence).reduce((a, b) => a + b)
          / withoutBpm.cues.length;
      expect(avgWith, greaterThan(avgWithout));
    });

    test('hasWeakConfidence is false when BPM and genre are known', () async {
      final result = await service.analyzeTrack(
          _track(genre: 'House', bpm: 128, duration: 360), useAi: false);
      expect(result.hasWeakConfidence, isFalse);
    });
  });

  group('CueAnalysisService — batch', () {

    test('analyzeBatch processes all tracks', () async {
      final tracks = [
        _track(id: 't1', genre: 'House', bpm: 128, duration: 360),
        _track(id: 't2', genre: 'Afrobeats', bpm: 105, duration: 240),
        _track(id: 't3', genre: 'Hip-Hop', bpm: 85, duration: 200),
      ];
      final results = await service.analyzeBatch(tracks, useAi: false);
      expect(results.length, equals(3));
      expect(results.map((r) => r.trackId).toSet(),
          containsAll(['t1', 't2', 't3']));
    });

    test('Progress callback is called for each track', () async {
      final tracks = List.generate(3, (i) => _track(id: 'track-$i'));
      final progresses = <int>[];
      await service.analyzeBatch(tracks, useAi: false,
          onProgress: (done, total) => progresses.add(done));
      expect(progresses, equals([1, 2, 3]));
    });
  });

  group('CueAnalysisService — serialization', () {

    test('HotCue round-trips through JSON', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      for (final c in result.cues) {
        final json = c.toJson();
        final restored = HotCue.fromJson(json);
        expect(restored.id,          equals(c.id));
        expect(restored.cueType,     equals(c.cueType));
        expect(restored.timeSeconds, equals(c.timeSeconds));
        expect(restored.confidence,  equals(c.confidence));
      }
    });

    test('CueGenerationResult round-trips through JSON', () async {
      final result = await service.analyzeTrack(
          _track(bpm: 128, duration: 360), useAi: false);
      final json     = result.toJson();
      final restored = CueGenerationResult.fromJson(json);
      expect(restored.trackId,    equals(result.trackId));
      expect(restored.cues.length, equals(result.cues.length));
    });
  });
}
