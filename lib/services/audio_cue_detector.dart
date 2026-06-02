import 'dart:io';
import 'dart:math' as math;
import '../models/hot_cue.dart';

// ── AudioCueDetector ──────────────────────────────────────────────────────────
//
// Detects musically meaningful cue points by analysing the audio energy
// envelope of a local file via ffmpeg.
//
// Usage:
//   final detector = AudioCueDetector();
//   final events = await detector.detectCues('/path/to/track.mp3', durationSeconds: 360.0);
//   if (events != null) { /* use real events */ }
//   else               { /* fall back to BPM/template estimate */ }

/// A single detected cue event before it is promoted to a [HotCue].
typedef CueEvent = ({double timeSeconds, CueType type, double confidence});

class AudioCueDetector {
  // ── Tunables ───────────────────────────────────────────────────────────────

  /// ffmpeg binary path. Falls back to the system PATH if not found here.
  static const String _ffmpegPath = '/opt/homebrew/bin/ffmpeg';

  /// Sample rate used for the decoded PCM stream.
  /// 11025 Hz is enough for energy-envelope analysis; keeps pipe fast.
  static const int _sampleRate = 11025;

  /// Window size in seconds for the RMS energy envelope.
  static const double _windowSec = 0.10; // 10 ms windows → 1102 samples

  /// Minimum spacing between reported cue events (seconds).
  static const double _minSpacingSec = 4.0;

  /// Maximum number of cues returned.
  static const int _maxCues = 8;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Decode [filePath] with ffmpeg and derive cue events from the energy
  /// envelope.
  ///
  /// Returns `null` when:
  ///   - ffmpeg is not found / exits with an error;
  ///   - the file cannot be decoded (empty stdout);
  ///   - any unexpected I/O exception occurs.
  ///
  /// Returns an **empty list** only in the unlikely case that a valid audio
  /// file is decoded but the envelope contains no detectable events — callers
  /// should treat this the same as `null` (fall back to estimate).
  Future<List<CueEvent>?> detectCues(
    String filePath, {
    double? durationSeconds,
  }) async {
    // ── 1. Locate ffmpeg ───────────────────────────────────────────────────
    final ffmpeg = File(_ffmpegPath).existsSync() ? _ffmpegPath : 'ffmpeg';

    // ── 2. Decode to mono 16-bit LE PCM via pipe ───────────────────────────
    ProcessResult result;
    try {
      result = await Process.run(
        ffmpeg,
        [
          '-v', 'error',          // suppress banner noise
          '-i', filePath,
          '-ac', '1',             // mono
          '-ar', '$_sampleRate',  // target sample rate
          '-f', 's16le',          // signed 16-bit little-endian PCM
          '-',                    // write to stdout
        ],
        stdoutEncoding: null,     // receive raw bytes, not a String
      );
    } catch (e) {
      // ffmpeg binary not found or OS-level failure
      return null;
    }

    if (result.exitCode != 0) return null;

    final bytes = result.stdout as List<int>;
    if (bytes.isEmpty) return null;

    // ── 3. Interpret bytes as Int16 samples ───────────────────────────────
    final samples = _int16Samples(bytes);
    if (samples.isEmpty) return null;

    // ── 4. Build energy envelope ─────────────────────────────────────────
    final windowSamples = (_windowSec * _sampleRate).round().clamp(1, samples.length);
    final envelope = buildEnergyEnvelope(samples, windowSamples);
    if (envelope.isEmpty) return null;

    // ── 5. Derive events from the envelope ───────────────────────────────
    final totalDur = durationSeconds ??
        (samples.length / _sampleRate.toDouble());

    final events = detectEventsFromEnvelope(
      envelope,
      windowSec: _windowSec,
      totalDuration: totalDur,
      minSpacingSec: _minSpacingSec,
      maxCues: _maxCues,
    );

    return events;
  }

  // ── Pure / testable DSP helpers ───────────────────────────────────────────
  // All functions below operate on `List<double>` energy values and have no
  // dependency on I/O — they can be unit-tested with synthetic envelopes.

  /// Parse raw little-endian bytes into normalised double samples [-1, 1].
  static List<double> _int16Samples(List<int> bytes) {
    // Need at least two bytes per sample
    final count = bytes.length ~/ 2;
    if (count == 0) return [];
    final samples = List<double>.filled(count, 0.0);
    for (var i = 0; i < count; i++) {
      final lo = bytes[i * 2] & 0xFF;
      final hi = bytes[i * 2 + 1] & 0xFF;
      // Reconstruct signed 16-bit value
      int raw = lo | (hi << 8);
      if (raw >= 0x8000) raw -= 0x10000; // two's complement
      samples[i] = raw / 32768.0;
    }
    return samples;
  }

  /// Build an RMS energy envelope from raw samples.
  ///
  /// Each element is the RMS of one [windowSize]-sample window.
  /// Pure function — safe to call in tests with synthetic data.
  static List<double> buildEnergyEnvelope(
      List<double> samples, int windowSize) {
    if (samples.isEmpty || windowSize <= 0) return [];
    final count = (samples.length / windowSize).ceil();
    final env = List<double>.filled(count, 0.0);
    for (var w = 0; w < count; w++) {
      final start = w * windowSize;
      final end = math.min(start + windowSize, samples.length);
      double sumSq = 0.0;
      for (var i = start; i < end; i++) {
        sumSq += samples[i] * samples[i];
      }
      env[w] = math.sqrt(sumSq / (end - start));
    }
    return env;
  }

  /// Smooth a 1-D signal with a simple moving average.
  ///
  /// [radius] is the one-sided half-width (total window = 2*radius + 1).
  static List<double> smoothEnvelope(List<double> env, {int radius = 5}) {
    if (env.isEmpty) return [];
    final out = List<double>.filled(env.length, 0.0);
    for (var i = 0; i < env.length; i++) {
      final lo = (i - radius).clamp(0, env.length - 1);
      final hi = (i + radius).clamp(0, env.length - 1);
      double sum = 0.0;
      for (var j = lo; j <= hi; j++) {
        sum += env[j];
      }
      out[i] = sum / (hi - lo + 1);
    }
    return out;
  }

  /// Normalise a signal to [0, 1].
  static List<double> normalise(List<double> env) {
    if (env.isEmpty) return [];
    final mx = env.reduce(math.max);
    final mn = env.reduce(math.min);
    final range = mx - mn;
    if (range < 1e-9) return List<double>.filled(env.length, 0.0);
    return env.map((v) => (v - mn) / range).toList();
  }

  /// Derive musically-meaningful [CueEvent]s from a normalised energy envelope.
  ///
  /// Parameters:
  ///   [envelope]       — raw (un-normalised) energy values, one per window.
  ///   [windowSec]      — duration of each window in seconds.
  ///   [totalDuration]  — track duration; events outside this are discarded.
  ///   [minSpacingSec]  — minimum gap between adjacent events.
  ///   [maxCues]        — cap on the number of returned events.
  ///
  /// This is the core DSP logic. It is a **pure function** and has no I/O
  /// dependencies so it can be unit-tested with synthetic envelopes.
  static List<CueEvent> detectEventsFromEnvelope(
    List<double> envelope, {
    required double windowSec,
    required double totalDuration,
    double minSpacingSec = 4.0,
    int maxCues = 8,
  }) {
    if (envelope.isEmpty || totalDuration <= 0) return [];

    // ── Smooth + normalise ──────────────────────────────────────────────
    // Smoothing radius ~1 second worth of windows
    final radius = math.max(1, (1.0 / windowSec).round());
    final smoothed = smoothEnvelope(envelope, radius: radius);
    final norm = normalise(smoothed);

    final n = norm.length;

    // ── Event candidate list ────────────────────────────────────────────
    final raw = <CueEvent>[];

    // Helper: time in seconds for window index w
    double t(int w) => w * windowSec;

    // ── 1. Intro: always t=0 ─────────────────────────────────────────────
    raw.add((
      timeSeconds: 0.0,
      type: CueType.intro,
      confidence: 0.80,
    ));

    // ── 2. First sustained rise (first drop) ─────────────────────────────
    // Scan through the first 40% of the track for the first window where
    // energy crosses 0.5 and stays above it for at least 2 windows.
    {
      final horizon = (n * 0.40).round();
      for (var i = 1; i < horizon - 1; i++) {
        if (norm[i] >= 0.50 && norm[i + 1] >= 0.50 && norm[i - 1] < 0.50) {
          // Rise start is 1 window before crossing
          final riseStart = math.max(0, i - 1);
          final jumpMag = (norm[i] - norm[riseStart]).clamp(0.0, 1.0);
          final conf = (0.50 + jumpMag * 0.45).clamp(0.40, 0.95);
          raw.add((
            timeSeconds: t(i),
            type: CueType.drop,
            confidence: conf,
          ));
          break;
        }
      }
    }

    // ── 3. Main drop: largest positive energy jump in high-energy region ─
    // Look in the 20–80% range for the biggest delta over a short lookback.
    {
      final lo = (n * 0.20).round();
      final hi = (n * 0.80).round();
      final lookback = math.max(1, (0.5 / windowSec).round()); // ~0.5 s

      double bestJump = 0.0;
      int bestIdx = -1;
      for (var i = lo + lookback; i < hi; i++) {
        final delta = norm[i] - norm[i - lookback];
        if (delta > bestJump && norm[i] >= 0.55) {
          bestJump = delta;
          bestIdx = i;
        }
      }
      if (bestIdx >= 0 && bestJump > 0.10) {
        final conf = (0.55 + bestJump * 0.40).clamp(0.40, 0.95);
        raw.add((
          timeSeconds: t(bestIdx),
          type: CueType.drop,
          confidence: conf,
        ));
      }
    }

    // ── 4. Breakdown + re-entry ───────────────────────────────────────────
    // A breakdown is a sustained dip (below 0.35 for at least 3 windows)
    // that occurs after a high section (above 0.5 before it).
    {
      final minDipWindows = math.max(1, (1.0 / windowSec).round()); // ~1 s

      // Scan from 25% to 80% of the track.
      final lo = (n * 0.25).round();
      final hi = (n * 0.80).round();

      bool wasHigh = false;
      int? dipStart;

      for (var i = lo; i < hi; i++) {
        if (norm[i] >= 0.5) {
          wasHigh = true;
          if (dipStart != null) {
            // End of dip — check if it was long enough
            final ds = dipStart; // promote to non-nullable local
            final dipLen = i - ds;
            if (dipLen >= minDipWindows) {
              final avgDip =
                  norm.sublist(ds, i).reduce((a, b) => a + b) / dipLen;
              final depth = (0.35 - avgDip).clamp(0.0, 0.35) / 0.35;
              final bdConf = (0.45 + depth * 0.45).clamp(0.40, 0.90);
              // Breakdown at dip start, re-entry at dip end
              raw.add((
                timeSeconds: t(ds),
                type: CueType.breakdown,
                confidence: bdConf,
              ));
              final reConf = (bdConf * 0.95).clamp(0.40, 0.90);
              raw.add((
                timeSeconds: t(i),
                type: CueType.reEntry,
                confidence: reConf,
              ));
            }
            dipStart = null;
          }
        } else if (norm[i] < 0.35 && wasHigh) {
          dipStart ??= i;
        }
      }
    }

    // ── 5. Mix-out + outro ────────────────────────────────────────────────
    // Scan backwards from the end to find the last sustained fall below 0.4.
    {
      const fallThresh = 0.40;
      final minOutroSec = 10.0;
      final minOutroIdx = (minOutroSec / windowSec).round();
      final scanStart = math.max(0, n - (n * 0.35).round());

      int? fallIdx;
      for (var i = scanStart; i < n - minOutroIdx; i++) {
        if (norm[i] < fallThresh &&
            (i + 1 < n ? norm[i + 1] : 0.0) < fallThresh) {
          fallIdx = i;
          break;
        }
      }

      if (fallIdx != null && t(fallIdx) < totalDuration) {
        // Mix out at the fall point
        final mixFallMag = fallIdx > 0
            ? (norm[fallIdx - 1] - norm[fallIdx]).clamp(0.0, 1.0)
            : 0.0;
        final moConf = (0.50 + mixFallMag * 0.40).clamp(0.40, 0.90);
        raw.add((
          timeSeconds: t(fallIdx),
          type: CueType.mixOut,
          confidence: moConf,
        ));

        // Outro: last few windows (last 8 seconds or last 5% of track)
        final outroSec =
            math.max(totalDuration - 8.0, totalDuration * 0.95);
        if (outroSec > 0 && outroSec < totalDuration) {
          raw.add((
            timeSeconds: outroSec,
            type: CueType.outro,
            confidence: 0.72,
          ));
        }
      }
    }

    // ── 6. Sort, clamp, deduplicate, cap ─────────────────────────────────
    final sorted = List<CueEvent>.from(raw)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final deduped = <CueEvent>[];
    for (final ev in sorted) {
      // Clamp to valid range
      if (ev.timeSeconds < 0 || ev.timeSeconds >= totalDuration) continue;
      // De-duplicate by minimum spacing (keep the more confident one if clash)
      if (deduped.isNotEmpty) {
        final gap = ev.timeSeconds - deduped.last.timeSeconds;
        if (gap < minSpacingSec) {
          if (ev.confidence > deduped.last.confidence) {
            deduped[deduped.length - 1] = ev;
          }
          continue;
        }
      }
      deduped.add(ev);
      if (deduped.length >= maxCues) break;
    }

    return deduped;
  }
}
