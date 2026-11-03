import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../models/video_playback_item.dart';
import '../models/video_transition_score.dart';
import '../services/video_sequence_service.dart';
import '../services/video_transition_engine_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class VideoTransitionState {
  const VideoTransitionState({
    this.mode = VideoTransitionMode.smooth,
    this.videoItems = const {},
    this.currentPreview,
    this.isComputing = false,
    this.error,
  });

  /// Active transition mode.
  final VideoTransitionMode mode;

  /// trackId → VideoPlaybackItem registry.
  final Map<String, VideoPlaybackItem> videoItems;

  /// Most recently computed sequence preview.
  final VideoSequencePreview? currentPreview;

  final bool isComputing;
  final String? error;

  VideoTransitionState copyWith({
    VideoTransitionMode? mode,
    Map<String, VideoPlaybackItem>? videoItems,
    VideoSequencePreview? Function()? currentPreview,
    bool? isComputing,
    Object? error = _sentinel,
  }) {
    return VideoTransitionState(
      mode: mode ?? this.mode,
      videoItems: videoItems ?? this.videoItems,
      currentPreview:
          currentPreview != null ? currentPreview() : this.currentPreview,
      isComputing: isComputing ?? this.isComputing,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

// ── Notifier ──────────────────────────────────────────────────────────────────

class VideoTransitionNotifier extends Notifier<VideoTransitionState> {
  late final VideoTransitionEngineService _engine;
  late final VideoSequenceService _sequenceService;

  @override
  VideoTransitionState build() {
    _engine = VideoTransitionEngineService();
    _sequenceService = VideoSequenceService(engine: _engine);
    return const VideoTransitionState();
  }

  /// Change the active transition mode and clear the cached preview.
  void setMode(VideoTransitionMode mode) {
    state = state.copyWith(
      mode: mode,
      currentPreview: () => null,
    );
  }

  /// Register a [VideoPlaybackItem] for a given [trackId].
  void registerVideoItem(String trackId, VideoPlaybackItem item) {
    final updated = Map<String, VideoPlaybackItem>.from(state.videoItems)
      ..[trackId] = item;
    state = state.copyWith(videoItems: updated);
  }

  /// Remove a video item registration.
  void unregisterVideoItem(String trackId) {
    final updated = Map<String, VideoPlaybackItem>.from(state.videoItems)
      ..remove(trackId);
    state = state.copyWith(videoItems: updated);
  }

  /// Build a [VideoSequencePreview] for the given [tracks], using currently
  /// registered video items.
  ///
  /// Returns the preview (also stored in state) or null if no video items are
  /// available for the given tracks.
  VideoSequencePreview? buildPreviewForCrate(List<Track> tracks) {
    if (tracks.isEmpty) return null;

    final relevantItems = tracks
        .where((t) => state.videoItems.containsKey(t.id))
        .map((t) => state.videoItems[t.id]!)
        .toList();

    if (relevantItems.isEmpty) return null;

    state = state.copyWith(isComputing: true, error: null);

    try {
      final preview = _sequenceService.buildPreview(
        tracks,
        relevantItems,
        state.mode,
      );

      state = state.copyWith(
        isComputing: false,
        currentPreview: () => preview,
      );

      return preview;
    } catch (e) {
      state = state.copyWith(
        isComputing: false,
        error: e.toString(),
      );
      return null;
    }
  }

  /// Rank [pool] tracks as candidates for the next video after [current].
  Future<List<VideoPlaybackItem>> rankNextVideos(
    Track current,
    List<Track> pool,
  ) async {
    final currentItem = state.videoItems[current.id];
    if (currentItem == null) return const [];

    final candidateItems = pool
        .where((t) => t.id != current.id && state.videoItems.containsKey(t.id))
        .map((t) => state.videoItems[t.id]!)
        .toList();

    if (candidateItems.isEmpty) return const [];

    return _engine.rankNextVideos(
      currentItem,
      current,
      candidateItems,
      pool,
      mode: state.mode,
    );
  }

  /// Clear the current sequence preview.
  void clearPreview() {
    state = state.copyWith(currentPreview: () => null);
  }

  /// Clear all registered video items and preview.
  void clearAll() {
    state = const VideoTransitionState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final videoTransitionProvider =
    NotifierProvider<VideoTransitionNotifier, VideoTransitionState>(
  VideoTransitionNotifier.new,
);

final videoTransitionModeProvider = Provider<VideoTransitionMode>(
  (ref) => ref.watch(videoTransitionProvider).mode,
);
