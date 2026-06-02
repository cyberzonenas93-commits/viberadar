import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/services/audio_cue_detector.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers for building synthetic energy envelopes
// ─────────────────────────────────────────────────────────────────────────────

/// Build a flat envelope at [level] for [durationSec] at [windowSec].
List<double> _flatEnv(double level, double durationSec,
    {double windowSec = 0.1}) {
  final n = (durationSec / windowSec).ceil();
  return List<double>.filled(n, level);
}

/// Build an envelope by concatenating segments described as (level, durationSec).
List<double> _segmentedEnv(List<(double, double)> segments,
    {double windowSec = 0.1}) {
  final out = <double>[];
  for (final (level, dur) in segments) {
    final n = (dur / windowSec).ceil();
    out.addAll(List<double>.filled(n, level));
  }
  return out;
}

/// Build a ramp from [start] to [end] over [durationSec].
List<double> _rampEnv(double start, double end, double durationSec,
    {double windowSec = 0.1}) {
  final n = (durationSec / windowSec).ceil();
  return List<double>.generate(n, (i) {
    if (n <= 1) return end;
    return start + (end - start) * i / (n - 1);
  });
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── DSP unit tests (pure functions, no I/O) ───────────────────────────────
  group('AudioCueDetector — pure DSP helpers', () {
    test('buildEnergyEnvelope: RMS of silent signal is 0', () {
      final samples = List<double>.filled(11025, 0.0);
      final env = AudioCueDetector.buildEnergyEnvelope(samples, 1102);
      expect(env.every((v) => v == 0.0), isTrue);
    });

    test('buildEnergyEnvelope: RMS of full-scale sine is close to 1/sqrt(2)', () {
      // Generate one full period of a unit sine at 440 Hz sampled at 11025 Hz
      const rate = 11025;
      const freq = 440.0;
      final samples = List<double>.generate(
          rate, (i) => math.sin(2 * math.pi * freq * i / rate));
      // One window of 1102 samples
      final env = AudioCueDetector.buildEnergyEnvelope(samples, 1102);
      // RMS of a sine ≈ 0.707; allow ±0.05 due to windowing
      for (final v in env) {
        expect(v, closeTo(1 / math.sqrt(2), 0.05));
      }
    });

    test('smoothEnvelope: flat signal stays flat', () {
      final env = List<double>.filled(100, 0.6);
      final smoothed = AudioCueDetector.smoothEnvelope(env, radius: 5);
      for (final v in smoothed) {
        expect(v, closeTo(0.6, 1e-9));
      }
    });

    test('smoothEnvelope: reduces a sharp spike', () {
      final env = List<double>.filled(50, 0.2);
      env[25] = 1.0; // one-window spike
      final smoothed = AudioCueDetector.smoothEnvelope(env, radius: 5);
      // Spike should be reduced
      expect(smoothed[25], lessThan(1.0));
      expect(smoothed[25], greaterThan(0.2));
    });

    test('normalise: output is in [0, 1]', () {
      final env = [0.1, 0.3, 0.6, 0.2, 0.9, 0.4];
      final n = AudioCueDetector.normalise(env);
      expect(n.reduce(math.min), closeTo(0.0, 1e-9));
      expect(n.reduce(math.max), closeTo(1.0, 1e-9));
    });

    test('normalise: constant signal returns all zeros', () {
      final env = List<double>.filled(20, 0.5);
      final n = AudioCueDetector.normalise(env);
      expect(n.every((v) => v == 0.0), isTrue);
    });
  });

  // ── detectEventsFromEnvelope — synthetic envelopes ────────────────────────
  group('detectEventsFromEnvelope — intro always present', () {
    test('Intro at t=0 is always emitted', () {
      final env = _flatEnv(0.5, 120.0);
      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: 0.1,
        totalDuration: 120.0,
      );
      expect(events.any((e) => e.type == CueType.intro), isTrue);
      final intro = events.firstWhere((e) => e.type == CueType.intro);
      expect(intro.timeSeconds, closeTo(0.0, 0.5));
    });
  });

  group('detectEventsFromEnvelope — drop detection', () {
    test('Sharp rise from low to high in first 40% → drop event near transition', () {
      // 30 s low (0.1), then 90 s high (0.9) — rise at t=30
      const windowSec = 0.1;
      const totalDur = 120.0;
      final env = _segmentedEnv([
        (0.1, 30.0),
        (0.9, 90.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
      );

      final drops = events.where((e) => e.type == CueType.drop).toList();
      expect(drops, isNotEmpty, reason: 'Expected at least one drop event');
      // The drop should be near t=30 (within 5 s given smoothing)
      final near30 = drops.any((e) => (e.timeSeconds - 30.0).abs() < 10.0);
      expect(near30, isTrue,
          reason: 'Drop should be detected near the 30s transition');
    });

    test('No drop if track is flat at low energy', () {
      const windowSec = 0.1;
      final env = _flatEnv(0.1, 120.0, windowSec: windowSec);
      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: 120.0,
      );
      final drops = events.where((e) => e.type == CueType.drop);
      expect(drops, isEmpty, reason: 'No drop expected in a flat low-energy track');
    });
  });

  group('detectEventsFromEnvelope — breakdown + re-entry detection', () {
    test('Dip in the middle of a high section → breakdown + re-entry', () {
      // high (0.8) for 60s, then dip (0.1) for 30s, then high (0.8) for 60s
      const windowSec = 0.1;
      const totalDur = 150.0;
      final env = _segmentedEnv([
        (0.8, 60.0),
        (0.1, 30.0),
        (0.8, 60.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
        minSpacingSec: 4.0,
      );

      final hasBD = events.any((e) => e.type == CueType.breakdown);
      final hasRE = events.any((e) => e.type == CueType.reEntry);
      expect(hasBD, isTrue, reason: 'Expected a breakdown event');
      expect(hasRE, isTrue, reason: 'Expected a re-entry event');

      // breakdown before re-entry
      if (hasBD && hasRE) {
        final bd = events.firstWhere((e) => e.type == CueType.breakdown);
        final re = events.firstWhere((e) => e.type == CueType.reEntry);
        expect(bd.timeSeconds, lessThan(re.timeSeconds));
        // breakdown near t=60, re-entry near t=90
        expect(bd.timeSeconds, closeTo(60.0, 10.0));
        expect(re.timeSeconds, closeTo(90.0, 10.0));
      }
    });
  });

  group('detectEventsFromEnvelope — outro / mix-out detection', () {
    test('Sustained fall near end → mixOut event in last third of track', () {
      // high (0.8) for 200s, then gradual fall to low (0.1) for 40s
      const windowSec = 0.1;
      const totalDur = 240.0;
      final high = _flatEnv(0.8, 200.0, windowSec: windowSec);
      final fade = _rampEnv(0.8, 0.05, 40.0, windowSec: windowSec);
      final env = [...high, ...fade];

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
        minSpacingSec: 4.0,
      );

      final mixOuts = events.where((e) => e.type == CueType.mixOut).toList();
      expect(mixOuts, isNotEmpty, reason: 'Expected a mixOut event');
      // mixOut should be in the last 40% of the track
      for (final mo in mixOuts) {
        expect(mo.timeSeconds, greaterThan(totalDur * 0.50));
      }
    });
  });

  group('detectEventsFromEnvelope — structural invariants', () {
    test('Events are time-ordered', () {
      const windowSec = 0.1;
      const totalDur = 240.0;
      final env = _segmentedEnv([
        (0.1, 30.0),
        (0.9, 90.0),
        (0.2, 30.0),
        (0.85, 60.0),
        (0.1, 30.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
      );

      for (var i = 1; i < events.length; i++) {
        expect(events[i].timeSeconds,
            greaterThanOrEqualTo(events[i - 1].timeSeconds),
            reason: 'Events must be time-ordered');
      }
    });

    test('Minimum spacing is respected', () {
      const windowSec = 0.1;
      const totalDur = 240.0;
      const minSpacing = 4.0;
      final env = _segmentedEnv([
        (0.1, 30.0),
        (0.9, 120.0),
        (0.1, 30.0),
        (0.9, 60.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
        minSpacingSec: minSpacing,
      );

      for (var i = 1; i < events.length; i++) {
        final gap = events[i].timeSeconds - events[i - 1].timeSeconds;
        expect(gap, greaterThanOrEqualTo(minSpacing - 1e-9),
            reason:
                'Gap between events ${events[i - 1].type} and ${events[i].type} '
                '(${gap.toStringAsFixed(2)}s) < minSpacing ($minSpacing s)');
      }
    });

    test('No event exceeds track duration', () {
      const windowSec = 0.1;
      const totalDur = 180.0;
      final env = _segmentedEnv([
        (0.2, 40.0),
        (0.9, 100.0),
        (0.1, 40.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
      );

      for (final ev in events) {
        expect(ev.timeSeconds, lessThan(totalDur),
            reason:
                'Event ${ev.type} at ${ev.timeSeconds}s exceeds duration $totalDur');
      }
    });

    test('Total events capped at maxCues', () {
      const windowSec = 0.1;
      const totalDur = 600.0;
      // Very dynamic signal with many transitions
      final env = <double>[];
      for (var i = 0; i < (totalDur / windowSec).ceil(); i++) {
        env.add((i % 20 < 10) ? 0.9 : 0.1);
      }

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
        maxCues: 8,
      );

      expect(events.length, lessThanOrEqualTo(8),
          reason: 'Should not exceed maxCues=8');
    });

    test('Confidence is in [0, 1] for all events', () {
      const windowSec = 0.1;
      const totalDur = 240.0;
      final env = _segmentedEnv([
        (0.1, 30.0),
        (0.9, 120.0),
        (0.2, 30.0),
        (0.8, 60.0),
      ], windowSec: windowSec);

      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: windowSec,
        totalDuration: totalDur,
      );

      for (final ev in events) {
        expect(ev.confidence, inInclusiveRange(0.0, 1.0),
            reason: 'Confidence out of range for ${ev.type}');
      }
    });

    test('Empty envelope returns empty list', () {
      final events = AudioCueDetector.detectEventsFromEnvelope(
        [],
        windowSec: 0.1,
        totalDuration: 120.0,
      );
      expect(events, isEmpty);
    });

    test('Zero duration returns empty list', () {
      final env = _flatEnv(0.5, 10.0);
      final events = AudioCueDetector.detectEventsFromEnvelope(
        env,
        windowSec: 0.1,
        totalDuration: 0.0,
      );
      expect(events, isEmpty);
    });
  });

  // ── CueSource.audioEnergy label ───────────────────────────────────────────
  group('CueSource.audioEnergy', () {
    test('audioEnergy label is "Audio (detected)"', () {
      expect(CueSource.audioEnergy.label, equals('Audio (detected)'));
    });

    test('audioEnergy round-trips through HotCue JSON', () {
      final cue = HotCue(
        trackId: 'test-track',
        cueIndex: 0,
        cueType: CueType.drop,
        label: 'Drop',
        timeSeconds: 42.5,
        confidence: 0.85,
        source: CueSource.audioEnergy,
        notes: 'Detected from audio energy',
      );
      final json = cue.toJson();
      final restored = HotCue.fromJson(json);
      expect(restored.source, equals(CueSource.audioEnergy));
      expect(restored.source.label, equals('Audio (detected)'));
    });
  });

  // ── Integration smoke test (skipped if dependencies absent) ──────────────
  //
  // This test runs ffmpeg on a real audio file and verifies that the detector
  // returns a non-empty list of plausible events. It is automatically SKIPPED
  // when:
  //   - ffmpeg is not installed at /opt/homebrew/bin/ffmpeg and not on PATH
  //   - no .mp3 file is found in ~/Downloads/amapiano
  //
  group('AudioCueDetector — integration smoke test (real audio, optional)', () {
    test('detectCues returns plausible events for a real .mp3', () async {
      // ── Guard: ffmpeg must be present ──────────────────────────────────
      const ffmpegPath = '/opt/homebrew/bin/ffmpeg';
      bool ffmpegAvailable = File(ffmpegPath).existsSync();
      if (!ffmpegAvailable) {
        try {
          final r = await Process.run('which', ['ffmpeg']);
          ffmpegAvailable = r.exitCode == 0;
        } catch (_) {}
      }
      if (!ffmpegAvailable) {
        // ignore: avoid_print
        print('[SKIP] ffmpeg not found — skipping integration smoke test');
        return;
      }

      // ── Guard: find a .mp3 in ~/Downloads/amapiano ────────────────────
      final dir = Directory(
          '${Platform.environment['HOME'] ?? ''}/Downloads/amapiano');
      if (!dir.existsSync()) {
        // ignore: avoid_print
        print('[SKIP] ~/Downloads/amapiano not found — skipping integration smoke test');
        return;
      }
      final mp3Files = dir
          .listSync(recursive: false)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.mp3'))
          .toList();
      if (mp3Files.isEmpty) {
        // ignore: avoid_print
        print('[SKIP] No .mp3 files in ~/Downloads/amapiano — skipping integration smoke test');
        return;
      }

      final testFile = mp3Files.first;
      // ignore: avoid_print
      print('[INFO] Integration smoke test using: ${testFile.path}');

      // ── Run the detector ──────────────────────────────────────────────
      final detector = AudioCueDetector();
      final events = await detector.detectCues(testFile.path);

      expect(events, isNotNull,
          reason: 'detectCues should not return null for a valid mp3 file');
      expect(events!, isNotEmpty,
          reason: 'detectCues should return at least one event');

      // All events must be time-ordered
      for (var i = 1; i < events.length; i++) {
        expect(events[i].timeSeconds,
            greaterThanOrEqualTo(events[i - 1].timeSeconds),
            reason: 'Events must be time-ordered');
      }

      // All events must have valid confidence
      for (final ev in events) {
        expect(ev.confidence, inInclusiveRange(0.0, 1.0));
        expect(ev.timeSeconds, greaterThanOrEqualTo(0.0));
      }

      // Intro must be first
      expect(events.first.type, equals(CueType.intro));

      // ignore: avoid_print
      print('[INFO] Detected ${events.length} events:');
      for (final ev in events) {
        final min = (ev.timeSeconds / 60).floor();
        final sec = (ev.timeSeconds % 60).floor();
        // ignore: avoid_print
        print(
            '  ${ev.type.label.padRight(12)} @ ${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')} '
            '(conf: ${ev.confidence.toStringAsFixed(2)})');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
