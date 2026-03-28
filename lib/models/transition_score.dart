// Transition type labels
enum TransitionType {
  smoothBlend,
  energyLift,
  energyDrop,
  bridgeTransition,
  hardCutCandidate,
  riskyTransition,
  singalongBridge,
  genrePivot,
  peakTimeSlam,
  warmUpFlow,
  closing,
}

extension TransitionTypeLabel on TransitionType {
  String get label {
    switch (this) {
      case TransitionType.smoothBlend:
        return 'Smooth Blend';
      case TransitionType.energyLift:
        return 'Energy Lift';
      case TransitionType.energyDrop:
        return 'Energy Drop';
      case TransitionType.bridgeTransition:
        return 'Bridge Transition';
      case TransitionType.hardCutCandidate:
        return 'Hard Cut';
      case TransitionType.riskyTransition:
        return 'Risky';
      case TransitionType.singalongBridge:
        return 'Singalong Bridge';
      case TransitionType.genrePivot:
        return 'Genre Pivot';
      case TransitionType.peakTimeSlam:
        return 'Peak Time Slam';
      case TransitionType.warmUpFlow:
        return 'Warm-Up Flow';
      case TransitionType.closing:
        return 'Closing';
    }
  }
}

// Dimension keys for per-dimension scores
enum TransitionDimension {
  bpmCompatibility,
  harmonicCompatibility,
  genreCompatibility,
  vibeCompatibility,
  energyProgression,
  introOutroSuitability,
  crowdMomentum,
  setPhase,
}

// The transition mode affects scoring weights
enum TransitionMode {
  smooth, // subtle low-friction
  clubFlow, // momentum and crowd continuity
  peakTime, // tolerate strong jumps for impact
  openFormat, // allow genre pivots
  warmUp, // lower-energy progression
  closing, // graceful landing
  singalong, // familiarity and hook continuity
}

class TransitionScore {
  const TransitionScore({
    required this.fromTrackId,
    required this.toTrackId,
    required this.overallScore,
    required this.confidence,
    required this.type,
    required this.reasons,
    required this.warnings,
    required this.dimensionScores,
    this.recommendedTechnique,
    this.isBridgeCandidate = false,
  });

  final String fromTrackId;
  final String toTrackId;
  final double overallScore; // 0.0–1.0
  final double confidence;
  final TransitionType type;
  final List<String> reasons;
  final List<String> warnings;
  final Map<TransitionDimension, double> dimensionScores;
  final String? recommendedTechnique;
  final bool isBridgeCandidate;

  String get scoreLabel {
    if (overallScore >= 0.8) return 'Excellent';
    if (overallScore >= 0.65) return 'Good';
    if (overallScore >= 0.5) return 'OK';
    return 'Risky';
  }

  String get summary => '$scoreLabel — ${type.label}';

  Map<String, dynamic> toJson() {
    return {
      'fromTrackId': fromTrackId,
      'toTrackId': toTrackId,
      'overallScore': overallScore,
      'confidence': confidence,
      'type': type.name,
      'reasons': reasons,
      'warnings': warnings,
      'dimensionScores': dimensionScores.map(
        (k, v) => MapEntry(k.name, v),
      ),
      'recommendedTechnique': recommendedTechnique,
      'isBridgeCandidate': isBridgeCandidate,
    };
  }

  factory TransitionScore.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'smoothBlend';
    final type = TransitionType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => TransitionType.smoothBlend,
    );

    final rawDimensions = json['dimensionScores'] as Map<String, dynamic>? ?? {};
    final dimensionScores = <TransitionDimension, double>{};
    for (final entry in rawDimensions.entries) {
      final dim = TransitionDimension.values.firstWhere(
        (d) => d.name == entry.key,
        orElse: () => TransitionDimension.bpmCompatibility,
      );
      dimensionScores[dim] = (entry.value as num?)?.toDouble() ?? 0.0;
    }

    return TransitionScore(
      fromTrackId: json['fromTrackId'] as String? ?? '',
      toTrackId: json['toTrackId'] as String? ?? '',
      overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      type: type,
      reasons: (json['reasons'] as List?)?.cast<String>() ?? const [],
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
      dimensionScores: dimensionScores,
      recommendedTechnique: json['recommendedTechnique'] as String?,
      isBridgeCandidate: json['isBridgeCandidate'] as bool? ?? false,
    );
  }
}
