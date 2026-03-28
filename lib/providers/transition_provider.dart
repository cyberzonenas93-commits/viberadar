import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../models/transition_score.dart';
import '../services/transition_engine_service.dart';

// ── Transition State ──────────────────────────────────────────────────────────

class TransitionState {
  const TransitionState({
    this.mode = TransitionMode.smooth,
    this.nextTrackCache = const {},
    this.isComputing = false,
    this.error,
  });

  final TransitionMode mode;

  /// fromTrackId → ranked next transition scores
  final Map<String, List<TransitionScore>> nextTrackCache;

  final bool isComputing;
  final String? error;

  TransitionState copyWith({
    TransitionMode? mode,
    Map<String, List<TransitionScore>>? nextTrackCache,
    bool? isComputing,
    Object? error = _sentinel,
  }) {
    return TransitionState(
      mode: mode ?? this.mode,
      nextTrackCache: nextTrackCache ?? this.nextTrackCache,
      isComputing: isComputing ?? this.isComputing,
      error:
          identical(error, _sentinel) ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

// ── Transition Notifier ───────────────────────────────────────────────────────

class TransitionNotifier extends Notifier<TransitionState> {
  final _engine = TransitionEngineService();

  @override
  TransitionState build() {
    return const TransitionState();
  }

  /// Change the active transition mode.
  void setMode(TransitionMode mode) {
    // Changing mode invalidates the cache since scores depend on mode
    state = state.copyWith(mode: mode, nextTrackCache: const {});
  }

  /// Get ranked next tracks for [current] from the given [pool].
  /// Results are cached per fromTrackId + mode.
  Future<List<TransitionScore>> getNextTracks(
    Track current,
    List<Track> pool, {
    int maxResults = 10,
  }) async {
    final cacheKey = '${current.id}:${state.mode.name}';

    if (state.nextTrackCache.containsKey(cacheKey)) {
      return state.nextTrackCache[cacheKey]!;
    }

    state = state.copyWith(isComputing: true, error: null);

    try {
      final candidates = pool.where((t) => t.id != current.id).toList();
      final scores = candidates
          .map((t) => _engine.scorePair(current, t, mode: state.mode))
          .toList()
        ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

      final top = scores.take(maxResults).toList();

      final updatedCache = Map<String, List<TransitionScore>>.from(
        state.nextTrackCache,
      )..[cacheKey] = top;

      state = state.copyWith(
        nextTrackCache: updatedCache,
        isComputing: false,
      );

      return top;
    } catch (e) {
      state = state.copyWith(
        isComputing: false,
        error: e.toString(),
      );
      return const [];
    }
  }

  /// Build an optimal sequence from the given tracks.
  Future<List<Track>> buildSequence(List<Track> tracks) async {
    state = state.copyWith(isComputing: true, error: null);
    try {
      final sequence = _engine.buildOptimalSequence(tracks, mode: state.mode);
      state = state.copyWith(isComputing: false);
      return sequence;
    } catch (e) {
      state = state.copyWith(isComputing: false, error: e.toString());
      return List.from(tracks);
    }
  }

  /// Find bridge tracks between [from] and [to] from the given [pool].
  Future<List<TransitionScore>> getBridgeTracks(
    Track from,
    Track to,
    List<Track> pool,
  ) async {
    state = state.copyWith(isComputing: true, error: null);
    try {
      final bridges = _engine.findBridgeTracks(from, to, pool, mode: state.mode);

      final scores = bridges
          .map((b) => _engine.scorePair(from, b, mode: state.mode))
          .toList()
        ..sort((a, b) => b.overallScore.compareTo(a.overallScore));

      state = state.copyWith(isComputing: false);
      return scores;
    } catch (e) {
      state = state.copyWith(isComputing: false, error: e.toString());
      return const [];
    }
  }

  /// Clear the next-track cache (e.g. when library changes).
  void clearCache() {
    state = state.copyWith(nextTrackCache: const {});
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final transitionProvider =
    NotifierProvider<TransitionNotifier, TransitionState>(
  TransitionNotifier.new,
);

final transitionModeProvider = Provider<TransitionMode>(
  (ref) => ref.watch(transitionProvider).mode,
);
