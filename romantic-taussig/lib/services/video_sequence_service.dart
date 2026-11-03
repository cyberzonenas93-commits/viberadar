import '../models/track.dart';
import '../models/video_playback_item.dart';
import '../models/video_transition_score.dart';
import 'video_transition_engine_service.dart';

/// Summary statistics and ordered list for a video sequence.
class VideoSequencePreview {
  const VideoSequencePreview({
    required this.orderedItems,
    required this.transitions,
    required this.averageScore,
    required this.mode,
    required this.riskyTransitions,
  });

  /// Ordered video items in recommended play order.
  final List<VideoPlaybackItem> orderedItems;

  /// Transition scores between consecutive items (length = orderedItems.length - 1).
  final List<VideoTransitionScore> transitions;

  /// Mean of all transition overall scores.
  final double averageScore;

  final VideoTransitionMode mode;

  /// Number of transitions with overallScore < 0.50.
  final int riskyTransitions;

  String get summary {
    final count = orderedItems.length;
    final pct = (averageScore * 100).round();
    final risky = riskyTransitions;
    return '$count videos · avg $pct%'
        '${risky > 0 ? ' · $risky risky' : ''}';
  }
}

/// Handles video playlist and crate ordering.
class VideoSequenceService {
  VideoSequenceService({VideoTransitionEngineService? engine})
      : _engine = engine ?? VideoTransitionEngineService();

  final VideoTransitionEngineService _engine;

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Reorder [tracks] to optimise video transitions, taking into account
  /// [videoItems] metadata.
  ///
  /// Returns a new list of [Track]s in the recommended order.
  /// Tracks that have no corresponding [VideoPlaybackItem] are appended at the
  /// end in their original order.
  List<Track> reorderForVideo(
    List<Track> tracks,
    List<VideoPlaybackItem> videoItems, {
    VideoTransitionMode mode = VideoTransitionMode.smooth,
  }) {
    if (tracks.isEmpty) return const [];

    final videoMap = {for (final v in videoItems) v.trackId: v};

    // Split: tracks that have a video item, and those that don't
    final withVideo = tracks.where((t) => videoMap.containsKey(t.id)).toList();
    final withoutVideo =
        tracks.where((t) => !videoMap.containsKey(t.id)).toList();

    if (withVideo.isEmpty) return List.from(tracks);

    final videoItemsForTracks =
        withVideo.map((t) => videoMap[t.id]!).toList();

    final orderedItems = _engine.buildVideoSequence(
      videoItemsForTracks,
      withVideo,
      mode: mode,
    );

    // Reconstruct tracks in the sequence order
    final trackById = {for (final t in withVideo) t.id: t};
    final reordered = orderedItems
        .map((item) => trackById[item.trackId])
        .whereType<Track>()
        .toList();

    return [...reordered, ...withoutVideo];
  }

  /// Extract [VideoPlaybackItem]s for the given [tracks] from [videoMap].
  /// Items are returned in the same order as [tracks] (skipping unmapped ones).
  List<VideoPlaybackItem> getVideoItemsForTracks(
    List<Track> tracks,
    Map<String, VideoPlaybackItem> videoMap,
  ) {
    return tracks
        .where((t) => videoMap.containsKey(t.id))
        .map((t) => videoMap[t.id]!)
        .toList();
  }

  /// Build a [VideoSequencePreview] for the given tracks and video items.
  VideoSequencePreview buildPreview(
    List<Track> tracks,
    List<VideoPlaybackItem> videoItems,
    VideoTransitionMode mode,
  ) {
    if (tracks.isEmpty || videoItems.isEmpty) {
      return VideoSequencePreview(
        orderedItems: const [],
        transitions: const [],
        averageScore: 0.0,
        mode: mode,
        riskyTransitions: 0,
      );
    }

    final trackMap = {for (final t in tracks) t.id: t};
    final videoMap = {for (final v in videoItems) v.trackId: v};

    // Reorder
    final reorderedTracks = reorderForVideo(tracks, videoItems, mode: mode);
    final orderedItems = getVideoItemsForTracks(reorderedTracks, videoMap);

    // Compute transitions between consecutive items
    final transitions = <VideoTransitionScore>[];
    for (var i = 0; i < orderedItems.length - 1; i++) {
      final from = orderedItems[i];
      final to = orderedItems[i + 1];
      final fromTrack = trackMap[from.trackId];
      final toTrack = trackMap[to.trackId];
      if (fromTrack == null || toTrack == null) continue;

      transitions.add(
        _engine.scoreVideoPair(from, to, fromTrack, toTrack, mode: mode),
      );
    }

    final averageScore = transitions.isEmpty
        ? 0.0
        : transitions.fold<double>(0.0, (sum, s) => sum + s.overallScore) /
            transitions.length;

    final riskyTransitions =
        transitions.where((s) => s.overallScore < 0.50).length;

    return VideoSequencePreview(
      orderedItems: orderedItems,
      transitions: transitions,
      averageScore: averageScore,
      mode: mode,
      riskyTransitions: riskyTransitions,
    );
  }
}
