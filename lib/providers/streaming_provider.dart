import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:developer' as dev;
import '../services/apple_music_service.dart';
import '../services/spotify_preview_service.dart';

// ── Player state ──────────────────────────────────────────────────────────────

// ── Services ─────────────────────────────────────────────────────────────────

final appleMusicServiceProvider = Provider((_) => AppleMusicService());
final spotifyServiceProvider = Provider((_) => SpotifyPreviewService());

// ── Apple Music State ─────────────────────────────────────────────────────────

class AppleMusicState {
  const AppleMusicState({
    this.authStatus = AppleMusicAuthStatus.notDetermined,
    this.hasSubscription = false,
    this.isLoading = false,
    this.searchResults = const [],
    this.currentTrack,
    this.isPlaying = false,
    this.positionSeconds = 0.0,
    this.searchQuery = '',
    this.error,
  });
  final AppleMusicAuthStatus authStatus;
  final bool hasSubscription;
  final bool isLoading;
  final List<AppleMusicTrack> searchResults;
  final AppleMusicTrack? currentTrack;
  final bool isPlaying;
  final double positionSeconds;
  final String searchQuery;
  final String? error;

  bool get isAuthorized => authStatus == AppleMusicAuthStatus.authorized;
  bool get canPlay => isAuthorized && hasSubscription;

  /// Duration of the current track in seconds (0 if unknown).
  double get durationSeconds =>
      currentTrack?.durationMs != null ? currentTrack!.durationMs! / 1000.0 : 0.0;

  /// Playback progress 0.0–1.0.
  double get progress =>
      durationSeconds > 0 ? (positionSeconds / durationSeconds).clamp(0.0, 1.0) : 0.0;

  AppleMusicState copyWith({
    AppleMusicAuthStatus? authStatus,
    bool? hasSubscription,
    bool? isLoading,
    List<AppleMusicTrack>? searchResults,
    AppleMusicTrack? currentTrack,
    bool? isPlaying,
    double? positionSeconds,
    String? searchQuery,
    String? error,
    bool clearCurrentTrack = false,
    bool clearError = false,
  }) =>
      AppleMusicState(
        authStatus: authStatus ?? this.authStatus,
        hasSubscription: hasSubscription ?? this.hasSubscription,
        isLoading: isLoading ?? this.isLoading,
        searchResults: searchResults ?? this.searchResults,
        currentTrack: clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
        isPlaying: isPlaying ?? this.isPlaying,
        positionSeconds: positionSeconds ?? this.positionSeconds,
        searchQuery: searchQuery ?? this.searchQuery,
        error: clearError ? null : (error ?? this.error),
      );
}

class AppleMusicNotifier extends Notifier<AppleMusicState> {
  late final Completer<void> _initDone;
  Timer? _pollTimer;

  // Auto-play queue: list of (title, artist) to play after current track ends.
  // Not stored in state — kept as private field to avoid unnecessary rebuilds.
  List<(String, String)> _autoQueue = [];
  // True when the user explicitly called stop() — suppress auto-advance.
  bool _userStopped = false;

  @override
  AppleMusicState build() {
    _initDone = Completer<void>();
    _init();
    ref.onDispose(_stopPolling);
    return const AppleMusicState();
  }

  AppleMusicService get _svc => ref.read(appleMusicServiceProvider);

  // ── Playback position polling ──────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    final ps = await _svc.getPlaybackState();
    final status = ps['status'] as String? ?? 'stopped';
    final currentTime = (ps['currentTime'] as num?)?.toDouble() ?? 0.0;
    if (status == 'stopped') {
      _stopPolling();
      if (!_userStopped && _autoQueue.isNotEmpty) {
        // Natural end of track — advance to next in queue.
        final (nextTitle, nextArtist) = _autoQueue.removeAt(0);
        await Future.delayed(const Duration(milliseconds: 300));
        await playByQuery(nextTitle, nextArtist);
      } else if (!_userStopped && state.currentTrack != null) {
        // Queue is empty but track ended naturally — find a similar track
        // via Apple Music search and auto-advance.
        state = state.copyWith(isPlaying: false, positionSeconds: 0.0);
        await _autoAdvance();
      } else {
        state = state.copyWith(isPlaying: false, positionSeconds: 0.0);
      }
    } else {
      state = state.copyWith(
        isPlaying: status == 'playing',
        positionSeconds: currentTime,
      );
    }
  }

  /// Auto-advance: search for a similar track and play it.
  Future<void> _autoAdvance() async {
    final current = state.currentTrack;
    if (current == null) return;

    try {
      // Search for more tracks by the same artist or similar genre
      final queries = [
        current.artist,
        '${current.artist} ${current.genre}',
        current.genre.isNotEmpty ? current.genre : current.artist,
      ];

      for (final q in queries) {
        if (q.isEmpty) continue;
        final results = await _svc.search(q);
        // Filter out the track that just played
        final candidates = results.where((t) => t.id != current.id).toList();
        if (candidates.isNotEmpty) {
          // Pick a random track from top results for variety
          candidates.shuffle();
          final next = candidates.first;
          dev.log('Apple Music auto-advance: "${next.title}" by ${next.artist}', name: 'AppleMusic');
          await play(next);
          return;
        }
      }
      dev.log('Apple Music auto-advance: no candidates found', name: 'AppleMusic');
    } catch (e) {
      dev.log('Apple Music auto-advance error: $e', name: 'AppleMusic');
    }
  }

  void _init() async {
    try {
      final status = await _svc.getAuthorizationStatus();
      state = state.copyWith(authStatus: status);
      if (status == AppleMusicAuthStatus.authorized) {
        final sub = await _svc.checkSubscription();
        state = state.copyWith(hasSubscription: sub);
      }
    } finally {
      if (!_initDone.isCompleted) _initDone.complete();
    }
  }

  Future<void> requestAccess() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final status = await _svc.requestAuthorization();
    if (status == AppleMusicAuthStatus.authorized) {
      final sub = await _svc.checkSubscription();
      state = state.copyWith(authStatus: status, hasSubscription: sub, isLoading: false);
    } else {
      state = state.copyWith(
        authStatus: status,
        isLoading: false,
        error: status == AppleMusicAuthStatus.denied
            ? 'Access denied. Enable in System Settings → Privacy → Media & Apple Music.'
            : 'Apple Music access not available.',
      );
    }
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(searchResults: [], searchQuery: '');
      return;
    }
    state = state.copyWith(isLoading: true, searchQuery: query, clearError: true);
    try {
      final results = await _svc.search(query);
      state = state.copyWith(searchResults: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Search failed: $e');
    }
  }

  Future<void> play(AppleMusicTrack track) async {
    if (!state.canPlay) return;
    state = state.copyWith(currentTrack: track, isPlaying: false, isLoading: true, positionSeconds: 0.0);
    try {
      await _svc.play(track.id);
      state = state.copyWith(isPlaying: true, isLoading: false);
      _startPolling();
    } catch (e) {
      dev.log('Apple Music play error: $e', name: 'AppleMusic');
      state = state.copyWith(isPlaying: false, isLoading: false, error: e.toString());
    }
  }

  Future<void> pause() async {
    await _svc.pause();
    _stopPolling();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> resume() async {
    await _svc.resume();
    state = state.copyWith(isPlaying: true);
    _startPolling();
  }

  Future<void> stop() async {
    _userStopped = true;
    _autoQueue = [];
    _stopPolling();
    await _svc.stop();
    state = state.copyWith(isPlaying: false, positionSeconds: 0.0, clearCurrentTrack: true, clearError: true);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> seek(double positionSeconds) async {
    await _svc.seek(positionSeconds);
    state = state.copyWith(positionSeconds: positionSeconds);
  }

  Future<void> setVolume(double v) => _svc.setVolume(v);

  /// Search Apple Music for a track by title+artist and play the best match.
  /// Pass [queue] to set the auto-play queue for the session (tracks after this one).
  /// If [queue] is null, the existing queue is preserved (used for auto-advance calls).
  Future<bool> playByQuery(String title, String artist, {List<(String, String)>? queue}) async {
    // Wait for startup auth check to finish before deciding
    await _initDone.future;
    if (!state.isAuthorized) return false;
    _userStopped = false;
    if (queue != null) _autoQueue = List<(String, String)>.from(queue);
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await _svc.search('$title $artist');
      if (results.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'Not found on Apple Music');
        return false;
      }
      if (!state.hasSubscription) {
        state = state.copyWith(isLoading: false, error: 'Apple Music subscription required to play tracks.');
        return false;
      }
      await play(results.first);
      return true;
    } catch (e) {
      dev.log('playByQuery error: $e', name: 'AppleMusic');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}

final appleMusicProvider = NotifierProvider<AppleMusicNotifier, AppleMusicState>(
  AppleMusicNotifier.new,
);

// ── Spotify Preview State ─────────────────────────────────────────────────────

class SpotifyState {
  const SpotifyState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.searchResults = const [],
    this.currentPreviewTrack,
    this.isPlayingPreview = false,
    this.previewVolume = 1.0,
    this.searchQuery = '',
    this.error,
  });
  final bool isAuthenticated;
  final bool isLoading;
  final List<SpotifyTrack> searchResults;
  final SpotifyTrack? currentPreviewTrack;
  final bool isPlayingPreview;
  final double previewVolume;
  final String searchQuery;
  final String? error;

  SpotifyState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    List<SpotifyTrack>? searchResults,
    SpotifyTrack? currentPreviewTrack,
    bool? isPlayingPreview,
    double? previewVolume,
    String? searchQuery,
    String? error,
    bool clearError = false,
    bool clearPreviewTrack = false,
  }) =>
      SpotifyState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        searchResults: searchResults ?? this.searchResults,
        currentPreviewTrack:
            clearPreviewTrack ? null : (currentPreviewTrack ?? this.currentPreviewTrack),
        isPlayingPreview: isPlayingPreview ?? this.isPlayingPreview,
        previewVolume: previewVolume ?? this.previewVolume,
        searchQuery: searchQuery ?? this.searchQuery,
        error: clearError ? null : (error ?? this.error),
      );
}

class SpotifyNotifier extends Notifier<SpotifyState> {
  late final AudioPlayer _previewPlayer;

  @override
  SpotifyState build() {
    _previewPlayer = AudioPlayer();
    ref.onDispose(_previewPlayer.dispose);
    return const SpotifyState();
  }

  SpotifyPreviewService get _svc => ref.read(spotifyServiceProvider);

  Future<bool> configure(String clientId, String clientSecret) async {
    _svc.clientId = clientId;
    _svc.clientSecret = clientSecret;
    state = state.copyWith(isLoading: true, clearError: true);
    final ok = await _svc.authenticate();
    state = state.copyWith(
      isAuthenticated: ok,
      isLoading: false,
      error: ok ? null : 'Authentication failed. Check your Client ID and Secret.',
    );
    return ok;
  }

  Future<void> search(String query) async {
    if (!state.isAuthenticated) return;
    if (query.isEmpty) {
      state = state.copyWith(searchResults: [], searchQuery: '');
      return;
    }
    state = state.copyWith(isLoading: true, searchQuery: query, clearError: true);
    try {
      final results = await _svc.search(query);
      state = state.copyWith(searchResults: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Search failed');
    }
  }

  Future<void> playPreview(SpotifyTrack track) async {
    if (track.previewUrl == null) return;
    state = state.copyWith(currentPreviewTrack: track, isPlayingPreview: false);
    try {
      await _previewPlayer.stop();
      await _previewPlayer.setUrl(track.previewUrl!);
      await _previewPlayer.setVolume(state.previewVolume);
      await _previewPlayer.play();
      state = state.copyWith(isPlayingPreview: true);
    } catch (e) {
      dev.log('Spotify preview error: $e', name: 'Spotify');
    }
  }

  Future<void> stopPreview() async {
    await _previewPlayer.stop();
    state = state.copyWith(isPlayingPreview: false);
  }

  Future<void> togglePreview(SpotifyTrack track) async {
    if (state.currentPreviewTrack?.id == track.id && state.isPlayingPreview) {
      await stopPreview();
    } else {
      await playPreview(track);
    }
  }
}

final spotifyProvider = NotifierProvider<SpotifyNotifier, SpotifyState>(
  SpotifyNotifier.new,
);
