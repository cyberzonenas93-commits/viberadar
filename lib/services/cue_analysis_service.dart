import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/hot_cue.dart';
import '../models/library_track.dart';
import '../models/track.dart';
import 'ai_copilot_service.dart';

// ── Genre family ───────────────────────────────────────────────────────────────
enum _GenreFamily { houseEdm, amapiano, afrobeats, hipHopRnb, latin, unknown }

/// Deterministic-first hot cue generation engine.
///
/// Analysis tiers (in order of trust):
///   1. BPM-grid based bar/phrase timing  (highest precision when BPM is known)
///   2. Genre-specific structural templates
///   3. Duration-percentage fallbacks      (when BPM is unknown)
///   4. AI ranking of deterministic candidates (optional, never fabricates timestamps)
class CueAnalysisService {
  CueAnalysisService({AiCopilotService? aiService})
      : _ai = aiService ?? AiCopilotService();

  final AiCopilotService _ai;

  // ── Tunable constants ──────────────────────────────────────────────────────
  // These were previously scattered as magic numbers. Centralising them makes
  // DJ-behaviour tuning a one-line change.

  /// VirtualDJ supports up to 8 hot cue slots (0-7).
  static const int maxCueSlots = 8;

  /// Base confidence when BPM is known (BPM-grid cues are trustworthy).
  static const double baseConfidenceWithBpm = 0.75;

  /// Base confidence when BPM is unknown (duration-only cues are estimates).
  static const double baseConfidenceNoBpm = 0.45;

  /// A cue is flagged "weak" below this confidence.
  static const double weakConfidenceThreshold = 0.6;

  /// Minimum spacing between cues — avoids near-duplicate markers.
  static const double minCueSpacingSeconds = 3.0;

  /// Minimum track duration (sec) for duration-based cue heuristics.
  static const double minAnalyzableDurationSec = 10.0;

  /// Fallback bar length (sec) when BPM is unknown. 8s ≈ 2 bars at 120 BPM.
  static const double fallbackBarLengthSeconds = 8.0;

  /// AI request timeout — short enough not to block UI, long enough for GPT-4.
  static const Duration aiRequestTimeout = Duration(seconds: 20);

  /// Max concurrent AI ranking requests when analysing a batch. Keeps us well
  /// under OpenAI's per-minute rate limits and avoids a 100-track stampede.
  static const int maxBatchConcurrency = 4;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Generate cue candidates for a single local track.
  /// [cloudTrack] provides optional enrichment (genre, energy, bpm override).
  /// [useAi] enables GPT-assisted ranking of deterministic candidates.
  Future<CueGenerationResult> analyzeTrack(
    LibraryTrack localTrack, {
    Track? cloudTrack,
    bool useAi = true,
  }) async {
    final bpm = localTrack.bpm > 0
        ? localTrack.bpm
        : (cloudTrack?.bpm.toDouble() ?? 0.0);
    final duration = localTrack.durationSeconds > 0 ? localTrack.durationSeconds : 0.0;
    final genre = localTrack.genre.isNotEmpty
        ? localTrack.genre
        : (cloudTrack?.genre ?? '');
    final energy = cloudTrack != null
        ? cloudTrack.energyLevel.toDouble()
        : _estimateEnergy(bpm, genre);

    final family   = _classifyGenre(genre, bpm);
    // 60/bpm = seconds per beat; *4 = one bar in 4/4.
    final barLen   = bpm > 0 ? (60.0 / bpm * 4) : fallbackBarLengthSeconds;
    final phrase   = barLen * 4;
    final baseConf = bpm > 0 ? baseConfidenceWithBpm : baseConfidenceNoBpm;
    final hasDur   = duration > minAnalyzableDurationSec;

    var candidates = _buildCandidates(
      trackId: localTrack.id,
      bpm: bpm,
      duration: duration,
      family: family,
      barLen: barLen,
      phrase: phrase,
      energy: energy,
      baseConf: baseConf,
      hasDur: hasDur,
    );

    String? aiWarning;
    if (useAi && candidates.isNotEmpty) {
      try {
        candidates = await _aiRankCandidates(
          candidates: candidates,
          title: localTrack.title,
          artist: localTrack.artist,
          genre: genre,
          bpm: bpm,
          duration: duration,
        );
      } on TimeoutException catch (e, st) {
        developer.log('AI cue ranking timed out for "${localTrack.title}"',
            name: 'CueAnalysisService', error: e, stackTrace: st);
        aiWarning = 'AI ranking timed out — showing deterministic cues.';
      } on FormatException catch (e, st) {
        developer.log('AI cue ranking returned malformed JSON',
            name: 'CueAnalysisService', error: e, stackTrace: st);
        aiWarning = 'AI ranking returned unexpected data — showing deterministic cues.';
      } catch (e, st) {
        developer.log('AI cue ranking failed for "${localTrack.title}"',
            name: 'CueAnalysisService', error: e, stackTrace: st);
        aiWarning = 'AI ranking unavailable — showing deterministic cues.';
      }
    }

    // Assign sequential cue slot indexes (VirtualDJ supports maxCueSlots slots).
    final finalCues = candidates.take(maxCueSlots).toList();
    for (var i = 0; i < finalCues.length; i++) {
      finalCues[i] = finalCues[i].copyWith(cueIndex: i);
    }

    final hasWeak = finalCues.any((c) => c.confidence < weakConfidenceThreshold);
    final warning = aiWarning ?? (bpm <= 0
        ? 'No BPM detected — cue timing is estimated from track duration only.'
        : null);

    return CueGenerationResult(
      trackId:           localTrack.id,
      trackTitle:        localTrack.title,
      trackArtist:       localTrack.artist,
      cues:              finalCues,
      hasWeakConfidence: hasWeak,
      warning:           warning,
      localFilePath:     localTrack.filePath,
      generatedAt:       DateTime.now(),
    );
  }

  /// Analyze a batch of tracks (crate or playlist) with progress reporting.
  ///
  /// When [useAi] is true, up to [maxBatchConcurrency] tracks are analysed in
  /// parallel. Results are returned in the same order as [tracks] regardless
  /// of completion order. Progress fires once per completed track.
  Future<List<CueGenerationResult>> analyzeBatch(
    List<LibraryTrack> tracks, {
    List<Track> cloudTracks = const [],
    bool useAi = true,
    void Function(int done, int total)? onProgress,
  }) async {
    final cloudMap = {for (final t in cloudTracks) t.id: t};
    final total    = tracks.length;
    final results  = List<CueGenerationResult?>.filled(total, null);
    var done = 0;

    // Simple semaphore: bounded pool of worker futures pulling from a shared
    // index. Preserves input order via [results] indexing.
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= total) return;
        final result = await analyzeTrack(
          tracks[i],
          cloudTrack: cloudMap[tracks[i].id],
          useAi: useAi,
        );
        results[i] = result;
        done++;
        onProgress?.call(done, total);
      }
    }

    final workerCount = total < maxBatchConcurrency ? total : maxBatchConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<CueGenerationResult>();
  }

  // ── Genre classification ───────────────────────────────────────────────────

  _GenreFamily _classifyGenre(String genre, double bpm) {
    final g = genre.toLowerCase();
    if (g.contains('amapiano'))                                         return _GenreFamily.amapiano;
    if (g.contains('afrobeat') || g.contains('afro beat') ||
        g.contains('afropop')  || g.contains('afro pop')) {
      return _GenreFamily.afrobeats;
    }
    if (g.contains('house') || g.contains('techno') ||
        g.contains('edm')   || g.contains('trance') ||
        g.contains('drum and bass') || g.contains('dnb') ||
        g.contains('electronic')) {
      return _GenreFamily.houseEdm;
    }
    if (g.contains('hip') || g.contains('rap') || g.contains('r&b') ||
        g.contains('rnb')  || g.contains('soul') || g.contains('trap')) {
      return _GenreFamily.hipHopRnb;
    }
    if (g.contains('latin') || g.contains('reggaeton') ||
        g.contains('salsa') || g.contains('bachata')) {
      return _GenreFamily.latin;
    }
    // BPM-based fallback
    if (bpm >= 120 && bpm <= 155) return _GenreFamily.houseEdm;
    if (bpm >= 95  && bpm < 120)  return _GenreFamily.afrobeats;
    if (bpm >= 60  && bpm < 95)   return _GenreFamily.hipHopRnb;
    return _GenreFamily.unknown;
  }

  double _estimateEnergy(double bpm, String genre) {
    if (bpm >= 130) return 0.85;
    if (bpm >= 120) return 0.75;
    if (bpm >= 100) return 0.65;
    return 0.5;
  }

  // ── Candidate dispatcher ───────────────────────────────────────────────────

  List<HotCue> _buildCandidates({
    required String trackId,
    required double bpm,
    required double duration,
    required _GenreFamily family,
    required double barLen,
    required double phrase,
    required double energy,
    required double baseConf,
    required bool hasDur,
  }) {
    switch (family) {
      case _GenreFamily.houseEdm:  return _houseTemplate(trackId, barLen, duration, baseConf, hasDur);
      case _GenreFamily.amapiano:  return _amapianoTemplate(trackId, barLen, duration, baseConf, hasDur);
      case _GenreFamily.afrobeats: return _afrobeatsTemplate(trackId, barLen, duration, baseConf, hasDur);
      case _GenreFamily.hipHopRnb: return _hipHopTemplate(trackId, barLen, duration, baseConf, hasDur);
      case _GenreFamily.latin:     return _latinTemplate(trackId, barLen, duration, baseConf, hasDur);
      case _GenreFamily.unknown:   return _unknownTemplate(trackId, duration, baseConf, hasDur);
    }
  }

  // ── Genre templates ────────────────────────────────────────────────────────

  List<HotCue> _houseTemplate(
      String tid, double barLen, double dur, double bc, bool hasDur) {
    final cues = <HotCue>[
      _cue(tid, CueType.intro,     'Intro',      0.0,              bc * 0.85, CueSource.genreTemplate),
      _cue(tid, CueType.mixIn,     'Mix In',     barLen * 8,       bc,        CueSource.bpmHeuristic,
           notes: 'Clean 8-bar loop point for incoming mix'),
      _cue(tid, CueType.drop,      'First Drop', barLen * 32,      bc,        CueSource.bpmHeuristic,
           notes: 'Typical house intro ends at 32 bars'),
    ];
    if (!hasDur || dur > barLen * 80) {
      cues.add(_cue(tid, CueType.breakdown, 'Breakdown', barLen * 64, bc * 0.8, CueSource.bpmHeuristic));
    }
    if (!hasDur || dur > barLen * 112) {
      cues.add(_cue(tid, CueType.reEntry,   'Re-Entry',  barLen * 96, bc,       CueSource.bpmHeuristic,
           notes: 'Build → second drop re-entry'));
    }
    if (hasDur && dur > barLen * 40) {
      cues.add(_cue(tid, CueType.mixOut, 'Mix Out',  dur - barLen * 32, bc * 0.9, CueSource.durationHeuristic,
           notes: 'Leaves 32 bars for outgoing mix'));
      cues.add(_cue(tid, CueType.outro,  'Outro',    dur - barLen * 8,  bc * 0.82, CueSource.durationHeuristic));
    }
    return _filterValid(cues, dur);
  }

  List<HotCue> _amapianoTemplate(
      String tid, double barLen, double dur, double bc, bool hasDur) {
    final cues = <HotCue>[
      _cue(tid, CueType.intro,     'Intro',    0.0,          bc * 0.85, CueSource.genreTemplate),
      _cue(tid, CueType.mixIn,     'Mix In',   barLen * 4,   bc,        CueSource.bpmHeuristic,
           notes: 'Log drum intro — clean mix point'),
      _cue(tid, CueType.vocalIn,   'Vocal In', barLen * 16,  bc * 0.8,  CueSource.bpmHeuristic,
           notes: 'Vocals typically enter over the log drum groove'),
      _cue(tid, CueType.hook,      'Hook',     barLen * 32,  bc,        CueSource.bpmHeuristic),
    ];
    if (!hasDur || dur > barLen * 80) {
      cues.add(_cue(tid, CueType.breakdown, 'Breakdown', barLen * 64, bc * 0.75, CueSource.bpmHeuristic));
    }
    if (!hasDur || dur > barLen * 96) {
      cues.add(_cue(tid, CueType.reEntry, 'Re-Entry', barLen * 80, bc, CueSource.bpmHeuristic));
    }
    if (hasDur && dur > barLen * 32) {
      cues.add(_cue(tid, CueType.mixOut, 'Mix Out', dur - barLen * 24, bc * 0.85, CueSource.durationHeuristic));
    }
    return _filterValid(cues, dur);
  }

  List<HotCue> _afrobeatsTemplate(
      String tid, double barLen, double dur, double bc, bool hasDur) {
    final cues = <HotCue>[
      _cue(tid, CueType.intro,   'Intro',       0.0,          bc * 0.85, CueSource.genreTemplate),
      _cue(tid, CueType.mixIn,   'Mix In',       barLen * 4,   bc,        CueSource.bpmHeuristic),
      _cue(tid, CueType.vocalIn, 'Vocal In',     barLen * 8,   bc * 0.8,  CueSource.bpmHeuristic,
           notes: 'Afrobeats vocals often enter at 8 bars'),
      _cue(tid, CueType.hook,    'Hook / Chorus', barLen * 24, bc,        CueSource.bpmHeuristic),
    ];
    if (!hasDur || dur > barLen * 60) {
      cues.add(_cue(tid, CueType.breakdown, 'Mid Break', barLen * 48, bc * 0.7, CueSource.bpmHeuristic));
    }
    if (hasDur && dur > barLen * 28) {
      cues.add(_cue(tid, CueType.mixOut, 'Mix Out', dur - barLen * 16, bc * 0.85, CueSource.durationHeuristic));
    }
    return _filterValid(cues, dur);
  }

  List<HotCue> _hipHopTemplate(
      String tid, double barLen, double dur, double bc, bool hasDur) {
    final cues = <HotCue>[
      _cue(tid, CueType.intro,   'Intro',   0.0,          bc * 0.85, CueSource.genreTemplate),
      _cue(tid, CueType.mixIn,   'Mix In',  barLen * 4,   bc,        CueSource.bpmHeuristic,
           notes: 'Clean beat entry point'),
      _cue(tid, CueType.vocalIn, 'Verse 1', barLen * 8,   bc * 0.8,  CueSource.bpmHeuristic),
      _cue(tid, CueType.hook,    'Hook',    barLen * 24,  bc,        CueSource.bpmHeuristic),
    ];
    if (!hasDur || dur > barLen * 48) {
      cues.add(_cue(tid, CueType.reEntry, 'Verse 2', barLen * 40, bc * 0.75, CueSource.bpmHeuristic));
    }
    if (hasDur && dur > barLen * 24) {
      cues.add(_cue(tid, CueType.outro, 'Outro', dur - barLen * 8, bc * 0.7, CueSource.durationHeuristic));
    }
    return _filterValid(cues, dur);
  }

  List<HotCue> _latinTemplate(
      String tid, double barLen, double dur, double bc, bool hasDur) {
    final cues = <HotCue>[
      _cue(tid, CueType.intro,   'Intro',   0.0,         bc * 0.85, CueSource.genreTemplate),
      _cue(tid, CueType.mixIn,   'Mix In',  barLen * 8,  bc,        CueSource.bpmHeuristic),
      _cue(tid, CueType.vocalIn, 'Vocal In',barLen * 16, bc * 0.8,  CueSource.bpmHeuristic),
      _cue(tid, CueType.hook,    'Coro',    barLen * 32, bc,        CueSource.bpmHeuristic),
    ];
    if (hasDur && dur > barLen * 40) {
      cues.add(_cue(tid, CueType.mixOut, 'Mix Out', dur - barLen * 16, bc * 0.85, CueSource.durationHeuristic));
    }
    return _filterValid(cues, dur);
  }

  List<HotCue> _unknownTemplate(
      String tid, double dur, double bc, bool hasDur) {
    final conf = bc * 0.5; // Lower confidence — no genre information
    final cues = <HotCue>[
      _cue(tid, CueType.intro, 'Intro', 0.0, conf, CueSource.durationHeuristic),
    ];
    if (hasDur) {
      cues.addAll([
        _cue(tid, CueType.mixIn,    'Mix In',    dur * 0.05, conf, CueSource.durationHeuristic),
        _cue(tid, CueType.hook,     'Hook',      dur * 0.30, conf, CueSource.durationHeuristic),
        _cue(tid, CueType.breakdown,'Breakdown', dur * 0.55, conf, CueSource.durationHeuristic),
        _cue(tid, CueType.mixOut,   'Mix Out',   dur * 0.85, conf, CueSource.durationHeuristic),
      ]);
    }
    return _filterValid(cues, dur);
  }

  // ── Utility helpers ────────────────────────────────────────────────────────

  HotCue _cue(String trackId, CueType type, String label, double timeSec,
      double confidence, CueSource source, {String? notes}) {
    return HotCue(
      trackId:    trackId,
      cueIndex:   0,
      cueType:    type,
      label:      label,
      timeSeconds: timeSec < 0 ? 0 : timeSec,
      confidence: confidence.clamp(0.0, 1.0),
      source:     source,
      notes:      notes,
    );
  }

  List<HotCue> _filterValid(List<HotCue> cues, double duration) {
    var f = cues.where((c) => c.timeSeconds >= 0).toList();
    if (duration > 0) f = f.where((c) => c.timeSeconds < duration).toList();
    f.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
    // Remove cues within minCueSpacingSeconds of each other (keep earlier one
    // which has higher priority).
    final out = <HotCue>[];
    for (final c in f) {
      if (out.isEmpty ||
          (c.timeSeconds - out.last.timeSeconds).abs() > minCueSpacingSeconds) {
        out.add(c);
      }
    }
    return out;
  }

  // ── AI ranking (optional) ──────────────────────────────────────────────────
  // AI NEVER fabricates timestamps — it only re-ranks deterministic candidates
  // and adjusts confidence scores based on genre/style knowledge.

  Future<List<HotCue>> _aiRankCandidates({
    required List<HotCue> candidates,
    required String title,
    required String artist,
    required String genre,
    required double bpm,
    required double duration,
  }) async {
    final apiKey = await _ai.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) return candidates;
    final model = await _ai.getModel();

    final desc = candidates.asMap().entries.map((e) {
      final c = e.value;
      return '${e.key}: ${c.cueType.label} @ ${c.timestampFormatted} '
             '"${c.label}" (conf: ${c.confidence.toStringAsFixed(2)}, src: ${c.source.label})';
    }).join('\n');

    final durFmt = duration > 0
        ? '${(duration ~/ 60)}:${(duration.toInt() % 60).toString().padLeft(2, '0')}'
        : 'unknown';

    final prompt =
        'You are a professional DJ cue point advisor.\n'
        'Track: "$title" by $artist | Genre: $genre | '
        'BPM: ${bpm > 0 ? bpm.toStringAsFixed(1) : "unknown"} | Duration: $durFmt\n\n'
        'Deterministic cue candidates:\n$desc\n\n'
        'Return a JSON object with key "ranked" containing an array of ALL candidates '
        'ordered by DJ usefulness. Each item: {"index": N, "confidence": 0.00–1.00, "notes": "reason"}. '
        'Adjust confidence ±0.15 max. Include all candidates. Valid JSON only.';

    try {
      final resp = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': 'DJ intelligence assistant. Return only valid JSON.'},
            {'role': 'user',   'content': prompt},
          ],
          'max_tokens': 500,
          'temperature': 0.2,
          'response_format': {'type': 'json_object'},
        }),
      ).timeout(aiRequestTimeout);

      if (resp.statusCode == 200) {
        final json    = jsonDecode(resp.body) as Map<String, dynamic>;
        final content = json['choices'][0]['message']['content'] as String;
        final decoded = jsonDecode(content);
        final list    = decoded is List ? decoded : decoded['ranked'];
        if (list is List) {
          final reordered = <HotCue>[];
          for (final item in list) {
            if (item is! Map<String, dynamic>) continue;
            final idx = item['index'] as int?;
            if (idx == null || idx < 0 || idx >= candidates.length) continue;
            var c = candidates[idx];
            final adj   = (item['confidence'] as num?)?.toDouble();
            final notes = item['notes'] as String?;
            if (adj   != null) c = c.copyWith(confidence: adj.clamp(0.0, 1.0));
            if (notes != null && notes.isNotEmpty) c = c.copyWith(notes: notes);
            c = c.copyWith(source: CueSource.aiRanking);
            reordered.add(c);
          }
          if (reordered.length == candidates.length) {
            // Re-sort chronologically — AI reorders priority, DJ needs time order
            reordered.sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));
            return reordered;
          }
        }
      }
    } on TimeoutException {
      // Surfaced to the caller via the outer try/catch in analyzeTrack.
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e, st) {
      developer.log('Unexpected error in _aiRankCandidates',
          name: 'CueAnalysisService', error: e, stackTrace: st);
      // Non-blocking; fall through to return original candidates so cue
      // generation still succeeds with deterministic results.
    }
    return candidates;
  }
}
