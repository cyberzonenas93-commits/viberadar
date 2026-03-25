import 'package:collection/collection.dart';

import '../models/track.dart';

class SetBuilderService {
  List<Track> buildSet({
    required List<Track> tracks,
    required int durationMinutes,
    required String genre,
    required String vibe,
    required double minBpm,
    required double maxBpm,
  }) {
    final filtered = tracks.where((track) {
      final bpm = track.bpm.toDouble();
      return bpm >= minBpm &&
          bpm <= maxBpm &&
          (genre == 'All' || track.genre == genre) &&
          (vibe == 'All' || track.vibe == vibe);
    }).toList()
      ..sort((a, b) => a.energyLevel.compareTo(b.energyLevel));

    if (filtered.isEmpty) {
      return const [];
    }

    // ~4 min per track on average, allow up to 45 tracks for long sets
    final targetCount = (durationMinutes / 4).clamp(6, 45).round();
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
