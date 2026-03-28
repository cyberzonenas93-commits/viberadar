import 'dart:convert';
import 'dart:developer' as dev;

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import '../models/track.dart';

/// Set sequencing mode.
enum SetBuildMode {
  /// Pure algorithmic — greedy nearest-neighbor with transition scoring.
  algorithmic,

  /// AI-enhanced — uses GPT to reorder the algorithmically-selected tracks
  /// for better flow, energy arcs, and crowd psychology.
  aiEnhanced,
}

class SetBuilderService {
  /// Build a DJ set from the given tracks.
  ///
  /// In [SetBuildMode.algorithmic] mode (default), uses greedy nearest-neighbor
  /// with transition scoring. In [SetBuildMode.aiEnhanced] mode, first selects
  /// tracks algorithmically, then asks GPT to optimize the sequence for
  /// better flow, energy arcs, and storytelling.
  Future<SetBuildResult> buildSet({
    required List<Track> tracks,
    required int durationMinutes,
    required String genre,
    required String vibe,
    required double minBpm,
    required double maxBpm,
    int? yearFrom,
    int? yearTo,
    int? trackCount,
    SetBuildMode mode = SetBuildMode.algorithmic,
    String? openAiApiKey,
    String? openAiModel,
  }) async {
    final filtered = tracks.where((track) {
      final bpm = track.bpm.toDouble();
      if (bpm < minBpm || bpm > maxBpm) return false;
      if (genre != 'All' && track.genre != genre) return false;
      if (vibe != 'All' && track.vibe != vibe) return false;
      if (yearFrom != null && track.effectiveReleaseYear < yearFrom) return false;
      if (yearTo != null && track.effectiveReleaseYear > yearTo) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.energyLevel.compareTo(b.energyLevel));

    if (filtered.isEmpty) {
      return const SetBuildResult(tracks: [], mode: SetBuildMode.algorithmic);
    }

    // User-specified count takes priority; otherwise estimate from duration
    final targetCount = trackCount ?? (durationMinutes / 4).clamp(6, 200).round();
    final algorithmicResult = _algorithmicSelect(filtered, targetCount);

    if (mode == SetBuildMode.aiEnhanced && openAiApiKey != null && openAiApiKey.isNotEmpty) {
      try {
        final aiResult = await _aiResequence(
          algorithmicResult,
          genre: genre,
          vibe: vibe,
          durationMinutes: durationMinutes,
          apiKey: openAiApiKey,
          model: openAiModel ?? 'gpt-4o-mini',
        );
        if (aiResult != null && aiResult.isNotEmpty) {
          return SetBuildResult(
            tracks: aiResult,
            mode: SetBuildMode.aiEnhanced,
            aiRationale: 'AI optimized sequence for energy flow and harmonic compatibility',
          );
        }
      } catch (e) {
        dev.log('[SetBuilder] AI resequence failed, falling back to algorithmic: $e',
            name: 'SetBuilder');
      }
    }

    return SetBuildResult(tracks: algorithmicResult, mode: SetBuildMode.algorithmic);
  }

  /// Synchronous algorithmic build (legacy API, still used internally).
  List<Track> buildSetSync({
    required List<Track> tracks,
    required int durationMinutes,
    required String genre,
    required String vibe,
    required double minBpm,
    required double maxBpm,
    int? yearFrom,
    int? yearTo,
    int? trackCount,
  }) {
    final filtered = tracks.where((track) {
      final bpm = track.bpm.toDouble();
      if (bpm < minBpm || bpm > maxBpm) return false;
      if (genre != 'All' && track.genre != genre) return false;
      if (vibe != 'All' && track.vibe != vibe) return false;
      if (yearFrom != null && track.effectiveReleaseYear < yearFrom) return false;
      if (yearTo != null && track.effectiveReleaseYear > yearTo) return false;
      return true;
    }).toList()
      ..sort((a, b) => a.energyLevel.compareTo(b.energyLevel));

    if (filtered.isEmpty) return const [];

    final targetCount = trackCount ?? (durationMinutes / 4).clamp(6, 200).round();
    return _algorithmicSelect(filtered, targetCount);
  }

  List<Track> _algorithmicSelect(List<Track> filtered, int targetCount) {
    final initial = filtered.first;
    final selected = <Track>[initial];
    final remaining =
        filtered.whereNot((track) => track.id == initial.id).toList();

    while (selected.length < targetCount && remaining.isNotEmpty) {
      final current = selected.last;
      var bestIndex = 0;
      var bestScore = _mixTransitionScore(
        current,
        remaining[0],
        selected.length,
        targetCount,
      );

      for (var i = 1; i < remaining.length; i++) {
        final score = _mixTransitionScore(
          current,
          remaining[i],
          selected.length,
          targetCount,
        );
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }

      selected.add(remaining.removeAt(bestIndex));
    }

    return selected;
  }

  /// Ask GPT to reorder the selected tracks for better DJ flow.
  Future<List<Track>?> _aiResequence(
    List<Track> tracks, {
    required String genre,
    required String vibe,
    required int durationMinutes,
    required String apiKey,
    required String model,
  }) async {
    if (tracks.length < 3) return null;

    // Build a compact track list for GPT
    final trackList = tracks.asMap().entries.map((e) {
      final t = e.value;
      return '${e.key}: ${t.artist} - ${t.title} (${t.bpm} BPM, ${t.keySignature}, energy=${t.energyLevel.toStringAsFixed(2)}, genre=${t.genre})';
    }).join('\n');

    final systemPrompt =
        'You are a professional DJ set sequencer. Given a list of tracks with BPM, key, '
        'energy level, and genre, reorder them for the best DJ set flow.\n\n'
        'Rules:\n'
        '- Start with lower energy and build up\n'
        '- Keep BPM transitions smooth (±3-6 BPM between adjacent tracks)\n'
        '- Prefer harmonic compatibility (Camelot wheel: same number ±1, same letter)\n'
        '- Create a compelling energy arc with a peak in the second half\n'
        '- Genre-cluster where it makes sense, but allow smooth genre pivots\n'
        '- Target vibe: $vibe, target genre focus: $genre\n'
        '- Set duration: ~$durationMinutes minutes\n\n'
        'Return ONLY a JSON array of the track indices in the optimal order.\n'
        'Example: [3, 0, 5, 1, 4, 2]\n'
        'No explanation, just the JSON array.';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': 'Reorder these ${tracks.length} tracks:\n\n$trackList'},
        ],
        'temperature': 0.3,
        'max_tokens': 500,
      }),
    );

    if (response.statusCode != 200) {
      dev.log('[SetBuilder] GPT returned ${response.statusCode}: ${response.body}', name: 'SetBuilder');
      return null;
    }

    final data = jsonDecode(response.body);
    final content = data['choices']?[0]?['message']?['content'] as String? ?? '';

    // Extract JSON array from response
    final match = RegExp(r'\[[\d\s,]+\]').firstMatch(content);
    if (match == null) return null;

    final indices = (jsonDecode(match.group(0)!) as List).cast<int>();
    if (indices.length != tracks.length) return null;

    // Validate all indices are valid and unique
    final indexSet = indices.toSet();
    if (indexSet.length != tracks.length || indexSet.any((i) => i < 0 || i >= tracks.length)) {
      return null;
    }

    return indices.map((i) => tracks[i]).toList();
  }

  double _mixTransitionScore(
    Track current,
    Track candidate,
    int index,
    int targetCount,
  ) {
    final progressTarget = index / targetCount;
    final desiredEnergy = (0.35 + progressTarget * 0.55).clamp(0.2, 0.95);
    final energyFit = 1 - (candidate.energyLevel - desiredEnergy).abs();
    final bpmFit =
        1 - ((candidate.bpm - current.bpm).abs() / 24).clamp(0.0, 1.0);
    final harmonicFit = _harmonicCompatibility(
      current.keySignature,
      candidate.keySignature,
    );
    final trendFit = candidate.trendScore;

    return (energyFit * 0.35) +
        (bpmFit * 0.25) +
        (harmonicFit * 0.2) +
        (trendFit * 0.2);
  }

  double _harmonicCompatibility(String first, String second) {
    if (first == second) {
      return 1;
    }

    final firstCamelot = _toCamelot(first);
    final secondCamelot = _toCamelot(second);
    if (firstCamelot == null || secondCamelot == null) {
      return 0.55;
    }

    final sameLetter = firstCamelot.$2 == secondCamelot.$2;
    final sameNumber = firstCamelot.$1 == secondCamelot.$1;
    final distance = (firstCamelot.$1 - secondCamelot.$1).abs();
    final wrappedDistance = distance > 6 ? 12 - distance : distance;

    if (sameNumber && sameLetter) return 1;
    if (sameNumber && !sameLetter) return 0.92;
    if (sameLetter && wrappedDistance == 1) return 0.88;
    if (!sameLetter && wrappedDistance == 1) return 0.72;
    if (sameLetter && wrappedDistance == 2) return 0.6;
    return 0.4;
  }

  /// Convert standard key notation (C, Dm, Ab, etc.) or Camelot (8A, 12B)
  /// to a (number, letter) Camelot pair.
  (int, String)? _toCamelot(String key) {
    final trimmed = key.trim();

    // Already Camelot notation?
    final camelotMatch =
        RegExp(r'^(\d{1,2})([AB])$').firstMatch(trimmed.toUpperCase());
    if (camelotMatch != null) {
      return (int.parse(camelotMatch.group(1)!), camelotMatch.group(2)!);
    }

    // Standard key notation → Camelot
    // Major keys map to B side, minor keys map to A side
    const majorMap = {
      'C': 8,
      'Db': 3,
      'D': 10,
      'Eb': 5,
      'E': 12,
      'F': 7,
      'Gb': 2,
      'G': 9,
      'Ab': 4,
      'A': 11,
      'Bb': 6,
      'B': 1,
    };
    const minorMap = {
      'Cm': 5,
      'Dbm': 12,
      'Dm': 7,
      'Ebm': 2,
      'Em': 9,
      'Fm': 4,
      'Gbm': 11,
      'Gm': 6,
      'Abm': 1,
      'Am': 8,
      'Bbm': 3,
      'Bm': 10,
    };

    if (minorMap.containsKey(trimmed)) {
      return (minorMap[trimmed]!, 'A');
    }
    if (majorMap.containsKey(trimmed)) {
      return (majorMap[trimmed]!, 'B');
    }

    return null;
  }
}

/// Result of a set build operation.
class SetBuildResult {
  const SetBuildResult({
    required this.tracks,
    required this.mode,
    this.aiRationale,
  });

  final List<Track> tracks;
  final SetBuildMode mode;
  final String? aiRationale;

  bool get isAiEnhanced => mode == SetBuildMode.aiEnhanced;
  bool get isEmpty => tracks.isEmpty;
  int get length => tracks.length;
}
