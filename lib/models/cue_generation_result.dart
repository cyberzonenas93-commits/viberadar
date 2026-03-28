// ── CueGenerationResult ───────────────────────────────────────────────────────
//
// Returned by CueAnalysisService after processing a single track.

import 'package:viberadar/models/hot_cue.dart';

enum CueGenerationStatus {
  /// Cues were successfully generated.
  success,

  /// Track has insufficient metadata (no BPM, no duration) to generate cues.
  insufficientMetadata,

  /// AI ranking was requested but failed; deterministic cues still returned.
  aiRankingFailed,

  /// No cues could be placed (edge case: very short track, etc.).
  noCuesGenerated,
}

class CueGenerationResult {
  const CueGenerationResult({
    required this.trackId,
    required this.status,
    required this.cues,
    this.errorMessage,
    this.aiUsed = false,
    this.generatedAt,
  });

  /// The track this result belongs to.
  final String trackId;

  final CueGenerationStatus status;

  /// Ordered list of suggested cue points (sorted by timeSeconds ascending).
  final List<HotCue> cues;

  /// Non-null only when status is [CueGenerationStatus.aiRankingFailed] or
  /// [CueGenerationStatus.insufficientMetadata].
  final String? errorMessage;

  /// Whether GPT ranking was applied on top of the deterministic candidates.
  final bool aiUsed;

  /// Wall-clock time at which generation completed.
  final DateTime? generatedAt;

  // ── Convenience getters ──────────────────────────────────────────────────

  bool get isSuccess => status == CueGenerationStatus.success;

  bool get hasError =>
      status == CueGenerationStatus.insufficientMetadata ||
      status == CueGenerationStatus.noCuesGenerated;

  /// Number of high-confidence cues (confidence ≥ 0.75).
  int get highConfidenceCount =>
      cues.where((c) => c.confidence >= 0.75).length;

  /// Human-readable summary for snackbars / logs.
  String get summary {
    switch (status) {
      case CueGenerationStatus.success:
        final aiSuffix = aiUsed ? ' (AI-ranked)' : '';
        return '${cues.length} cue${cues.length == 1 ? '' : 's'} generated$aiSuffix';
      case CueGenerationStatus.aiRankingFailed:
        return '${cues.length} cues generated (AI ranking failed)';
      case CueGenerationStatus.insufficientMetadata:
        return 'Could not generate cues: ${errorMessage ?? 'insufficient metadata'}';
      case CueGenerationStatus.noCuesGenerated:
        return 'No cues could be placed for this track';
    }
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'status': status.name,
        'cues': cues.map((c) => c.toJson()).toList(),
        if (errorMessage != null) 'errorMessage': errorMessage,
        'aiUsed': aiUsed,
        if (generatedAt != null)
          'generatedAt': generatedAt!.toIso8601String(),
      };

  factory CueGenerationResult.fromJson(Map<String, dynamic> j) =>
      CueGenerationResult(
        trackId: j['trackId'] as String,
        status: CueGenerationStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => CueGenerationStatus.success,
        ),
        cues: (j['cues'] as List<dynamic>)
            .map((e) => HotCue.fromJson(e as Map<String, dynamic>))
            .toList(),
        errorMessage: j['errorMessage'] as String?,
        aiUsed: j['aiUsed'] as bool? ?? false,
        generatedAt: j['generatedAt'] != null
            ? DateTime.tryParse(j['generatedAt'] as String)
            : null,
      );

  /// Convenience factory for a failure result when metadata is missing.
  factory CueGenerationResult.insufficientMetadata(
    String trackId,
    String reason,
  ) =>
      CueGenerationResult(
        trackId: trackId,
        status: CueGenerationStatus.insufficientMetadata,
        cues: const [],
        errorMessage: reason,
        generatedAt: DateTime.now(),
      );
}
