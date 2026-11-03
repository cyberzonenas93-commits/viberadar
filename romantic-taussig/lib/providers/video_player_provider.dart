import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../models/video_playback_item.dart';
import '../services/youtube_video_match_service.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class VideoPlayerState {
  const VideoPlayerState({
    this.isVisible = false,
    this.item,
    this.isLoading = false,
    this.error,
    this.track,
  });

  /// Whether the video player overlay is showing.
  final bool isVisible;

  /// The current video being played (YouTube or local).
  final VideoPlaybackItem? item;

  /// True while resolving a YouTube match.
  final bool isLoading;

  /// Error message if resolution or playback failed.
  final String? error;

  /// The VibeRadar track this video is associated with (for display).
  final Track? track;

  VideoPlayerState copyWith({
    bool? isVisible,
    Object? item = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
    Object? track = _sentinel,
  }) =>
      VideoPlayerState(
        isVisible: isVisible ?? this.isVisible,
        item: identical(item, _sentinel)
            ? this.item
            : item as VideoPlaybackItem?,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _sentinel) ? this.error : error as String?,
        track: identical(track, _sentinel) ? this.track : track as Track?,
      );
}

const _sentinel = Object();

// ── Notifier ──────────────────────────────────────────────────────────────────

class VideoPlayerNotifier extends Notifier<VideoPlayerState> {
  @override
  VideoPlayerState build() => const VideoPlayerState();

  final _matchService = YoutubeVideoMatchService();

  /// Resolve and play a YouTube video for [track].
  ///
  /// Shows the overlay in loading state, resolves via YouTube Data API,
  /// then switches to the embed player. Falls back to error state if
  /// no match is found.
  Future<void> playYouTube(Track track) async {
    state = VideoPlayerState(
      isVisible: true,
      isLoading: true,
      track: track,
    );

    try {
      final match = await _matchService.resolve(track);
      if (match == null) {
        // Surface quota info if that's the reason
        final searchError = _matchService.lastSearchError;
        final errorMsg = searchError != null && searchError.contains('quota')
            ? searchError
            : 'No YouTube video found for "${track.artist} – ${track.title}"';
        state = state.copyWith(
          isLoading: false,
          error: errorMsg,
        );
        return;
      }

      final item = VideoPlaybackItem.youtube(
        trackId: track.id,
        videoId: match.videoId,
        rawTitle: match.title,
        channelName: match.channelName,
        thumbnailUrl: match.thumbnailUrl,
        artistName: track.artist,
      );

      state = state.copyWith(
        isLoading: false,
        item: item,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to resolve video: $e',
      );
    }
  }

  /// Play a local video file directly.
  void playLocalVideo({
    required String trackId,
    required String filePath,
    String? title,
    Track? track,
  }) {
    final item = VideoPlaybackItem.local(
      trackId: trackId,
      filePath: filePath,
      title: title,
    );
    state = VideoPlayerState(
      isVisible: true,
      item: item,
      track: track,
    );
  }

  /// Close the video player overlay.
  void close() {
    state = const VideoPlayerState();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final videoPlayerProvider =
    NotifierProvider<VideoPlayerNotifier, VideoPlayerState>(
  VideoPlayerNotifier.new,
);
