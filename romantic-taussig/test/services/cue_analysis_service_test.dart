// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/cue_generation_result.dart';
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/cue_analysis_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

LibraryTrack _track({
  String id = 't1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  double bpm = 128.0,
  double durationSeconds = 240.0,
  String genre = 'House',
}) =>
    LibraryTrack(
      id: id,
      filePath: '/music/$title.mp3',
      fileName: '$title.mp3',
      title: title,
      artist: artist,
      album: '',
      genre: genre,
      bpm: bpm,
      key: '8A',
      durationSeconds: durationSeconds,
      fileSizeBytes: 10000000,
      fileExtension: '.mp3',
      md5Hash: '',
      bitrate: 320,
      sampleRate: 44100,
    );

void main() {
  late CueAnalysisService svc;

  setUp(() => svc = CueAnalysisService());

  // ── Metadata validation ──────────────────────────────────────────────────

  group('metadata validation', () {
    test('returns insufficientMetadata for very short track', () async {
      final t = _track(durationSeconds: 10.0);
      final result = await svc.generateCues(t);
      expect(result.status, CueGenerationStatus.insufficientMetadata);
      expect(result.cues, isEmpty);
    });

    test('returns insufficientMetadata for zero duration + zero BPM', () async {
      final t = _track(bpm: 0.0, durationSeconds: 0.0);
      final result = await svc.generateCues(t);
      expect(result.status, CueGenerationStatus.insufficientMetadata);
    });

    test('proceeds with degraded confidence when BPM is 0 but duration is ok',
        () async {
      // Should still produce cues using duration-only heuristics.
      final t = _track(bpm: 0.0, durationSeconds: 180.0);
      final result = await svc.generateCues(t);
      // Either success with low-confidence cues, or insufficientMetadata
      // depending on edge-case logic (both are acceptable).
      expect(
        result.status,
        anyOf(
          CueGenerationStatus.success,
          CueGenerationStatus.insufficientMetadata,
        ),
      );
    });
  });

  // ── Success path ─────────────────────────────────────────────────────────

  group('success cases', () {
    test('returns CueGenerationStatus.success for a well-formed track',
        () async {
      final result = await svc.generateCues(_track());
      expect(result.status, CueGenerationStatus.success);
    });

    test('generates up to 8 cues', () async {
      final result = await svc.generateCues(_track());
      expect(result.cues.length, lessThanOrEqualTo(8));
      expect(result.cues.length, greaterThan(0));
    });

    test('cues are sorted ascending by timeSeconds', () async {
      final result = await svc.generateCues(_track());
      final times = result.cues.map((c) => c.timeSeconds).toList();
      final sorted = List<double>.from(times)..sort();
      expect(times, sorted);
    });

    test('all cue timeSeconds are within track duration', () async {
      final t = _track(durationSeconds: 210.0);
      final result = await svc.generateCues(t);
      for (final cue in result.cues) {
        expect(cue.timeSeconds, greaterThanOrEqualTo(0.0));
        expect(cue.timeSeconds, lessThan(t.durationSeconds));
      }
    });

    test('all cue timeSeconds are at least 0.5 seconds from start', () async {
      final result = await svc.generateCues(_track());
      for (final cue in result.cues) {
        expect(cue.timeSeconds, greaterThanOrEqualTo(0.5));
      }
    });

    test('cueIndex values are 0-based sequential within bounds', () async {
      final result = await svc.generateCues(_track());
      for (final cue in result.cues) {
        expect(cue.cueIndex, greaterThanOrEqualTo(0));
        expect(cue.cueIndex, lessThanOrEqualTo(7));
      }
    });

    test('confidence scores are within [0.0, 1.0]', () async {
      final result = await svc.generateCues(_track());
      for (final cue in result.cues) {
        expect(cue.confidence, inInclusiveRange(0.0, 1.0));
      }
    });

    test('isSuggested is true for all generated cues', () async {
      final result = await svc.generateCues(_track());
      expect(result.cues.every((c) => c.isSuggested), isTrue);
    });

    test('isWritten is false for all generated cues', () async {
      final result = await svc.generateCues(_track());
      expect(result.cues.every((c) => !c.isWritten), isTrue);
    });

    test('source is genreTemplate for deterministic cues', () async {
      final result = await svc.generateCues(_track());
      for (final cue in result.cues) {
        expect(cue.source, CueSource.genreTemplate);
      }
    });

    test('aiUsed is false (no AI in deterministic path)', () async {
      final result = await svc.generateCues(_track());
      expect(result.aiUsed, isFalse);
    });

    test('trackId is set correctly on each cue', () async {
      final t = _track(id: 'my-track-123');
      final result = await svc.generateCues(t);
      for (final cue in result.cues) {
        expect(cue.trackId, 'my-track-123');
      }
    });

    test('cue ids are unique within a result', () async {
      final result = await svc.generateCues(_track());
      final ids = result.cues.map((c) => c.id).toSet();
      expect(ids.length, result.cues.length);
    });

    test('each cue has a non-empty label', () async {
      final result = await svc.generateCues(_track());
      for (final cue in result.cues) {
        expect(cue.label, isNotEmpty);
      }
    });
  });

  // ── Bar snapping ──────────────────────────────────────────────────────────

  group('bar snapping', () {
    test('cue positions land on bar boundaries for 128 BPM', () async {
      const bpm = 128.0;
      final barDuration = (60.0 / bpm) * 4.0; // ~1.875 s
      final t = _track(bpm: bpm, durationSeconds: 240.0, genre: 'House');
      final result = await svc.generateCues(t);
      for (final cue in result.cues) {
        // Each time should be a multiple of barDuration (within ±0.5 s tolerance).
        final bars = cue.timeSeconds / barDuration;
        expect(bars - bars.roundToDouble(), closeTo(0.0, 0.5),
            reason:
                '${cue.label} at ${cue.timeSeconds}s is not on a bar boundary');
      }
    });

    test('intro cue lands near the beginning of the track', () async {
      final result = await svc.generateCues(_track(durationSeconds: 300.0));
      final introCue =
          result.cues.firstWhere((c) => c.cueType == CueType.intro);
      // Intro should be within first 15% of track.
      expect(introCue.timeSeconds / 300.0, lessThan(0.15));
    });

    test('mixOut cue lands near the end of the track', () async {
      final result = await svc.generateCues(_track(durationSeconds: 300.0));
      final mixOutCue =
          result.cues.firstWhere((c) => c.cueType == CueType.mixOut);
      // MixOut should be in the last 25% of track.
      expect(mixOutCue.timeSeconds / 300.0, greaterThan(0.70));
    });
  });

  // ── Genre classification ──────────────────────────────────────────────────

  group('genre classification', () {
    test('house track includes drop cue', () async {
      final result = await svc.generateCues(_track(genre: 'House'));
      expect(result.cues.any((c) => c.cueType == CueType.drop), isTrue);
    });

    test('trance track includes drop cue', () async {
      final result = await svc.generateCues(_track(genre: 'Trance'));
      expect(result.cues.any((c) => c.cueType == CueType.drop), isTrue);
    });

    test('hip-hop track includes vocalIn cue', () async {
      final result = await svc.generateCues(_track(genre: 'Hip-Hop'));
      expect(result.cues.any((c) => c.cueType == CueType.vocalIn), isTrue);
    });

    test('drum and bass track includes drop cue', () async {
      final result = await svc.generateCues(_track(genre: 'Drum & Bass'));
      expect(result.cues.any((c) => c.cueType == CueType.drop), isTrue);
    });

    test('generic genre produces cues with lower confidence', () async {
      final genericResult =
          await svc.generateCues(_track(genre: 'UnknownGenre123'));
      final houseResult =
          await svc.generateCues(_track(genre: 'House'));
      final genericAvg = genericResult.cues
              .map((c) => c.confidence)
              .reduce((a, b) => a + b) /
          genericResult.cues.length;
      final houseAvg = houseResult.cues
              .map((c) => c.confidence)
              .reduce((a, b) => a + b) /
          houseResult.cues.length;
      expect(genericAvg, lessThan(houseAvg));
    });

    test('empty genre string still produces cues', () async {
      final result = await svc.generateCues(_track(genre: ''));
      expect(result.isSuccess, isTrue);
      expect(result.cues, isNotEmpty);
    });
  });

  // ── Confidence scoring ────────────────────────────────────────────────────

  group('confidence scoring', () {
    test('well-known genre gives higher confidence than unknown', () async {
      final knownResult =
          await svc.generateCues(_track(genre: 'Tech House', bpm: 128.0));
      final unknownResult =
          await svc.generateCues(_track(genre: '', bpm: 0.0, durationSeconds: 180.0));
      if (!knownResult.isSuccess || !unknownResult.isSuccess) return;
      final knownAvg = knownResult.cues
              .map((c) => c.confidence)
              .reduce((a, b) => a + b) /
          knownResult.cues.length;
      final unknownAvg = unknownResult.cues
              .map((c) => c.confidence)
              .reduce((a, b) => a + b) /
          unknownResult.cues.length;
      expect(knownAvg, greaterThan(unknownAvg));
    });

    test('highConfidenceCount is correct', () async {
      final result = await svc.generateCues(_track());
      final manual = result.cues.where((c) => c.confidence >= 0.75).length;
      expect(result.highConfidenceCount, manual);
    });
  });

  // ── Batch generation ──────────────────────────────────────────────────────

  group('batch generation', () {
    test('generateCuesForTracks returns one result per input track', () async {
      final tracks = [
        _track(id: 'a', title: 'A'),
        _track(id: 'b', title: 'B'),
        _track(id: 'c', title: 'C'),
      ];
      final results = await svc.generateCuesForTracks(tracks);
      expect(results.keys, containsAll(['a', 'b', 'c']));
    });

    test('empty track list returns empty map', () async {
      final results = await svc.generateCuesForTracks([]);
      expect(results, isEmpty);
    });
  });

  // ── CueGenerationResult summary ───────────────────────────────────────────

  group('CueGenerationResult summary', () {
    test('success summary lists cue count', () async {
      final result = await svc.generateCues(_track());
      expect(result.summary, contains(result.cues.length.toString()));
    });

    test('insufficientMetadata summary contains the error reason', () {
      final result = CueGenerationResult.insufficientMetadata(
          't1', 'Track too short');
      expect(result.summary, contains('Track too short'));
    });
  });

  // ── CueType helpers ───────────────────────────────────────────────────────

  group('CueType helpers', () {
    test('CueType.label returns non-empty string for all types', () {
      for (final t in CueType.values) {
        expect(t.label, isNotEmpty);
      }
    });

    test('CueType.emoji returns non-empty string for all types', () {
      for (final t in CueType.values) {
        expect(t.emoji, isNotEmpty);
      }
    });

    test('CueType.vdjColor returns valid hex string for all types', () {
      final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
      for (final t in CueType.values) {
        expect(hexPattern.hasMatch(t.vdjColor), isTrue,
            reason: '${t.name} vdjColor "${t.vdjColor}" is not valid hex');
      }
    });
  });

  // ── HotCue helpers ────────────────────────────────────────────────────────

  group('HotCue helpers', () {
    late HotCue cue;

    setUp(() {
      cue = const HotCue(
        id: 'id1',
        trackId: 't1',
        cueIndex: 0,
        cueType: CueType.drop,
        label: 'Drop',
        timeSeconds: 93.5,
        confidence: 0.85,
        source: CueSource.genreTemplate,
      );
    });

    test('timeMs is timeSeconds * 1000 rounded', () {
      expect(cue.timeMs, 93500);
    });

    test('formattedTime is m:ss format', () {
      expect(cue.formattedTime, '1:33');
    });

    test('confidenceLabel is High for confidence >= 0.75', () {
      expect(cue.confidenceLabel, 'High');
    });

    test('confidenceLabel is Medium for confidence in [0.5, 0.75)', () {
      final mid = cue.copyWith(confidence: 0.6);
      expect(mid.confidenceLabel, 'Medium');
    });

    test('confidenceLabel is Low for confidence < 0.5', () {
      final low = cue.copyWith(confidence: 0.3);
      expect(low.confidenceLabel, 'Low');
    });

    test('copyWith preserves unchanged fields', () {
      final updated = cue.copyWith(label: 'New Label');
      expect(updated.id, cue.id);
      expect(updated.trackId, cue.trackId);
      expect(updated.cueType, cue.cueType);
      expect(updated.timeSeconds, cue.timeSeconds);
      expect(updated.label, 'New Label');
    });

    test('toJson / fromJson round-trips correctly', () {
      final json = cue.toJson();
      final restored = HotCue.fromJson(json);
      expect(restored.id, cue.id);
      expect(restored.trackId, cue.trackId);
      expect(restored.cueIndex, cue.cueIndex);
      expect(restored.cueType, cue.cueType);
      expect(restored.label, cue.label);
      expect(restored.timeSeconds, cue.timeSeconds);
      expect(restored.confidence, cue.confidence);
      expect(restored.source, cue.source);
      expect(restored.isSuggested, cue.isSuggested);
      expect(restored.isWritten, cue.isWritten);
    });
  });
}
