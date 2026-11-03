import '../models/track.dart';
import '../models/transition_score.dart';

class TransitionEngineService {
  // ── Genre Families ──────────────────────────────────────────────────────────
  static const List<List<String>> _genreFamilies = [
    ['house', 'techno', 'edm', 'tech house', 'deep house', 'progressive house', 'minimal techno'],
    ['trance', 'progressive trance', 'psytrance', 'uplifting trance'],
    ['hip hop', 'hiphop', 'hip-hop', 'r&b', 'rnb', 'trap', 'rap', 'drill'],
    ['pop', 'dance pop', 'dance-pop', 'electropop', 'synth-pop'],
    ['afrobeats', 'afro', 'amapiano', 'afro house', 'afro tech'],
    ['reggae', 'soul', 'funk', 'reggaeton', 'dancehall', 'gospel'],
    ['dnb', 'drum and bass', 'drum & bass', 'jungle', 'neurofunk', 'liquid dnb'],
  ];

  // ── BPM Scoring ─────────────────────────────────────────────────────────────

  double _scoreBpm(double fromBpm, double toBpm) {
    if (fromBpm <= 0 || toBpm <= 0) return 0.5;

    final delta = (fromBpm - toBpm).abs();

    // Check half-time / double-time relationships
    final doubleRatio = (fromBpm / toBpm - 2.0).abs() / 2.0;
    final halfRatio = (fromBpm / toBpm - 0.5).abs() / 0.5;

    if (doubleRatio <= 0.03) return 0.80;
    if (halfRatio <= 0.03) return 0.78;

    if (delta <= 1) return 1.0;
    if (delta <= 3) return 0.95;
    if (delta <= 6) return 0.88;
    if (delta <= 10) return 0.75;
    if (delta <= 15) return 0.60;
    if (delta <= 20) return 0.42;
    if (delta <= 30) return 0.25;
    return 0.10;
  }

  // ── Harmonic (Camelot) Scoring ───────────────────────────────────────────────

  /// Parse Camelot notation e.g. "8A", "11B", "1A"
  /// Returns (number, mode) or null on failure.
  (int, String)? _parseCamelot(String key) {
    final trimmed = key.trim();

    // Direct Camelot notation
    final camelotMatch = RegExp(r'^(\d{1,2})([AB])$').firstMatch(trimmed.toUpperCase());
    if (camelotMatch != null) {
      final num = int.tryParse(camelotMatch.group(1)!);
      if (num != null && num >= 1 && num <= 12) {
        return (num, camelotMatch.group(2)!);
      }
    }

    // Standard key notation → Camelot
    const majorMap = {
      'C': 8, 'Db': 3, 'D': 10, 'Eb': 5, 'E': 12, 'F': 7,
      'Gb': 2, 'G': 9, 'Ab': 4, 'A': 11, 'Bb': 6, 'B': 1,
    };
    const minorMap = {
      'Cm': 5, 'Dbm': 12, 'Dm': 7, 'Ebm': 2, 'Em': 9, 'Fm': 4,
      'Gbm': 11, 'Gm': 6, 'Abm': 1, 'Am': 8, 'Bbm': 3, 'Bm': 10,
    };

    if (minorMap.containsKey(trimmed)) return (minorMap[trimmed]!, 'A');
    if (majorMap.containsKey(trimmed)) return (majorMap[trimmed]!, 'B');

    return null;
  }

  double _scoreHarmonic(String fromKey, String toKey) {
    if (fromKey.isEmpty || toKey.isEmpty) return 0.5;

    final from = _parseCamelot(fromKey);
    final to = _parseCamelot(toKey);

    if (from == null || to == null) return 0.5; // Parse failure = neutral

    final (fromNum, fromMode) = from;
    final (toNum, toMode) = to;

    if (fromNum == toNum && fromMode == toMode) return 1.0; // Same key+mode

    // Energy boost: same number, different mode A↔B
    if (fromNum == toNum && fromMode != toMode) return 0.85;

    // Circular distance on wheel (1–12)
    final distance = (fromNum - toNum).abs();
    final wrappedDist = distance > 6 ? 12 - distance : distance;

    if (wrappedDist == 1 && fromMode == toMode) return 0.92; // Perfect 4th/5th
    if (wrappedDist == 2 && fromMode == toMode) return 0.65;
    if (wrappedDist == 3 && fromMode == toMode) return 0.40;
    return 0.15; // ±4+
  }

  // ── Genre Scoring ────────────────────────────────────────────────────────────

  int _getGenreFamily(String genre) {
    final g = genre.toLowerCase().trim();
    for (var i = 0; i < _genreFamilies.length; i++) {
      if (_genreFamilies[i].any((f) => g.contains(f) || f.contains(g))) {
        return i;
      }
    }
    return -1; // unknown
  }

  double _scoreGenre(String fromGenre, String toGenre) {
    final fromFamily = _getGenreFamily(fromGenre);
    final toFamily = _getGenreFamily(toGenre);

    if (fromFamily == -1 || toFamily == -1) return 0.5; // Unknown = neutral
    if (fromFamily == toFamily) return 0.9; // Same family
    // Adjacent families (defined as being next to each other in the list)
    if ((fromFamily - toFamily).abs() == 1) return 0.7;
    return 0.4; // Different families
  }

  // ── Vibe/Energy Scoring ──────────────────────────────────────────────────────

  double _estimateEnergy(Track track) {
    // If energyLevel is explicitly set to something other than default 0.5, use it
    if (track.energyLevel != 0.5) return track.energyLevel;

    // Otherwise estimate from genre + BPM
    final bpm = track.bpm.toDouble();
    double bpmFactor = 0.5;
    if (bpm > 0) {
      if (bpm < 80) {
        bpmFactor = 0.3;
      } else if (bpm < 100) {
        bpmFactor = 0.4;
      } else if (bpm < 120) {
        bpmFactor = 0.55;
      } else if (bpm < 140) {
        bpmFactor = 0.7;
      } else if (bpm < 160) {
        bpmFactor = 0.8;
      } else {
        bpmFactor = 0.9;
      }
    }

    final genreFamily = _getGenreFamily(track.genre);
    double genreFactor = 0.5;
    switch (genreFamily) {
      case 0: genreFactor = 0.75; // house/techno/edm
      case 1: genreFactor = 0.80; // trance
      case 2: genreFactor = 0.65; // hiphop/rnb/trap
      case 3: genreFactor = 0.60; // pop/dance-pop
      case 4: genreFactor = 0.65; // afrobeats/amapiano
      case 5: genreFactor = 0.50; // reggae/soul/funk
      case 6: genreFactor = 0.85; // dnb/jungle
      default: genreFactor = 0.5;
    }

    return (bpmFactor * 0.6 + genreFactor * 0.4).clamp(0.0, 1.0);
  }

  double _scoreVibe(Track from, Track to) {
    final fromEnergy = _estimateEnergy(from);
    final toEnergy = _estimateEnergy(to);
    final delta = toEnergy - fromEnergy;

    if (delta >= 0 && delta <= 0.15) return 0.95; // Small rise
    if (delta.abs() <= 0.05) return 0.90; // Flat
    if (delta > 0.15 && delta <= 0.30) return 0.80; // Moderate rise
    if (delta > 0.30) return 0.55; // Large rise
    if (delta < 0 && delta >= -0.15) return 0.75; // Small drop
    return 0.40; // Large drop
  }

  /// Whether vibe is rising (positive delta)
  bool _isVibeRising(Track from, Track to) {
    final fromEnergy = _estimateEnergy(from);
    final toEnergy = _estimateEnergy(to);
    return (toEnergy - fromEnergy) > 0.03;
  }

  /// Whether vibe is dropping (negative delta)
  bool _isVibeFalling(Track from, Track to) {
    final fromEnergy = _estimateEnergy(from);
    final toEnergy = _estimateEnergy(to);
    return (toEnergy - fromEnergy) < -0.03;
  }

  // ── Intro/Outro Suitability ─────────────────────────────────────────────────

  double _scoreIntroOutro(Track from, Track to) {
    // Heuristic: closer BPM = smoother mix in/out, also check for longer tracks
    final bpmDelta = (from.bpm - to.bpm).abs().toDouble();
    double bpmFactor = 1.0 - (bpmDelta / 30.0).clamp(0.0, 1.0);

    // Harmonic compatibility also helps intro/outro
    final harmonicFactor = _scoreHarmonic(from.keySignature, to.keySignature);

    return ((bpmFactor * 0.6) + (harmonicFactor * 0.4)).clamp(0.0, 1.0);
  }

  // ── Weight Dimensions ────────────────────────────────────────────────────────

  static const Map<TransitionMode, Map<TransitionDimension, double>> _modeWeights = {
    TransitionMode.smooth: {
      TransitionDimension.bpmCompatibility: 0.25,
      TransitionDimension.harmonicCompatibility: 0.30,
      TransitionDimension.genreCompatibility: 0.20,
      TransitionDimension.vibeCompatibility: 0.15,
      TransitionDimension.introOutroSuitability: 0.10,
    },
    TransitionMode.clubFlow: {
      TransitionDimension.bpmCompatibility: 0.30,
      TransitionDimension.harmonicCompatibility: 0.25,
      TransitionDimension.genreCompatibility: 0.15,
      TransitionDimension.vibeCompatibility: 0.20,
      TransitionDimension.introOutroSuitability: 0.10,
    },
    TransitionMode.peakTime: {
      TransitionDimension.bpmCompatibility: 0.20,
      TransitionDimension.harmonicCompatibility: 0.20,
      TransitionDimension.genreCompatibility: 0.15,
      TransitionDimension.vibeCompatibility: 0.35,
      TransitionDimension.introOutroSuitability: 0.10,
    },
    TransitionMode.openFormat: {
      TransitionDimension.bpmCompatibility: 0.25,
      TransitionDimension.harmonicCompatibility: 0.20,
      TransitionDimension.genreCompatibility: 0.10,
      TransitionDimension.vibeCompatibility: 0.30,
      TransitionDimension.introOutroSuitability: 0.15,
    },
    TransitionMode.warmUp: {
      TransitionDimension.bpmCompatibility: 0.20,
      TransitionDimension.harmonicCompatibility: 0.25,
      TransitionDimension.genreCompatibility: 0.20,
      TransitionDimension.vibeCompatibility: 0.25,
      TransitionDimension.introOutroSuitability: 0.10,
    },
    TransitionMode.closing: {
      TransitionDimension.bpmCompatibility: 0.15,
      TransitionDimension.harmonicCompatibility: 0.20,
      TransitionDimension.genreCompatibility: 0.20,
      TransitionDimension.vibeCompatibility: 0.30,
      TransitionDimension.introOutroSuitability: 0.15,
    },
    TransitionMode.singalong: {
      TransitionDimension.bpmCompatibility: 0.20,
      TransitionDimension.harmonicCompatibility: 0.25,
      TransitionDimension.genreCompatibility: 0.20,
      TransitionDimension.vibeCompatibility: 0.20,
      TransitionDimension.introOutroSuitability: 0.15,
    },
  };

  double _weighDimensions(
    Map<TransitionDimension, double> scores,
    TransitionMode mode,
  ) {
    final weights = _modeWeights[mode]!;
    double weighted = 0.0;
    double totalWeight = 0.0;

    for (final entry in weights.entries) {
      final score = scores[entry.key] ?? 0.5;
      weighted += score * entry.value;
      totalWeight += entry.value;
    }

    if (totalWeight == 0) return 0.5;
    return (weighted / totalWeight).clamp(0.0, 1.0);
  }

  // ── Reasons & Warnings ───────────────────────────────────────────────────────

  List<String> _buildReasons(
    Track from,
    Track to,
    Map<TransitionDimension, double> scores,
    TransitionMode mode,
  ) {
    final reasons = <String>[];

    final bpmScore = scores[TransitionDimension.bpmCompatibility] ?? 0.5;
    final harmonicScore = scores[TransitionDimension.harmonicCompatibility] ?? 0.5;
    final genreScore = scores[TransitionDimension.genreCompatibility] ?? 0.5;
    final vibeScore = scores[TransitionDimension.vibeCompatibility] ?? 0.5;

    final bpmDelta = (from.bpm - to.bpm).abs();
    if (bpmScore >= 0.88) {
      reasons.add('BPMs are closely matched (${from.bpm}→${to.bpm} BPM)');
    } else if (bpmScore >= 0.75) {
      reasons.add('BPMs are compatible ($bpmDelta BPM difference)');
    }

    if (harmonicScore >= 0.92) {
      reasons.add('Perfect harmonic match (${from.keySignature}→${to.keySignature})');
    } else if (harmonicScore >= 0.85) {
      reasons.add('Energy boost transition (relative keys)');
    } else if (harmonicScore >= 0.65) {
      reasons.add('Harmonically compatible keys');
    }

    if (genreScore >= 0.9) {
      reasons.add('Same genre family — seamless crowd continuity');
    } else if (genreScore >= 0.7) {
      reasons.add('Adjacent genres allow smooth pivot');
    }

    if (vibeScore >= 0.90) {
      reasons.add('Energy level stays consistent');
    } else if (vibeScore >= 0.80) {
      reasons.add('Natural energy build into next track');
    } else if (vibeScore >= 0.75) {
      reasons.add('Slight energy drop — good after peak');
    }

    if (reasons.isEmpty) {
      reasons.add('Transition scores within acceptable range');
    }

    return reasons;
  }

  List<String> _buildWarnings(
    Track from,
    Track to,
    Map<TransitionDimension, double> scores,
    TransitionMode mode,
  ) {
    final warnings = <String>[];

    final bpmScore = scores[TransitionDimension.bpmCompatibility] ?? 0.5;
    final harmonicScore = scores[TransitionDimension.harmonicCompatibility] ?? 0.5;
    final genreScore = scores[TransitionDimension.genreCompatibility] ?? 0.5;
    final vibeScore = scores[TransitionDimension.vibeCompatibility] ?? 0.5;
    // overall score is accessible via dimensionScores[setPhase] if needed

    final bpmDelta = (from.bpm - to.bpm).abs();
    if (bpmScore < 0.42) {
      warnings.add('Large BPM jump ($bpmDelta BPM) — consider pitching');
    } else if (bpmScore < 0.60) {
      warnings.add('Noticeable BPM shift ($bpmDelta BPM difference)');
    }

    if (harmonicScore < 0.40) {
      warnings.add('Harmonic clash risk — EQ cut recommended');
    } else if (harmonicScore < 0.65) {
      warnings.add('Keys may create tension — use brief neutral break');
    }

    if (genreScore < 0.4) {
      warnings.add('Genre shift — announce or use acapella bridge');
    }

    if (vibeScore < 0.55) {
      warnings.add('Significant energy change — crowd may react');
    }

    if (mode == TransitionMode.smooth && bpmScore < 0.75) {
      warnings.add('Smooth mode prefers tighter BPM range');
    }

    if (mode == TransitionMode.warmUp && _isVibeRising(from, to)) {
      final fromEnergy = _estimateEnergy(from);
      final toEnergy = _estimateEnergy(to);
      final delta = toEnergy - fromEnergy;
      if (delta > 0.3) {
        warnings.add('Large energy jump for warm-up phase — may rush crowd');
      }
    }

    return warnings;
  }

  // ── Transition Type Determination ────────────────────────────────────────────

  TransitionType _determineType(
    Track from,
    Track to,
    double overall,
    Map<TransitionDimension, double> scores,
    TransitionMode mode,
  ) {
    final bpmScore = scores[TransitionDimension.bpmCompatibility] ?? 0.5;
    final harmonicScore = scores[TransitionDimension.harmonicCompatibility] ?? 0.5;
    final genreScore = scores[TransitionDimension.genreCompatibility] ?? 0.5;
    final vibeScore = scores[TransitionDimension.vibeCompatibility] ?? 0.5;
    final vibeRising = _isVibeRising(from, to);
    final vibeFalling = _isVibeFalling(from, to);

    if (overall < 0.5) return TransitionType.riskyTransition;

    if (mode == TransitionMode.closing && overall >= 0.65) {
      return TransitionType.closing;
    }

    if (mode == TransitionMode.warmUp && overall >= 0.7) {
      return TransitionType.warmUpFlow;
    }

    if (mode == TransitionMode.singalong && overall >= 0.7) {
      return TransitionType.singalongBridge;
    }

    if (mode == TransitionMode.peakTime && vibeScore >= 0.65 && overall >= 0.65 && overall < 0.8) {
      return TransitionType.peakTimeSlam;
    }

    if (overall >= 0.8 && bpmScore >= 0.8 && harmonicScore >= 0.8) {
      return TransitionType.smoothBlend;
    }

    if (overall >= 0.75 && vibeRising) {
      return TransitionType.energyLift;
    }

    if (overall >= 0.75 && vibeFalling) {
      return TransitionType.energyDrop;
    }

    if (genreScore < 0.7 && overall >= 0.55) {
      return genreScore < 0.5
          ? TransitionType.genrePivot
          : TransitionType.bridgeTransition;
    }

    if (overall >= 0.6) {
      return TransitionType.bridgeTransition;
    }

    return TransitionType.hardCutCandidate;
  }

  // ── Technique Recommendation ─────────────────────────────────────────────────

  String? _recommendTechnique(
    TransitionType type,
    Map<TransitionDimension, double> scores,
  ) {
    final bpmScore = scores[TransitionDimension.bpmCompatibility] ?? 0.5;
    final harmonicScore = scores[TransitionDimension.harmonicCompatibility] ?? 0.5;

    switch (type) {
      case TransitionType.smoothBlend:
        return 'Long crossfade (8–16 bars)';
      case TransitionType.energyLift:
        return bpmScore >= 0.88 ? 'EQ swap on drop' : 'Filter sweep + crossfade';
      case TransitionType.energyDrop:
        return 'Slow crossfade, fade out highs';
      case TransitionType.bridgeTransition:
        return harmonicScore >= 0.65
            ? 'Quick blend with EQ cut'
            : 'Use acapella or instrumental bridge';
      case TransitionType.hardCutCandidate:
        return 'Hard cut on phrase boundary (8 or 16 bars)';
      case TransitionType.riskyTransition:
        return 'Avoid or use spoken word / sample buffer';
      case TransitionType.singalongBridge:
        return 'Overlap on familiar hook or chorus';
      case TransitionType.genrePivot:
        return 'Announce pivot or use genre-neutral break';
      case TransitionType.peakTimeSlam:
        return 'Drop cut — maximize impact on beat 1';
      case TransitionType.warmUpFlow:
        return 'Gentle crossfade (4–8 bars)';
      case TransitionType.closing:
        return 'Long smooth fade (16+ bars)';
    }
  }

  // ── Confidence Calculation ───────────────────────────────────────────────────

  double _calculateConfidence(Track from, Track to) {
    double confidence = 1.0;

    // Lower confidence if BPM is 0 (unknown)
    if (from.bpm <= 0 || to.bpm <= 0) confidence -= 0.2;

    // Lower confidence if keys are unknown/default
    if (from.keySignature == '--' || from.keySignature.isEmpty) confidence -= 0.15;
    if (to.keySignature == '--' || to.keySignature.isEmpty) confidence -= 0.15;

    // Lower confidence if genre is generic
    if (from.genre == 'Open Format' || from.genre.isEmpty) confidence -= 0.1;
    if (to.genre == 'Open Format' || to.genre.isEmpty) confidence -= 0.1;

    return confidence.clamp(0.3, 1.0);
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Score a pair of tracks for transition compatibility.
  TransitionScore scorePair(
    Track from,
    Track to, {
    TransitionMode mode = TransitionMode.smooth,
  }) {
    final bpmScore = _scoreBpm(from.bpm.toDouble(), to.bpm.toDouble());
    final harmonicScore = _scoreHarmonic(from.keySignature, to.keySignature);
    final genreScore = _scoreGenre(from.genre, to.genre);
    final vibeScore = _scoreVibe(from, to);
    final introOutroScore = _scoreIntroOutro(from, to);

    final dimensionScores = <TransitionDimension, double>{
      TransitionDimension.bpmCompatibility: bpmScore,
      TransitionDimension.harmonicCompatibility: harmonicScore,
      TransitionDimension.genreCompatibility: genreScore,
      TransitionDimension.vibeCompatibility: vibeScore,
      TransitionDimension.energyProgression: vibeScore,
      TransitionDimension.introOutroSuitability: introOutroScore,
      TransitionDimension.crowdMomentum: (vibeScore * 0.6 + genreScore * 0.4),
      TransitionDimension.setPhase: 0.5, // placeholder for set position
    };

    final overall = _weighDimensions(dimensionScores, mode).clamp(0.0, 1.0);

    // Store overall in setPhase dimension for type determination lookup
    dimensionScores[TransitionDimension.setPhase] = overall;

    final type = _determineType(from, to, overall, dimensionScores, mode);
    final reasons = _buildReasons(from, to, dimensionScores, mode);
    final warnings = _buildWarnings(from, to, dimensionScores, mode);
    final technique = _recommendTechnique(type, dimensionScores);
    final confidence = _calculateConfidence(from, to);

    // A bridge candidate scores well both as a continuation and as a pivot
    final isBridgeCandidate = type == TransitionType.bridgeTransition ||
        (overall >= 0.65 && genreScore < 0.7 && harmonicScore >= 0.65);

    return TransitionScore(
      fromTrackId: from.id,
      toTrackId: to.id,
      overallScore: overall,
      confidence: confidence,
      type: type,
      reasons: reasons,
      warnings: warnings,
      dimensionScores: dimensionScores,
      recommendedTechnique: technique,
      isBridgeCandidate: isBridgeCandidate,
    );
  }

  /// Rank candidate tracks for the next slot after [current].
  List<Track> rankNextTracks(
    Track current,
    List<Track> candidates, {
    TransitionMode mode = TransitionMode.smooth,
    int maxResults = 10,
  }) {
    final scored = candidates
        .where((t) => t.id != current.id)
        .map((t) => (track: t, score: scorePair(current, t, mode: mode)))
        .toList()
      ..sort((a, b) => b.score.overallScore.compareTo(a.score.overallScore));

    return scored.take(maxResults).map((e) => e.track).toList();
  }

  /// Find bridge tracks B such that A→B and B→C both score well.
  List<Track> findBridgeTracks(
    Track from,
    Track to,
    List<Track> pool, {
    TransitionMode mode = TransitionMode.smooth,
  }) {
    final bridges = <({Track track, double bridgeScore})>[];

    for (final candidate in pool) {
      if (candidate.id == from.id || candidate.id == to.id) continue;

      final aToB = scorePair(from, candidate, mode: mode);
      final bToC = scorePair(candidate, to, mode: mode);

      // Both hops need to be decent
      final bridgeScore = (aToB.overallScore + bToC.overallScore) / 2.0;
      if (aToB.overallScore >= 0.55 && bToC.overallScore >= 0.55) {
        bridges.add((track: candidate, bridgeScore: bridgeScore));
      }
    }

    bridges.sort((a, b) => b.bridgeScore.compareTo(a.bridgeScore));
    return bridges.map((e) => e.track).toList();
  }

  /// Build optimal sequence using greedy nearest-neighbor by transition score.
  List<Track> buildOptimalSequence(
    List<Track> tracks, {
    TransitionMode mode = TransitionMode.smooth,
  }) {
    if (tracks.isEmpty) return const [];
    if (tracks.length == 1) return List.from(tracks);

    final remaining = List<Track>.from(tracks);
    final sequence = <Track>[];

    // Start with the track that has the best average transition score to others
    Track? seed;
    double bestAvg = -1.0;
    for (final t in remaining) {
      double sum = 0.0;
      int count = 0;
      for (final other in remaining) {
        if (other.id == t.id) continue;
        sum += scorePair(t, other, mode: mode).overallScore;
        count++;
      }
      final avg = count > 0 ? sum / count : 0.0;
      if (avg > bestAvg) {
        bestAvg = avg;
        seed = t;
      }
    }

    sequence.add(seed!);
    remaining.removeWhere((t) => t.id == seed!.id);

    while (remaining.isNotEmpty) {
      final current = sequence.last;
      Track? bestNext;
      double bestScore = -1.0;

      for (final candidate in remaining) {
        final s = scorePair(current, candidate, mode: mode).overallScore;
        if (s > bestScore) {
          bestScore = s;
          bestNext = candidate;
        }
      }

      sequence.add(bestNext!);
      remaining.removeWhere((t) => t.id == bestNext!.id);
    }

    return sequence;
  }
}
