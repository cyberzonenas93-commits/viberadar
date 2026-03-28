// ── CueAnalysisService ────────────────────────────────────────────────────────
//
// Deterministic hot-cue generation from BPM grid + duration heuristics +
// genre-structural templates.
//
// DESIGN CONTRACT
// ──────────────
// • NEVER fabricates timestamps — all positions are derived mathematically
//   from BPM (bar snapping) and track duration (structural ratios).
// • AI (GPT) is only used as an OPTIONAL ranking layer on top of
//   deterministic candidates. AI does NOT produce new timestamps.
// • Returns up to 8 cue points (VirtualDJ max per track).
// • Confidence is reduced when key metadata (BPM, duration) is weak.

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/cue_generation_result.dart';
import '../models/hot_cue.dart';
import '../models/library_track.dart';

// ── Genre group classification ────────────────────────────────────────────────

enum _GenreGroup {
  edmHouse,          // House, Techno, EDM, Tech House, Progressive
  trance,            // Trance, Psytrance, Progressive Trance
  hiphopRnb,         // Hip-Hop, R&B, Trap, Drill
  popDance,          // Pop, Dance-Pop, Electropop
  afrobeats,         // Afrobeats, Afrohouse, Amapiano, Dancehall
  reggaeSoulFunk,    // Reggae, Soul, Funk, Neo-Soul, Blues
  drumsAndBass,      // Drum & Bass, Jungle, Liquid DnB
  generic,           // Fallback for unknown/unusual genres
}

// ── Structural template: per-genre cue type relative positions ─────────────

/// Defines where each cue type appears as a fraction of track duration
/// for a given genre group.  Positions are [min, ideal, max] as fractions.
class _CueTemplate {
  const _CueTemplate(this.type, this.minFrac, this.idealFrac, this.maxFrac,
      {this.confidence = 0.8});
  final CueType type;
  final double minFrac;
  final double idealFrac;
  final double maxFrac;

  /// Base confidence for this template entry.
  final double confidence;
}

// Templates for each genre group (up to 8 cues each).
const Map<_GenreGroup, List<_CueTemplate>> _templates = {
  _GenreGroup.edmHouse: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.05, confidence: 0.95),
    _CueTemplate(CueType.mixIn, 0.06, 0.10, 0.15, confidence: 0.90),
    _CueTemplate(CueType.vocalIn, 0.12, 0.20, 0.28, confidence: 0.75),
    _CueTemplate(CueType.hook, 0.25, 0.32, 0.40, confidence: 0.80),
    _CueTemplate(CueType.drop, 0.30, 0.38, 0.45, confidence: 0.85),
    _CueTemplate(CueType.breakdown, 0.48, 0.55, 0.65, confidence: 0.80),
    _CueTemplate(CueType.reEntry, 0.58, 0.65, 0.73, confidence: 0.80),
    _CueTemplate(CueType.mixOut, 0.78, 0.85, 0.93, confidence: 0.90),
  ],
  _GenreGroup.trance: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.05, confidence: 0.90),
    _CueTemplate(CueType.mixIn, 0.06, 0.12, 0.18, confidence: 0.85),
    _CueTemplate(CueType.vocalIn, 0.15, 0.22, 0.30, confidence: 0.75),
    _CueTemplate(CueType.hook, 0.22, 0.30, 0.38, confidence: 0.80),
    _CueTemplate(CueType.drop, 0.28, 0.38, 0.48, confidence: 0.80),
    _CueTemplate(CueType.breakdown, 0.50, 0.58, 0.68, confidence: 0.80),
    _CueTemplate(CueType.reEntry, 0.60, 0.68, 0.76, confidence: 0.80),
    _CueTemplate(CueType.mixOut, 0.80, 0.88, 0.95, confidence: 0.85),
  ],
  _GenreGroup.hiphopRnb: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.08, confidence: 0.85),
    _CueTemplate(CueType.mixIn, 0.06, 0.10, 0.16, confidence: 0.80),
    _CueTemplate(CueType.vocalIn, 0.08, 0.14, 0.22, confidence: 0.85),
    _CueTemplate(CueType.hook, 0.18, 0.26, 0.35, confidence: 0.80),
    _CueTemplate(CueType.breakdown, 0.40, 0.50, 0.60, confidence: 0.70),
    _CueTemplate(CueType.reEntry, 0.55, 0.62, 0.70, confidence: 0.70),
    _CueTemplate(CueType.mixOut, 0.78, 0.86, 0.93, confidence: 0.80),
    _CueTemplate(CueType.outro, 0.90, 0.94, 0.98, confidence: 0.75),
  ],
  _GenreGroup.popDance: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.06, confidence: 0.90),
    _CueTemplate(CueType.mixIn, 0.05, 0.10, 0.16, confidence: 0.85),
    _CueTemplate(CueType.vocalIn, 0.06, 0.12, 0.18, confidence: 0.85),
    _CueTemplate(CueType.hook, 0.20, 0.28, 0.36, confidence: 0.85),
    _CueTemplate(CueType.drop, 0.28, 0.35, 0.44, confidence: 0.75),
    _CueTemplate(CueType.breakdown, 0.48, 0.56, 0.65, confidence: 0.75),
    _CueTemplate(CueType.reEntry, 0.58, 0.65, 0.73, confidence: 0.75),
    _CueTemplate(CueType.mixOut, 0.80, 0.87, 0.94, confidence: 0.85),
  ],
  _GenreGroup.afrobeats: [
    _CueTemplate(CueType.intro, 0.0, 0.03, 0.08, confidence: 0.85),
    _CueTemplate(CueType.mixIn, 0.06, 0.12, 0.18, confidence: 0.80),
    _CueTemplate(CueType.vocalIn, 0.08, 0.14, 0.22, confidence: 0.80),
    _CueTemplate(CueType.hook, 0.20, 0.28, 0.38, confidence: 0.80),
    _CueTemplate(CueType.breakdown, 0.45, 0.54, 0.63, confidence: 0.70),
    _CueTemplate(CueType.reEntry, 0.60, 0.66, 0.74, confidence: 0.75),
    _CueTemplate(CueType.mixOut, 0.78, 0.86, 0.92, confidence: 0.80),
    _CueTemplate(CueType.outro, 0.88, 0.93, 0.98, confidence: 0.70),
  ],
  _GenreGroup.reggaeSoulFunk: [
    _CueTemplate(CueType.intro, 0.0, 0.03, 0.08, confidence: 0.80),
    _CueTemplate(CueType.mixIn, 0.06, 0.12, 0.20, confidence: 0.75),
    _CueTemplate(CueType.vocalIn, 0.08, 0.14, 0.22, confidence: 0.80),
    _CueTemplate(CueType.hook, 0.22, 0.30, 0.40, confidence: 0.75),
    _CueTemplate(CueType.breakdown, 0.42, 0.52, 0.62, confidence: 0.65),
    _CueTemplate(CueType.reEntry, 0.58, 0.65, 0.74, confidence: 0.65),
    _CueTemplate(CueType.mixOut, 0.78, 0.85, 0.92, confidence: 0.75),
    _CueTemplate(CueType.outro, 0.88, 0.93, 0.98, confidence: 0.70),
  ],
  _GenreGroup.drumsAndBass: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.06, confidence: 0.90),
    _CueTemplate(CueType.mixIn, 0.05, 0.10, 0.15, confidence: 0.85),
    _CueTemplate(CueType.hook, 0.12, 0.20, 0.28, confidence: 0.80),
    _CueTemplate(CueType.drop, 0.18, 0.25, 0.35, confidence: 0.85),
    _CueTemplate(CueType.breakdown, 0.40, 0.50, 0.60, confidence: 0.80),
    _CueTemplate(CueType.reEntry, 0.55, 0.62, 0.70, confidence: 0.80),
    _CueTemplate(CueType.mixOut, 0.78, 0.85, 0.92, confidence: 0.85),
    _CueTemplate(CueType.outro, 0.90, 0.94, 0.98, confidence: 0.75),
  ],
  _GenreGroup.generic: [
    _CueTemplate(CueType.intro, 0.0, 0.02, 0.08, confidence: 0.75),
    _CueTemplate(CueType.mixIn, 0.06, 0.12, 0.20, confidence: 0.70),
    _CueTemplate(CueType.vocalIn, 0.12, 0.18, 0.26, confidence: 0.65),
    _CueTemplate(CueType.hook, 0.22, 0.30, 0.40, confidence: 0.65),
    _CueTemplate(CueType.breakdown, 0.45, 0.54, 0.63, confidence: 0.60),
    _CueTemplate(CueType.reEntry, 0.58, 0.65, 0.74, confidence: 0.60),
    _CueTemplate(CueType.mixOut, 0.78, 0.86, 0.92, confidence: 0.70),
    _CueTemplate(CueType.outro, 0.90, 0.94, 0.98, confidence: 0.65),
  ],
};

// ── Service ────────────────────────────────────────────────────────────────────

class CueAnalysisService {
  CueAnalysisService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  // Minimum BPM to treat as valid (prevents divide-by-zero, filters out 0.0)
  static const double _minBpm = 40.0;
  // Maximum BPM considered realistic for DJ music
  static const double _maxBpm = 300.0;
  // Minimum track duration in seconds to attempt cue generation
  static const double _minDurationSeconds = 30.0;
  // Maximum number of cue points returned (VirtualDJ limit)
  static const int _maxCues = 8;

  // ── Public entry point ──────────────────────────────────────────────────

  /// Generates hot cues for [track] using deterministic analysis.
  ///
  /// Never returns null — failures are surfaced via [CueGenerationStatus].
  Future<CueGenerationResult> generateCues(LibraryTrack track) async {
    // ── Validate metadata ──────────────────────────────────────────────────
    final validationError = _validateMetadata(track);
    if (validationError != null) {
      return CueGenerationResult.insufficientMetadata(track.id, validationError);
    }

    final double bpm = track.bpm;
    final double duration = track.durationSeconds;
    final double barDuration = (60.0 / bpm) * 4.0; // seconds per 4/4 bar

    // ── Genre classification ───────────────────────────────────────────────
    final genreGroup = _classifyGenre(track.genre);
    final templates = _templates[genreGroup]!;

    // ── Build confidence multiplier ────────────────────────────────────────
    // Reduce confidence when metadata quality is lower.
    final double confidenceMultiplier = _computeConfidenceMultiplier(
      bpm: bpm,
      duration: duration,
      genre: track.genre,
      genreGroup: genreGroup,
    );

    // ── Generate cue candidates ────────────────────────────────────────────
    final cues = <HotCue>[];
    for (var i = 0; i < math.min(templates.length, _maxCues); i++) {
      final template = templates[i];
      final double rawPositionSeconds = duration * template.idealFrac;

      // Snap to the nearest bar boundary (only when BPM is reliable)
      final double positionSeconds = bpm >= _minBpm
          ? _snapToBar(rawPositionSeconds, barDuration)
          : rawPositionSeconds;

      // Safety clamp: keep inside track + minimum 0.5 s gap from start/end
      final double safeDuration = math.max(duration - 1.0, 1.0);
      final double clampedPosition =
          positionSeconds.clamp(0.5, safeDuration - 0.5);

      final double cueConfidence =
          (template.confidence * confidenceMultiplier).clamp(0.0, 1.0);

      cues.add(HotCue(
        id: _uuid.v4(),
        trackId: track.id,
        cueIndex: i,
        cueType: template.type,
        label: template.type.label,
        timeSeconds: clampedPosition,
        confidence: cueConfidence,
        source: CueSource.genreTemplate,
        notes: _buildNotes(template.type, bpm, genreGroup, barDuration,
            duration * template.idealFrac),
        isSuggested: true,
        isWritten: false,
      ));
    }

    if (cues.isEmpty) {
      return CueGenerationResult(
        trackId: track.id,
        status: CueGenerationStatus.noCuesGenerated,
        cues: const [],
        generatedAt: DateTime.now(),
      );
    }

    // Sort by time ascending
    cues.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    return CueGenerationResult(
      trackId: track.id,
      status: CueGenerationStatus.success,
      cues: cues,
      aiUsed: false,
      generatedAt: DateTime.now(),
    );
  }

  /// Generates cues for a list of tracks (used for crate-level cue generation).
  ///
  /// Returns a map of trackId → CueGenerationResult.
  Future<Map<String, CueGenerationResult>> generateCuesForTracks(
      List<LibraryTrack> tracks) async {
    final results = <String, CueGenerationResult>{};
    for (final track in tracks) {
      results[track.id] = await generateCues(track);
    }
    return results;
  }

  // ── Private helpers ─────────────────────────────────────────────────────

  /// Returns an error string if track metadata is too weak to generate cues,
  /// or null if metadata is acceptable.
  String? _validateMetadata(LibraryTrack track) {
    if (track.durationSeconds < _minDurationSeconds) {
      return 'Track too short (${track.durationSeconds.toStringAsFixed(0)} s, minimum ${_minDurationSeconds.toInt()} s)';
    }
    if (track.bpm < _minBpm || track.bpm > _maxBpm) {
      // BPM zero or out of range — we can still produce duration-only cues
      // by using the generic template without bar snapping.
      // Only hard-fail if duration is also missing.
      if (track.durationSeconds <= 0) {
        return 'No BPM and no duration available';
      }
      // Proceed with degraded confidence; validation passes.
    }
    return null;
  }

  /// Snaps [rawSeconds] to the nearest bar boundary.
  ///
  /// The goal is for cue points to land on clean 4/4 bar beginnings.
  double _snapToBar(double rawSeconds, double barDuration) {
    if (barDuration <= 0) return rawSeconds;
    final double bars = rawSeconds / barDuration;
    final double snappedBars = bars.roundToDouble();
    return snappedBars * barDuration;
  }

  /// Classifies a genre string into a [_GenreGroup].
  _GenreGroup _classifyGenre(String genre) {
    final g = genre.toLowerCase().trim();
    if (g.isEmpty) return _GenreGroup.generic;

    if (_matchesAny(g, [
      'house', 'tech house', 'deep house', 'minimal', 'techno', 'edm',
      'progressive', 'electro', 'chicago', 'tribal', 'acid',
      'melodic techno', 'nu-disco', 'electronica', 'big room',
    ])) { return _GenreGroup.edmHouse; }

    if (_matchesAny(g, [
      'trance', 'psytrance', 'psy-trance', 'goa', 'uplifting',
      'vocal trance', 'progressive trance', 'hardtrance',
    ])) { return _GenreGroup.trance; }

    if (_matchesAny(g, [
      'hip-hop', 'hip hop', 'hiphop', 'rap', 'r&b', 'rnb', 'trap',
      'drill', 'boom bap', 'uk rap', 'afro-trap', 'lofi', 'lo-fi',
    ])) { return _GenreGroup.hiphopRnb; }

    if (_matchesAny(g, [
      'pop', 'dance-pop', 'dance pop', 'electropop', 'synth-pop',
      'synthpop', 'indie pop', 'k-pop', 'kpop', 'future bass',
    ])) { return _GenreGroup.popDance; }

    if (_matchesAny(g, [
      'afrobeats', 'afrohouse', 'afro house', 'amapiano', 'dancehall',
      'soca', 'afropop', 'afro-pop', 'highlife', 'zouk', 'kompa',
    ])) { return _GenreGroup.afrobeats; }

    if (_matchesAny(g, [
      'reggae', 'soul', 'funk', 'neo-soul', 'neosoul', 'blues',
      'r&b classic', 'motown', 'gospel', 'jazz', 'disco',
    ])) { return _GenreGroup.reggaeSoulFunk; }

    if (_matchesAny(g, [
      'drum and bass', 'drum & bass', 'd&b', 'dnb', 'jungle',
      'liquid', 'neurofunk', 'rollers', 'jump up',
    ])) { return _GenreGroup.drumsAndBass; }

    return _GenreGroup.generic;
  }

  bool _matchesAny(String genre, List<String> keywords) {
    for (final k in keywords) {
      if (genre.contains(k)) return true;
    }
    return false;
  }

  /// Returns a multiplier (0.4–1.0) based on metadata richness.
  double _computeConfidenceMultiplier({
    required double bpm,
    required double duration,
    required String genre,
    required _GenreGroup genreGroup,
  }) {
    double m = 1.0;

    // Penalise if BPM is zero / out of normal range
    if (bpm < _minBpm || bpm > _maxBpm) m -= 0.2;

    // Penalise if genre is unknown / generic
    if (genreGroup == _GenreGroup.generic) m -= 0.15;

    // Penalise if genre string is entirely empty
    if (genre.trim().isEmpty) m -= 0.1;

    // Small bonus for very clean BPM (integer-ish values are more reliable)
    if ((bpm - bpm.roundToDouble()).abs() < 0.5) m += 0.05;

    return m.clamp(0.4, 1.0);
  }

  /// Generates a developer-readable notes string for a cue.
  String _buildNotes(
    CueType type,
    double bpm,
    _GenreGroup genreGroup,
    double barDuration,
    double rawPosition,
  ) {
    final barNumber = barDuration > 0
        ? (rawPosition / barDuration).round()
        : null;

    final barNote = barNumber != null ? ', bar ~$barNumber' : '';
    return '${genreGroup.name} template, BPM ${bpm.toStringAsFixed(1)}$barNote';
  }
}
