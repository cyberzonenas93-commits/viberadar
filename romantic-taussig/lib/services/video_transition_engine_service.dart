import '../models/track.dart';
import '../models/transition_score.dart';
import '../models/video_playback_item.dart';
import '../models/video_transition_score.dart';
import 'transition_engine_service.dart';

/// Scores video transitions by combining audio-based scores (delegated to
/// [TransitionEngineService]) with visual-intensity signals derived from the
/// [VideoPlaybackItem] metadata.
class VideoTransitionEngineService {
  VideoTransitionEngineService({TransitionEngineService? audioEngine})
      : _audioEngine = audioEngine ?? TransitionEngineService();

  final TransitionEngineService _audioEngine;

  // ── Visual Intensity ────────────────────────────────────────────────────────

  /// Returns a 0.0–1.0 visual intensity score for a single item.
  ///
  /// - Live performance → high (0.85)
  /// - Official video   → medium (0.55)
  /// - Lyric video      → low (0.25)
  /// - Unknown          → medium-low (0.45)
  double _visualIntensity(VideoPlaybackItem item) {
    if (item.isLivePerformance) return 0.85;
    if (item.isOfficialVideo) return 0.55;
    if (item.isLyricVideo) return 0.25;
    return 0.45;
  }

  /// Score visual compatibility between two items (0.0–1.0).
  ///
  /// Same type → 0.90, similar category → 0.75, different → 0.50.
  double _scoreVisual(VideoPlaybackItem from, VideoPlaybackItem to) {
    // Identical type flags
    final sameType =
        (from.isLivePerformance == to.isLivePerformance) &&
        (from.isOfficialVideo == to.isOfficialVideo) &&
        (from.isLyricVideo == to.isLyricVideo);

    if (sameType) return 0.90;

    // "Similar": both are not lyric-only OR both are music-content (not live)
    final bothNotLyric = !from.isLyricVideo && !to.isLyricVideo;
    final bothNotLive = !from.isLivePerformance && !to.isLivePerformance;

    if (bothNotLyric || bothNotLive) return 0.75;

    return 0.50;
  }

  // ── Source Switch Penalty ───────────────────────────────────────────────────

  double _sourceSwitchPenalty(VideoPlaybackItem from, VideoPlaybackItem to) {
    return from.sourceType == to.sourceType ? 0.0 : 0.1;
  }

  // ── Mode Weights ────────────────────────────────────────────────────────────

  /// Returns (audioWeight, visualWeight) for the given mode.
  /// They sum to 1.0.
  (double, double) _modeWeights(VideoTransitionMode mode) {
    switch (mode) {
      case VideoTransitionMode.visualContinuity:
        return (0.65, 0.35);
      case VideoTransitionMode.smooth:
        return (0.85, 0.15);
      case VideoTransitionMode.clubFlow:
        return (0.82, 0.18);
      case VideoTransitionMode.peakTime:
        return (0.80, 0.20);
      case VideoTransitionMode.openFormat:
        return (0.78, 0.22);
      case VideoTransitionMode.warmUp:
        return (0.82, 0.18);
      case VideoTransitionMode.closing:
        return (0.80, 0.20);
      case VideoTransitionMode.singalong:
        return (0.82, 0.18);
    }
  }

  // ── Warnings ────────────────────────────────────────────────────────────────

  List<VideoTransitionWarning> _buildWarnings(
    VideoPlaybackItem from,
    VideoPlaybackItem to,
    Track fromTrack,
    Track toTrack,
    double audioScore,
    double visualScore,
    double penalty,
  ) {
    final warnings = <VideoTransitionWarning>[];

    final bpmDelta = (fromTrack.bpm - toTrack.bpm).abs();
    if (bpmDelta > 20) warnings.add(VideoTransitionWarning.bpmGapTooLarge);

    if (audioScore < 0.40) warnings.add(VideoTransitionWarning.harmonicClash);

    final intensityDelta =
        (_visualIntensity(from) - _visualIntensity(to)).abs();
    if (intensityDelta > 0.40) {
      warnings.add(VideoTransitionWarning.abruptVisualIntensityJump);
    }

    if (visualScore < 0.60) {
      warnings.add(VideoTransitionWarning.weakVisualContinuity);
    }

    if (penalty > 0.0) {
      warnings.add(VideoTransitionWarning.sourceSwitchFriction);
    }

    final overallEstimate = (audioScore + visualScore) / 2.0 - penalty;
    if (overallEstimate < 0.45) {
      warnings.add(VideoTransitionWarning.likelyJarringTransition);
    }

    return warnings;
  }

  // ── Reasons ─────────────────────────────────────────────────────────────────

  List<String> _buildReasons(
    VideoPlaybackItem from,
    VideoPlaybackItem to,
    double audioScore,
    double visualScore,
    double overall,
  ) {
    final reasons = <String>[];

    if (audioScore >= 0.75) {
      reasons.add('Strong audio compatibility');
    } else if (audioScore >= 0.55) {
      reasons.add('Acceptable audio compatibility');
    }

    if (visualScore >= 0.88) {
      reasons.add('Identical visual style — seamless visual continuity');
    } else if (visualScore >= 0.73) {
      reasons.add('Similar visual style — smooth visual flow');
    }

    if (from.isOfficialVideo && to.isOfficialVideo) {
      reasons.add('Both official videos — polished visual match');
    } else if (from.isLivePerformance && to.isLivePerformance) {
      reasons.add('Both live performances — consistent energy atmosphere');
    } else if (from.isLyricVideo && to.isOfficialVideo) {
      reasons.add('Lyric → official — natural visual upgrade');
    }

    if (reasons.isEmpty) {
      reasons.add('Transition within acceptable range');
    }

    return reasons;
  }

  // ── Type Determination ───────────────────────────────────────────────────────

  VideoTransitionType _determineType(
    VideoPlaybackItem from,
    VideoPlaybackItem to,
    double overall,
    double audioScore,
    double visualScore,
    VideoTransitionMode mode,
  ) {
    if (overall < 0.45) return VideoTransitionType.riskyTransition;

    if (mode == VideoTransitionMode.closing && overall >= 0.6) {
      return VideoTransitionType.closingFlow;
    }

    if (mode == VideoTransitionMode.singalong && overall >= 0.65) {
      return VideoTransitionType.singalongBridge;
    }

    if (mode == VideoTransitionMode.peakTime && overall >= 0.60 && overall < 0.80) {
      return VideoTransitionType.peakTimeSlam;
    }

    if (overall >= 0.80 && audioScore >= 0.75 && visualScore >= 0.80) {
      return VideoTransitionType.smoothVisualBlend;
    }

    if (overall >= 0.75 && audioScore >= 0.80) {
      return VideoTransitionType.smoothMusicBlend;
    }

    if (from.isLyricVideo && to.isLivePerformance) {
      return VideoTransitionType.lyricToPerformanceBridge;
    }

    if (from.isOfficialVideo && to.isLivePerformance) {
      return VideoTransitionType.officialToLivePivot;
    }

    if (overall >= 0.70) {
      // Determine energy direction from visual intensity
      final fromIntensity = _visualIntensity(from);
      final toIntensity = _visualIntensity(to);
      final delta = toIntensity - fromIntensity;
      if (delta > 0.15) return VideoTransitionType.energyLift;
      if (delta < -0.15) return VideoTransitionType.energyDrop;
      return VideoTransitionType.smoothVisualBlend;
    }

    if (overall >= 0.55) return VideoTransitionType.bridgeTransition;
    if (overall >= 0.45) return VideoTransitionType.hardCutCandidate;

    return VideoTransitionType.visualReset;
  }

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Score a pair of video items for transition compatibility.
  ///
  /// Combines audio score (from [TransitionEngineService]) with visual
  /// intensity analysis, then applies a source-switch penalty if the items
  /// come from different source types.
  VideoTransitionScore scoreVideoPair(
    VideoPlaybackItem from,
    VideoPlaybackItem to,
    Track fromTrack,
    Track toTrack, {
    VideoTransitionMode mode = VideoTransitionMode.smooth,
  }) {
    // Audio score from the existing engine (map VideoTransitionMode → TransitionMode)
    final audioTransitionScore = _audioEngine.scorePair(
      fromTrack,
      toTrack,
      mode: _mapMode(mode),
    );
    final audioScore = audioTransitionScore.overallScore;

    final visualScore = _scoreVisual(from, to);
    final penalty = _sourceSwitchPenalty(from, to);

    final (audioWeight, visualWeight) = _modeWeights(mode);

    final rawCombined = (audioScore * audioWeight) + (visualScore * visualWeight);
    final overall = (rawCombined - penalty).clamp(0.0, 1.0);

    final warnings = _buildWarnings(
      from, to, fromTrack, toTrack, audioScore, visualScore, penalty,
    );
    final reasons = _buildReasons(from, to, audioScore, visualScore, overall);
    final type = _determineType(from, to, overall, audioScore, visualScore, mode);

    return VideoTransitionScore(
      fromTrackId: fromTrack.id,
      toTrackId: toTrack.id,
      overallScore: overall,
      confidence: audioTransitionScore.confidence,
      type: type,
      reasons: reasons,
      warnings: warnings,
      sourceSwitchPenalty: penalty,
      audioScore: audioScore,
      visualScore: visualScore,
    );
  }

  /// Map [VideoTransitionMode] to an audio [TransitionMode].
  TransitionMode _mapMode(VideoTransitionMode mode) {
    switch (mode) {
      case VideoTransitionMode.smooth:
      case VideoTransitionMode.visualContinuity:
        return TransitionMode.smooth;
      case VideoTransitionMode.clubFlow:
        return TransitionMode.clubFlow;
      case VideoTransitionMode.peakTime:
        return TransitionMode.peakTime;
      case VideoTransitionMode.openFormat:
        return TransitionMode.openFormat;
      case VideoTransitionMode.warmUp:
        return TransitionMode.warmUp;
      case VideoTransitionMode.closing:
        return TransitionMode.closing;
      case VideoTransitionMode.singalong:
        return TransitionMode.singalong;
    }
  }

  /// Build an optimal video sequence using a greedy nearest-neighbour
  /// approach (mirrors [TransitionEngineService.buildOptimalSequence]).
  List<VideoPlaybackItem> buildVideoSequence(
    List<VideoPlaybackItem> items,
    List<Track> tracks, {
    VideoTransitionMode mode = VideoTransitionMode.smooth,
  }) {
    if (items.isEmpty) return const [];
    if (items.length == 1) return List.from(items);

    final trackMap = {for (final t in tracks) t.id: t};

    // Remove items without a matching track
    final validItems = items
        .where((i) => trackMap.containsKey(i.trackId))
        .toList();

    if (validItems.isEmpty) return const [];
    if (validItems.length == 1) return List.from(validItems);

    final remaining = List<VideoPlaybackItem>.from(validItems);
    final sequence = <VideoPlaybackItem>[];

    // Seed: item with best average score to others
    VideoPlaybackItem? seed;
    double bestAvg = -1.0;
    for (final item in remaining) {
      final fromTrack = trackMap[item.trackId]!;
      double sum = 0.0;
      int count = 0;
      for (final other in remaining) {
        if (other.trackId == item.trackId) continue;
        final toTrack = trackMap[other.trackId];
        if (toTrack == null) continue;
        sum += scoreVideoPair(item, other, fromTrack, toTrack, mode: mode)
            .overallScore;
        count++;
      }
      final avg = count > 0 ? sum / count : 0.0;
      if (avg > bestAvg) {
        bestAvg = avg;
        seed = item;
      }
    }

    sequence.add(seed!);
    remaining.removeWhere((i) => i.trackId == seed!.trackId);

    while (remaining.isNotEmpty) {
      final current = sequence.last;
      final currentTrack = trackMap[current.trackId]!;
      VideoPlaybackItem? bestNext;
      double bestScore = -1.0;

      for (final candidate in remaining) {
        final toTrack = trackMap[candidate.trackId];
        if (toTrack == null) continue;
        final s = scoreVideoPair(current, candidate, currentTrack, toTrack,
                mode: mode)
            .overallScore;
        if (s > bestScore) {
          bestScore = s;
          bestNext = candidate;
        }
      }

      if (bestNext == null) break;
      sequence.add(bestNext);
      remaining.removeWhere((i) => i.trackId == bestNext!.trackId);
    }

    // Append any remaining items that couldn't be matched
    sequence.addAll(remaining);

    return sequence;
  }

  /// Rank [candidates] for the next slot after [current].
  List<VideoPlaybackItem> rankNextVideos(
    VideoPlaybackItem current,
    Track currentTrack,
    List<VideoPlaybackItem> candidates,
    List<Track> allTracks, {
    VideoTransitionMode mode = VideoTransitionMode.smooth,
    int maxResults = 10,
  }) {
    final trackMap = {for (final t in allTracks) t.id: t};

    final scored = candidates
        .where((c) => c.trackId != current.trackId)
        .map((c) {
          final toTrack = trackMap[c.trackId];
          if (toTrack == null) return null;
          final s = scoreVideoPair(current, c, currentTrack, toTrack,
              mode: mode);
          return (item: c, score: s.overallScore);
        })
        .whereType<({VideoPlaybackItem item, double score})>()
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(maxResults).map((e) => e.item).toList();
  }

  /// Find a bridge video [B] such that A→B and B→C both score well.
  /// Returns the best bridge candidate, or null if none qualifies.
  VideoPlaybackItem? findBridgeVideo(
    VideoPlaybackItem from,
    VideoPlaybackItem to,
    Track fromTrack,
    Track toTrack,
    List<VideoPlaybackItem> pool,
    List<Track> allTracks, {
    VideoTransitionMode mode = VideoTransitionMode.smooth,
    double minHopScore = 0.50,
  }) {
    final trackMap = {for (final t in allTracks) t.id: t};
    VideoPlaybackItem? bestBridge;
    double bestBridgeScore = -1.0;

    for (final candidate in pool) {
      if (candidate.trackId == from.trackId ||
          candidate.trackId == to.trackId) {
        continue;
      }
      final bridgeTrack = trackMap[candidate.trackId];
      if (bridgeTrack == null) continue;

      final aToB = scoreVideoPair(from, candidate, fromTrack, bridgeTrack,
          mode: mode);
      final bToC = scoreVideoPair(candidate, to, bridgeTrack, toTrack,
          mode: mode);

      if (aToB.overallScore >= minHopScore &&
          bToC.overallScore >= minHopScore) {
        final bridgeScore =
            (aToB.overallScore + bToC.overallScore) / 2.0;
        if (bridgeScore > bestBridgeScore) {
          bestBridgeScore = bridgeScore;
          bestBridge = candidate;
        }
      }
    }

    return bestBridge;
  }
}
