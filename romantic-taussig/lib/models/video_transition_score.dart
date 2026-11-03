enum VideoTransitionType {
  smoothVisualBlend,
  smoothMusicBlend,
  energyLift,
  energyDrop,
  bridgeTransition,
  hardCutCandidate,
  visualReset,
  lyricToPerformanceBridge,
  officialToLivePivot,
  riskyTransition,
  singalongBridge,
  peakTimeSlam,
  closingFlow,
}

extension VideoTransitionTypeLabel on VideoTransitionType {
  String get label {
    switch (this) {
      case VideoTransitionType.smoothVisualBlend:
        return 'Smooth Visual Blend';
      case VideoTransitionType.smoothMusicBlend:
        return 'Smooth Music Blend';
      case VideoTransitionType.energyLift:
        return 'Energy Lift';
      case VideoTransitionType.energyDrop:
        return 'Energy Drop';
      case VideoTransitionType.bridgeTransition:
        return 'Bridge Transition';
      case VideoTransitionType.hardCutCandidate:
        return 'Hard Cut';
      case VideoTransitionType.visualReset:
        return 'Visual Reset';
      case VideoTransitionType.lyricToPerformanceBridge:
        return 'Lyric→Performance Bridge';
      case VideoTransitionType.officialToLivePivot:
        return 'Official→Live Pivot';
      case VideoTransitionType.riskyTransition:
        return 'Risky';
      case VideoTransitionType.singalongBridge:
        return 'Singalong Bridge';
      case VideoTransitionType.peakTimeSlam:
        return 'Peak Time Slam';
      case VideoTransitionType.closingFlow:
        return 'Closing Flow';
    }
  }
}

enum VideoTransitionWarning {
  bpmGapTooLarge,
  harmonicClash,
  abruptVisualIntensityJump,
  introOutroMismatch,
  weakVisualContinuity,
  sourceSwitchFriction,
  likelyJarringTransition,
}

extension VideoTransitionWarningLabel on VideoTransitionWarning {
  String get label {
    switch (this) {
      case VideoTransitionWarning.bpmGapTooLarge:
        return 'BPM gap too large';
      case VideoTransitionWarning.harmonicClash:
        return 'Harmonic clash';
      case VideoTransitionWarning.abruptVisualIntensityJump:
        return 'Abrupt visual intensity jump';
      case VideoTransitionWarning.introOutroMismatch:
        return 'Intro/outro mismatch';
      case VideoTransitionWarning.weakVisualContinuity:
        return 'Weak visual continuity';
      case VideoTransitionWarning.sourceSwitchFriction:
        return 'Source switch friction (local ↔ YouTube)';
      case VideoTransitionWarning.likelyJarringTransition:
        return 'Likely jarring transition';
    }
  }
}

enum VideoTransitionMode {
  smooth,
  clubFlow,
  peakTime,
  openFormat,
  warmUp,
  closing,
  singalong,

  /// Prioritises visual smoothness over audio compatibility.
  visualContinuity,
}

extension VideoTransitionModeLabel on VideoTransitionMode {
  String get label {
    switch (this) {
      case VideoTransitionMode.smooth:
        return 'Smooth';
      case VideoTransitionMode.clubFlow:
        return 'Club Flow';
      case VideoTransitionMode.peakTime:
        return 'Peak Time';
      case VideoTransitionMode.openFormat:
        return 'Open Format';
      case VideoTransitionMode.warmUp:
        return 'Warm-Up';
      case VideoTransitionMode.closing:
        return 'Closing';
      case VideoTransitionMode.singalong:
        return 'Singalong';
      case VideoTransitionMode.visualContinuity:
        return 'Visual Continuity';
    }
  }
}

class VideoTransitionScore {
  const VideoTransitionScore({
    required this.fromTrackId,
    required this.toTrackId,
    required this.overallScore,
    required this.confidence,
    required this.type,
    required this.reasons,
    required this.warnings,
    this.sourceSwitchPenalty = 0.0,
    this.audioScore = 0.5,
    this.visualScore = 0.5,
  });

  final String fromTrackId;
  final String toTrackId;

  /// Combined score 0.0–1.0.
  final double overallScore;

  /// Confidence of this score estimate (0.0–1.0).
  final double confidence;

  final VideoTransitionType type;
  final List<String> reasons;
  final List<VideoTransitionWarning> warnings;

  /// 0.0 if same source type, 0.1 if different (local ↔ YouTube).
  final double sourceSwitchPenalty;

  /// Raw audio-based sub-score before weighting.
  final double audioScore;

  /// Raw visual-based sub-score before weighting.
  final double visualScore;

  // ── Computed ────────────────────────────────────────────────────────────────

  String get scoreLabel {
    if (overallScore >= 0.8) return 'Excellent';
    if (overallScore >= 0.65) return 'Good';
    if (overallScore >= 0.5) return 'OK';
    return 'Risky';
  }

  String get summary => '$scoreLabel — ${type.label}';

  // ── Serialization ───────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'fromTrackId': fromTrackId,
      'toTrackId': toTrackId,
      'overallScore': overallScore,
      'confidence': confidence,
      'type': type.name,
      'reasons': reasons,
      'warnings': warnings.map((w) => w.name).toList(),
      'sourceSwitchPenalty': sourceSwitchPenalty,
      'audioScore': audioScore,
      'visualScore': visualScore,
    };
  }

  factory VideoTransitionScore.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'smoothVisualBlend';
    final type = VideoTransitionType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => VideoTransitionType.smoothVisualBlend,
    );

    final rawWarnings = json['warnings'] as List? ?? [];
    final warnings = rawWarnings
        .map((w) => VideoTransitionWarning.values.firstWhere(
              (e) => e.name == w,
              orElse: () => VideoTransitionWarning.likelyJarringTransition,
            ))
        .toList();

    return VideoTransitionScore(
      fromTrackId: json['fromTrackId'] as String? ?? '',
      toTrackId: json['toTrackId'] as String? ?? '',
      overallScore: (json['overallScore'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      type: type,
      reasons: (json['reasons'] as List?)?.cast<String>() ?? const [],
      warnings: warnings,
      sourceSwitchPenalty:
          (json['sourceSwitchPenalty'] as num?)?.toDouble() ?? 0.0,
      audioScore: (json['audioScore'] as num?)?.toDouble() ?? 0.5,
      visualScore: (json['visualScore'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
