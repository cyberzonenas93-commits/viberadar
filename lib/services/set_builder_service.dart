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
    }).toList()..sort((a, b) => a.energyLevel.compareTo(b.energyLevel));

    if (filtered.isEmpty) {
      return const [];
    }

    final targetCount = (durationMinutes / 4).clamp(6, 20).round();
    final initial = filtered.first;
    final selected = <Track>[initial];
    final remaining = filtered
        .whereNot((track) => track.id == initial.id)
        .toList();

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
    final bpmFit = 1 - ((candidate.bpm - current.bpm).abs() / 24).clamp(0, 1);
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

    final firstValue = _parseCamelot(first);
    final secondValue = _parseCamelot(second);
    if (firstValue == null || secondValue == null) {
      return 0.55;
    }

    final sameLetter = firstValue.$2 == secondValue.$2;
    final sameNumber = firstValue.$1 == secondValue.$1;
    // Camelot wheel wraps at 12, so 12→1 is adjacent.
    final distance = (firstValue.$1 - secondValue.$1).abs();
    final wrappedDistance = distance > 6 ? 12 - distance : distance;

    if (sameNumber && sameLetter) {
      return 1;
    }
    // Same number, different letter = relative major/minor switch (e.g. 8A↔8B).
    if (sameNumber && !sameLetter) {
      return 0.92;
    }
    // Adjacent on the wheel in the same mode (e.g. 8A→9A).
    if (sameLetter && wrappedDistance == 1) {
      return 0.88;
    }
    // One step on wheel + mode switch.
    if (!sameLetter && wrappedDistance == 1) {
      return 0.72;
    }
    // Two steps away, same mode.
    if (sameLetter && wrappedDistance == 2) {
      return 0.6;
    }
    return 0.4;
  }

  (int, String)? _parseCamelot(String key) {
    final match = RegExp(
      r'^(\d{1,2})([AB])$',
    ).firstMatch(key.trim().toUpperCase());
    if (match == null) {
      return null;
    }

    return (int.parse(match.group(1)!), match.group(2)!);
  }
}
