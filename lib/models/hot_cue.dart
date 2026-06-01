import 'package:uuid/uuid.dart';

// ── Cue type ───────────────────────────────────────────────────────────────────
enum CueType {
  intro,
  mixIn,
  vocalIn,
  hook,
  drop,
  breakdown,
  reEntry,
  mixOut,
  outro,
  marker,
}

extension CueTypeX on CueType {
  String get label {
    switch (this) {
      case CueType.intro:     return 'Intro';
      case CueType.mixIn:     return 'Mix In';
      case CueType.vocalIn:   return 'Vocal In';
      case CueType.hook:      return 'Hook';
      case CueType.drop:      return 'Drop';
      case CueType.breakdown: return 'Breakdown';
      case CueType.reEntry:   return 'Re-Entry';
      case CueType.mixOut:    return 'Mix Out';
      case CueType.outro:     return 'Outro';
      case CueType.marker:    return 'Marker';
    }
  }

  String get emoji {
    switch (this) {
      case CueType.intro:     return '🎬';
      case CueType.mixIn:     return '🔀';
      case CueType.vocalIn:   return '🎤';
      case CueType.hook:      return '🎣';
      case CueType.drop:      return '💥';
      case CueType.breakdown: return '🌊';
      case CueType.reEntry:   return '⚡';
      case CueType.mixOut:    return '🔄';
      case CueType.outro:     return '🏁';
      case CueType.marker:    return '📍';
    }
  }
}

// ── Cue source ─────────────────────────────────────────────────────────────────
enum CueSource {
  bpmHeuristic,
  durationHeuristic,
  genreTemplate,
  metadataHint,
  aiRanking,
  userDefined,
}

extension CueSourceX on CueSource {
  String get label {
    switch (this) {
      // These are ESTIMATES derived from BPM and typical song structure, not
      // detected from the audio waveform — the labels say so to avoid implying
      // real audio analysis.
      case CueSource.bpmHeuristic:      return 'BPM grid (est.)';
      case CueSource.durationHeuristic: return 'Structure estimate';
      case CueSource.genreTemplate:     return 'Genre template';
      case CueSource.metadataHint:      return 'Metadata';
      case CueSource.aiRanking:         return 'AI ranked';
      case CueSource.userDefined:       return 'User defined';
    }
  }
}

// ── HotCue ─────────────────────────────────────────────────────────────────────
class HotCue {
  HotCue({
    String? id,
    required this.trackId,
    required this.cueIndex,
    required this.cueType,
    required this.label,
    required this.timeSeconds,
    required this.confidence,
    required this.source,
    this.notes,
    this.isSuggested = true,
    this.isWritten = false,
    this.targetSoftware,
  })  : id = id ?? const Uuid().v4(),
        timeMs = (timeSeconds * 1000).round();

  final String id;
  final String trackId;
  final int cueIndex;
  final CueType cueType;
  final String label;
  final double timeSeconds;
  final int timeMs;
  final double confidence;
  final CueSource source;
  final String? notes;
  final bool isSuggested;
  final bool isWritten;
  final String? targetSoftware;

  String get timestampFormatted {
    final total = timeSeconds.floor();
    final m = total ~/ 60;
    final s = total % 60;
    final ms = ((timeSeconds - total) * 10).floor();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$ms';
  }

  HotCue copyWith({
    String? id,
    String? trackId,
    int? cueIndex,
    CueType? cueType,
    String? label,
    double? timeSeconds,
    double? confidence,
    CueSource? source,
    String? notes,
    bool? isSuggested,
    bool? isWritten,
    String? targetSoftware,
  }) {
    return HotCue(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      cueIndex: cueIndex ?? this.cueIndex,
      cueType: cueType ?? this.cueType,
      label: label ?? this.label,
      timeSeconds: timeSeconds ?? this.timeSeconds,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      notes: notes ?? this.notes,
      isSuggested: isSuggested ?? this.isSuggested,
      isWritten: isWritten ?? this.isWritten,
      targetSoftware: targetSoftware ?? this.targetSoftware,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'cueIndex': cueIndex,
        'cueType': cueType.name,
        'label': label,
        'timeSeconds': timeSeconds,
        'timeMs': timeMs,
        'confidence': confidence,
        'source': source.name,
        'notes': notes,
        'isSuggested': isSuggested,
        'isWritten': isWritten,
        'targetSoftware': targetSoftware,
      };

  factory HotCue.fromJson(Map<String, dynamic> json) {
    return HotCue(
      id: json['id'] as String?,
      trackId: json['trackId'] as String,
      cueIndex: json['cueIndex'] as int,
      cueType: CueType.values.firstWhere(
        (e) => e.name == json['cueType'],
        orElse: () => CueType.marker,
      ),
      label: json['label'] as String,
      timeSeconds: (json['timeSeconds'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      source: CueSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => CueSource.genreTemplate,
      ),
      notes: json['notes'] as String?,
      isSuggested: json['isSuggested'] as bool? ?? true,
      isWritten: json['isWritten'] as bool? ?? false,
      targetSoftware: json['targetSoftware'] as String?,
    );
  }
}

// ── CueGenerationResult ────────────────────────────────────────────────────────
class CueGenerationResult {
  const CueGenerationResult({
    required this.trackId,
    required this.trackTitle,
    required this.trackArtist,
    required this.cues,
    required this.generatedAt,
    this.hasWeakConfidence = false,
    this.warning,
    this.localFilePath,
  });

  final String trackId;
  final String trackTitle;
  final String trackArtist;
  final List<HotCue> cues;
  final bool hasWeakConfidence;
  final String? warning;
  final String? localFilePath;
  final DateTime generatedAt;

  List<HotCue> get strongCues => cues.where((c) => c.confidence >= 0.6).toList();
  List<HotCue> get weakCues   => cues.where((c) => c.confidence < 0.6).toList();

  CueGenerationResult copyWith({
    List<HotCue>? cues,
    bool? hasWeakConfidence,
    String? warning,
  }) {
    return CueGenerationResult(
      trackId: trackId,
      trackTitle: trackTitle,
      trackArtist: trackArtist,
      cues: cues ?? this.cues,
      generatedAt: generatedAt,
      hasWeakConfidence: hasWeakConfidence ?? this.hasWeakConfidence,
      warning: warning ?? this.warning,
      localFilePath: localFilePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'trackTitle': trackTitle,
        'trackArtist': trackArtist,
        'cues': cues.map((c) => c.toJson()).toList(),
        'hasWeakConfidence': hasWeakConfidence,
        'warning': warning,
        'localFilePath': localFilePath,
        'generatedAt': generatedAt.toIso8601String(),
      };

  factory CueGenerationResult.fromJson(Map<String, dynamic> json) {
    return CueGenerationResult(
      trackId: json['trackId'] as String,
      trackTitle: json['trackTitle'] as String,
      trackArtist: json['trackArtist'] as String,
      cues: (json['cues'] as List<dynamic>)
          .map((c) => HotCue.fromJson(c as Map<String, dynamic>))
          .toList(),
      hasWeakConfidence: json['hasWeakConfidence'] as bool? ?? false,
      warning: json['warning'] as String?,
      localFilePath: json['localFilePath'] as String?,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
    );
  }
}
