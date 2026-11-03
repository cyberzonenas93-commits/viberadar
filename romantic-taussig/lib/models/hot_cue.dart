// ── Cue type ──────────────────────────────────────────────────────────────────

/// The functional role of a cue point in a DJ set.
enum CueType {
  /// Beginning of track — safe starting point.
  intro,

  /// Good point to start a mix into this track.
  mixIn,

  /// First vocal entry.
  vocalIn,

  /// First chorus or main hook.
  hook,

  /// The energy drop / main climax.
  drop,

  /// Energy breakdown / quiet section.
  breakdown,

  /// Re-entry after breakdown — energy builds back.
  reEntry,

  /// Safe point to begin mixing out.
  mixOut,

  /// End/outro of the track.
  outro,
}

extension CueTypeLabel on CueType {
  String get label => switch (this) {
        CueType.intro => 'Intro',
        CueType.mixIn => 'Mix In',
        CueType.vocalIn => 'Vocal In',
        CueType.hook => 'Hook',
        CueType.drop => 'Drop',
        CueType.breakdown => 'Breakdown',
        CueType.reEntry => 'Re-Entry',
        CueType.mixOut => 'Mix Out',
        CueType.outro => 'Outro',
      };

  /// Emoji colour indicator for UI display.
  String get emoji => switch (this) {
        CueType.intro => '🟢',
        CueType.mixIn => '🔵',
        CueType.vocalIn => '🟣',
        CueType.hook => '🟡',
        CueType.drop => '🔴',
        CueType.breakdown => '⚪',
        CueType.reEntry => '🟠',
        CueType.mixOut => '🔵',
        CueType.outro => '⚫',
      };

  /// VirtualDJ Poi colour hex (8 common hot-cue colours in VDJ order).
  String get vdjColor => switch (this) {
        CueType.intro => '#00FF00',
        CueType.mixIn => '#4488FF',
        CueType.vocalIn => '#AA44FF',
        CueType.hook => '#FFFF00',
        CueType.drop => '#FF0000',
        CueType.breakdown => '#FFFFFF',
        CueType.reEntry => '#FF8800',
        CueType.mixOut => '#4488FF',
        CueType.outro => '#888888',
      };
}

// ── Cue source (what generated the cue) ──────────────────────────────────────

enum CueSource {
  /// Deterministic BPM-grid + duration heuristics.
  metadataHeuristic,

  /// Genre-template structural pattern.
  genreTemplate,

  /// AI-assisted ranking of deterministic candidates.
  aiRanked,

  /// Hand-placed by the user.
  userEdited,
}

// ── HotCue ────────────────────────────────────────────────────────────────────

class HotCue {
  const HotCue({
    required this.id,
    required this.trackId,
    required this.cueIndex,
    required this.cueType,
    required this.label,
    required this.timeSeconds,
    required this.confidence,
    required this.source,
    this.notes = '',
    this.isSuggested = true,
    this.isWritten = false,
    this.targetSoftware,
  });

  /// Unique ID for this cue record (UUID or hash-based).
  final String id;

  /// LibraryTrack.id or Track.id this cue belongs to.
  final String trackId;

  /// 0-based sequential cue index within this track (0–7 for VirtualDJ).
  final int cueIndex;

  final CueType cueType;

  /// Human-readable label shown in DJ software (max ~20 chars for VDJ).
  final String label;

  /// Position in seconds from the start of the track.
  final double timeSeconds;

  /// Millisecond position (derived from timeSeconds for convenience).
  int get timeMs => (timeSeconds * 1000).round();

  /// Confidence score (0.0–1.0).
  final double confidence;

  final CueSource source;

  /// Optional generation notes / reasoning.
  final String notes;

  /// True while this is still a suggestion (not yet user-accepted).
  final bool isSuggested;

  /// True after successfully written to DJ software.
  final bool isWritten;

  /// Which DJ software this cue targets (null = VibeRadar only).
  final String? targetSoftware;

  String get formattedTime {
    final m = (timeSeconds / 60).floor();
    final s = (timeSeconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get confidenceLabel {
    if (confidence >= 0.75) return 'High';
    if (confidence >= 0.5) return 'Medium';
    return 'Low';
  }

  HotCue copyWith({
    String? label,
    double? timeSeconds,
    bool? isSuggested,
    bool? isWritten,
    String? targetSoftware,
    double? confidence,
    String? notes,
  }) =>
      HotCue(
        id: id,
        trackId: trackId,
        cueIndex: cueIndex,
        cueType: cueType,
        label: label ?? this.label,
        timeSeconds: timeSeconds ?? this.timeSeconds,
        confidence: confidence ?? this.confidence,
        source: source,
        notes: notes ?? this.notes,
        isSuggested: isSuggested ?? this.isSuggested,
        isWritten: isWritten ?? this.isWritten,
        targetSoftware: targetSoftware ?? this.targetSoftware,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'cueIndex': cueIndex,
        'cueType': cueType.name,
        'label': label,
        'timeSeconds': timeSeconds,
        'confidence': confidence,
        'source': source.name,
        'notes': notes,
        'isSuggested': isSuggested,
        'isWritten': isWritten,
        if (targetSoftware != null) 'targetSoftware': targetSoftware,
      };

  factory HotCue.fromJson(Map<String, dynamic> j) => HotCue(
        id: j['id'] as String,
        trackId: j['trackId'] as String,
        cueIndex: j['cueIndex'] as int,
        cueType: CueType.values.firstWhere(
          (e) => e.name == j['cueType'],
          orElse: () => CueType.intro,
        ),
        label: j['label'] as String,
        timeSeconds: (j['timeSeconds'] as num).toDouble(),
        confidence: (j['confidence'] as num).toDouble(),
        source: CueSource.values.firstWhere(
          (e) => e.name == j['source'],
          orElse: () => CueSource.metadataHeuristic,
        ),
        notes: j['notes'] as String? ?? '',
        isSuggested: j['isSuggested'] as bool? ?? true,
        isWritten: j['isWritten'] as bool? ?? false,
        targetSoftware: j['targetSoftware'] as String?,
      );
}
