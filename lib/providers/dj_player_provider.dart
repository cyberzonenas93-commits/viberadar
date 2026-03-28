import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/library_track.dart';
import '../providers/library_provider.dart';

// ── Camelot wheel compatibility ────────────────────────────────────────────────
// Returns true if two Camelot keys are harmonically compatible (same, +/-1, relative)
bool camelotCompatible(String a, String b) {
  if (a.isEmpty || b.isEmpty) return true;
  if (a == b) return true;
  final numA = int.tryParse(a.replaceAll(RegExp(r'[AB]'), ''));
  final numB = int.tryParse(b.replaceAll(RegExp(r'[AB]'), ''));
  if (numA == null || numB == null) return false;
  final modeA = a.endsWith('A') ? 'A' : 'B';
  final modeB = b.endsWith('A') ? 'A' : 'B';
  final diff = ((numA - numB) % 12).abs();
  // Same mode, adjacent number
  if (modeA == modeB && (diff == 0 || diff == 1 || diff == 11)) return true;
  // Relative major/minor (same number, different mode)
  if (numA == numB && modeA != modeB) return true;
  return false;
}

// ── Deck state ─────────────────────────────────────────────────────────────────

class DeckState {
  const DeckState({
    this.track,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.pitch = 0.0,   // -8.0 to +8.0 percent
    this.volume = 1.0,
    this.isCued = false,
    this.cuePoint = Duration.zero,
    this.isLooping = false,
    this.loopStart = Duration.zero,
    this.loopEnd = Duration.zero,
    this.eqHigh = 0.0,
    this.eqMid = 0.0,
    this.eqLow = 0.0,
  });

  final LibraryTrack? track;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;
  final double pitch;       // percent offset, -8 to +8
  final double volume;
  final bool isCued;
  final Duration cuePoint;
  final bool isLooping;
  final Duration loopStart;
  final Duration loopEnd;
  final double eqHigh;
  final double eqMid;
  final double eqLow;

  bool get hasTrack => track != null;
  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;
  double get speedFactor => 1.0 + (pitch / 100.0);
  double get effectiveBpm => track != null && track!.bpm > 0
      ? track!.bpm * speedFactor
      : 0.0;
  // Remaining time
  Duration get remaining => duration - position;
  // Near end = last 30 seconds
  bool get isNearEnd => remaining.inSeconds < 30 && duration.inSeconds > 0;

  DeckState copyWith({
    LibraryTrack? track,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    double? pitch,
    double? volume,
    bool? isCued,
    Duration? cuePoint,
    bool? isLooping,
    Duration? loopStart,
    Duration? loopEnd,
    double? eqHigh,
    double? eqMid,
    double? eqLow,
  }) => DeckState(
    track: track ?? this.track,
    isPlaying: isPlaying ?? this.isPlaying,
    isLoading: isLoading ?? this.isLoading,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    pitch: pitch ?? this.pitch,
    volume: volume ?? this.volume,
    isCued: isCued ?? this.isCued,
    cuePoint: cuePoint ?? this.cuePoint,
    isLooping: isLooping ?? this.isLooping,
    loopStart: loopStart ?? this.loopStart,
    loopEnd: loopEnd ?? this.loopEnd,
    eqHigh: eqHigh ?? this.eqHigh,
    eqMid: eqMid ?? this.eqMid,
    eqLow: eqLow ?? this.eqLow,
  );
}

// ── DJ Player State ────────────────────────────────────────────────────────────

class DjPlayerState {
  const DjPlayerState({
    this.deckA = const DeckState(),
    this.deckB = const DeckState(),
    this.crossfader = 0.5,    // 0=full A, 1=full B
    this.masterVolume = 1.0,
    this.autoMix = false,
    this.autoMixThreshold = 20, // seconds before end to start automix
    this.bpmSynced = false,
    this.isVisible = false,
    this.activeDeck = 0,       // 0=A, 1=B
    this.autoQueue = false,    // Spotify-style auto-advance
    this.preloadedDeck = -1,   // which deck has the preloaded next track (-1 = none)
  });

  final DeckState deckA;
  final DeckState deckB;
  final double crossfader;
  final double masterVolume;
  final bool autoMix;
  final int autoMixThreshold;
  final bool bpmSynced;
  final bool isVisible;
  final int activeDeck;       // which deck was last loaded
  final bool autoQueue;
  final int preloadedDeck;

  bool get hasAnyTrack => deckA.hasTrack || deckB.hasTrack;

  // Effective volumes accounting for crossfader
  // Crossfader: 0.0 = deck A full, 0.5 = equal, 1.0 = deck B full
  // Use equal-power crossfade curve
  double get deckAVolume {
    return deckA.volume * masterVolume * (crossfader <= 0.5 ? 1.0 : (1.0 - crossfader) * 2.0);
  }
  double get deckBVolume {
    return deckB.volume * masterVolume * (crossfader >= 0.5 ? 1.0 : crossfader * 2.0);
  }

  DjPlayerState copyWith({
    DeckState? deckA,
    DeckState? deckB,
    double? crossfader,
    double? masterVolume,
    bool? autoMix,
    int? autoMixThreshold,
    bool? bpmSynced,
    bool? isVisible,
    int? activeDeck,
    bool? autoQueue,
    int? preloadedDeck,
  }) => DjPlayerState(
    deckA: deckA ?? this.deckA,
    deckB: deckB ?? this.deckB,
    crossfader: crossfader ?? this.crossfader,
    masterVolume: masterVolume ?? this.masterVolume,
    autoMix: autoMix ?? this.autoMix,
    autoMixThreshold: autoMixThreshold ?? this.autoMixThreshold,
    bpmSynced: bpmSynced ?? this.bpmSynced,
    isVisible: isVisible ?? this.isVisible,
    activeDeck: activeDeck ?? this.activeDeck,
    autoQueue: autoQueue ?? this.autoQueue,
    preloadedDeck: preloadedDeck ?? this.preloadedDeck,
  );
}

// ── DJ Player Notifier ─────────────────────────────────────────────────────────

class DjPlayerNotifier extends Notifier<DjPlayerState> {
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;

  // Stream subscriptions
  final List<StreamSubscription<dynamic>> _subs = [];

  // Auto-mix crossfade timer
  Timer? _autoMixTimer;
  bool _autoMixing = false;

  // Tracks which deck is the "main" playing deck (0=A, 1=B)
  int _playingDeck = 0;

  @override
  DjPlayerState build() {
    _playerA = AudioPlayer();
    _playerB = AudioPlayer();
    _setupListeners();
    ref.onDispose(_dispose);
    return const DjPlayerState();
  }

  void _dispose() {
    _autoMixTimer?.cancel();
    for (final s in _subs) { s.cancel(); }
    _playerA.dispose();
    _playerB.dispose();
  }

  void _setupListeners() {
    // Deck A listeners
    _subs.add(_playerA.positionStream.listen((pos) {
      state = state.copyWith(deckA: state.deckA.copyWith(position: pos));
      _checkAutoMix();
    }));
    _subs.add(_playerA.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(deckA: state.deckA.copyWith(duration: dur));
    }));
    _subs.add(_playerA.playerStateStream.listen((ps) {
      state = state.copyWith(deckA: state.deckA.copyWith(
        isPlaying: ps.playing,
        isLoading: ps.processingState == ProcessingState.loading || ps.processingState == ProcessingState.buffering,
      ));
      if (ps.processingState == ProcessingState.completed) {
        state = state.copyWith(deckA: state.deckA.copyWith(isPlaying: false));
        _onDeckCompleted(0);
      }
    }));

    // Deck B listeners
    _subs.add(_playerB.positionStream.listen((pos) {
      state = state.copyWith(deckB: state.deckB.copyWith(position: pos));
    }));
    _subs.add(_playerB.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(deckB: state.deckB.copyWith(duration: dur));
    }));
    _subs.add(_playerB.playerStateStream.listen((ps) {
      state = state.copyWith(deckB: state.deckB.copyWith(
        isPlaying: ps.playing,
        isLoading: ps.processingState == ProcessingState.loading || ps.processingState == ProcessingState.buffering,
      ));
      if (ps.processingState == ProcessingState.completed) {
        state = state.copyWith(deckB: state.deckB.copyWith(isPlaying: false));
        _onDeckCompleted(1);
      }
    }));
  }

  // ── Load & Play ──────────────────────────────────────────────────────────

  /// Load a track onto a deck (0=A, 1=B) and start playing.
  Future<void> loadTrack(LibraryTrack track, {int deck = 0}) async {
    final player = deck == 0 ? _playerA : _playerB;
    final current = deck == 0 ? state.deckA : state.deckB;

    final newDeck = current.copyWith(
      track: track,
      isLoading: true,
      position: Duration.zero,
      duration: Duration.zero,
      isCued: false,
      cuePoint: Duration.zero,
    );
    state = deck == 0
        ? state.copyWith(deckA: newDeck, isVisible: true, activeDeck: deck)
        : state.copyWith(deckB: newDeck, isVisible: true, activeDeck: deck);

    try {
      await player.stop();
      await player.setFilePath(track.filePath);
      await player.setSpeed(newDeck.speedFactor);
      // Apply crossfader volume
      final vol = deck == 0 ? state.deckAVolume : state.deckBVolume;
      await player.setVolume(vol);
      await player.play();
      _playingDeck = deck;
      // Schedule preload of next track if autoQueue is active
      if (state.autoQueue) {
        // ignore: discarded_futures
        _schedulePreload();
      }
    } catch (e) {
      dev.log('DjPlayer deck $deck load error: $e', name: 'DjPlayer');
    }
  }

  /// Smart load: if deck A is empty or idle, load to A. Otherwise load to B.
  Future<void> smartLoad(LibraryTrack track) async {
    final targetDeck = (!state.deckA.hasTrack || !state.deckA.isPlaying) ? 0 : 1;
    await loadTrack(track, deck: targetDeck);
  }

  // ── Playback controls ────────────────────────────────────────────────────

  Future<void> togglePlayPause(int deck) async {
    final player = deck == 0 ? _playerA : _playerB;
    final deckState = deck == 0 ? state.deckA : state.deckB;
    if (deckState.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(int deck, double fraction) async {
    final player = deck == 0 ? _playerA : _playerB;
    final dur = deck == 0 ? state.deckA.duration : state.deckB.duration;
    if (dur == Duration.zero) return;
    final ms = (fraction * dur.inMilliseconds).toInt().clamp(0, dur.inMilliseconds);
    await player.seek(Duration(milliseconds: ms));
  }

  Future<void> setCue(int deck) async {
    final deckState = deck == 0 ? state.deckA : state.deckB;
    final pos = deckState.position;
    if (deck == 0) {
      state = state.copyWith(deckA: state.deckA.copyWith(cuePoint: pos, isCued: true));
    } else {
      state = state.copyWith(deckB: state.deckB.copyWith(cuePoint: pos, isCued: true));
    }
  }

  Future<void> jumpToCue(int deck) async {
    final player = deck == 0 ? _playerA : _playerB;
    final cue = deck == 0 ? state.deckA.cuePoint : state.deckB.cuePoint;
    await player.seek(cue);
  }

  // ── Pitch / BPM ──────────────────────────────────────────────────────────

  Future<void> setPitch(int deck, double percent) async {
    final player = deck == 0 ? _playerA : _playerB;
    final clamped = percent.clamp(-8.0, 8.0);
    final speed = 1.0 + (clamped / 100.0);
    if (deck == 0) {
      state = state.copyWith(deckA: state.deckA.copyWith(pitch: clamped));
    } else {
      state = state.copyWith(deckB: state.deckB.copyWith(pitch: clamped));
    }
    await player.setSpeed(speed);
  }

  /// Sync deck B's pitch so its BPM matches deck A's effective BPM.
  Future<void> syncBpm({int sourceDeck = 0}) async {
    final src = sourceDeck == 0 ? state.deckA : state.deckB;
    final dst = sourceDeck == 0 ? state.deckB : state.deckA;
    final dstDeck = sourceDeck == 0 ? 1 : 0;
    if (src.track == null || dst.track == null) return;
    if (src.track!.bpm <= 0 || dst.track!.bpm <= 0) return;
    final targetBpm = src.effectiveBpm;
    final currentBpm = dst.track!.bpm;
    final neededPitch = ((targetBpm / currentBpm) - 1.0) * 100.0;
    await setPitch(dstDeck, neededPitch);
    state = state.copyWith(bpmSynced: true);
  }

  // ── Crossfader ───────────────────────────────────────────────────────────

  Future<void> setCrossfader(double value) async {
    state = state.copyWith(crossfader: value.clamp(0.0, 1.0));
    await _updateDeckVolumes();
  }

  Future<void> setDeckVolume(int deck, double vol) async {
    if (deck == 0) {
      state = state.copyWith(deckA: state.deckA.copyWith(volume: vol.clamp(0.0, 1.0)));
    } else {
      state = state.copyWith(deckB: state.deckB.copyWith(volume: vol.clamp(0.0, 1.0)));
    }
    await _updateDeckVolumes();
  }

  Future<void> setMasterVolume(double vol) async {
    state = state.copyWith(masterVolume: vol.clamp(0.0, 1.0));
    await _updateDeckVolumes();
  }

  Future<void> _updateDeckVolumes() async {
    await _playerA.setVolume(state.deckAVolume.clamp(0.0, 1.0));
    await _playerB.setVolume(state.deckBVolume.clamp(0.0, 1.0));
  }

  // ── Loop ─────────────────────────────────────────────────────────────────

  void toggleLoop(int deck) {
    final deckState = deck == 0 ? state.deckA : state.deckB;
    final nowLooping = !deckState.isLooping;
    final loopStart = deckState.position;
    if (deck == 0) {
      state = state.copyWith(deckA: state.deckA.copyWith(
        isLooping: nowLooping,
        loopStart: loopStart,
        loopEnd: loopStart + const Duration(seconds: 4),
      ));
    } else {
      state = state.copyWith(deckB: state.deckB.copyWith(
        isLooping: nowLooping,
        loopStart: loopStart,
        loopEnd: loopStart + const Duration(seconds: 4),
      ));
    }
  }

  // ── EQ ───────────────────────────────────────────────────────────────────

  void setEq(int deck, {double? high, double? mid, double? low}) {
    if (deck == 0) {
      state = state.copyWith(deckA: state.deckA.copyWith(
        eqHigh: high ?? state.deckA.eqHigh,
        eqMid: mid ?? state.deckA.eqMid,
        eqLow: low ?? state.deckA.eqLow,
      ));
    } else {
      state = state.copyWith(deckB: state.deckB.copyWith(
        eqHigh: high ?? state.deckB.eqHigh,
        eqMid: mid ?? state.deckB.eqMid,
        eqLow: low ?? state.deckB.eqLow,
      ));
    }
    // Note: just_audio doesn't support EQ on macOS natively.
    // EQ state is stored for UI display; actual audio EQ would require
    // a native audio unit plugin (out of scope for pure Flutter).
  }

  // ── Auto-mix / Auto-queue ─────────────────────────────────────────────────

  void toggleAutoMix() {
    final newVal = !state.autoMix;
    if (!newVal) _autoMixing = false;
    state = state.copyWith(autoMix: newVal);
  }

  void toggleAutoQueue() {
    final newVal = !state.autoQueue;
    state = state.copyWith(autoQueue: newVal);
    if (newVal && (state.deckA.isPlaying || state.deckB.isPlaying)) {
      // Already playing — schedule preload immediately
      // ignore: discarded_futures
      _schedulePreload();
    }
  }

  void _checkAutoMix() {
    if (!state.autoMix && !state.autoQueue) return;
    if (_autoMixing) return;

    final playingDeckState = _playingDeck == 0 ? state.deckA : state.deckB;
    if (!playingDeckState.isPlaying || playingDeckState.duration == Duration.zero) return;

    // Start transition 30 seconds before end (gives 20s crossfade + 10s buffer)
    if (playingDeckState.remaining.inSeconds <= 30 &&
        playingDeckState.remaining.inSeconds > 0) {
      _startAutoMix();
    }
  }

  Future<void> _schedulePreload() async {
    // Small delay to let the player settle
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!state.autoQueue) return;

    final suggestion = _suggestNextTrack();
    if (suggestion == null) return;

    // Load onto the idle deck (not the playing deck) silently
    final idleDeck = _playingDeck == 0 ? 1 : 0;
    final idlePlayer = idleDeck == 0 ? _playerA : _playerB;

    try {
      await idlePlayer.stop();
      await idlePlayer.setFilePath(suggestion.filePath);
      // Sync BPM: pitch idle deck to match playing deck
      final playingDeckState = _playingDeck == 0 ? state.deckA : state.deckB;
      if (playingDeckState.track != null &&
          playingDeckState.track!.bpm > 0 &&
          suggestion.bpm > 0) {
        final neededSpeed = playingDeckState.effectiveBpm / suggestion.bpm;
        await idlePlayer.setSpeed(neededSpeed.clamp(0.7, 1.5));
      }
      // Set volume to 0 — preloaded but silent
      await idlePlayer.setVolume(0.0);

      final newDeck = (idleDeck == 0 ? state.deckA : state.deckB).copyWith(
        track: suggestion,
        isLoading: false,
        position: Duration.zero,
      );
      state = idleDeck == 0
          ? state.copyWith(deckA: newDeck, preloadedDeck: idleDeck)
          : state.copyWith(deckB: newDeck, preloadedDeck: idleDeck);

      dev.log('AutoQueue: preloaded "${suggestion.title}" onto deck $idleDeck',
          name: 'DjPlayer');
    } catch (e) {
      dev.log('AutoQueue preload error: $e', name: 'DjPlayer');
    }
  }

  Future<void> _startAutoMix() async {
    if (_autoMixing) return;
    _autoMixing = true;
    dev.log('AutoMix/Queue: starting transition from deck $_playingDeck',
        name: 'DjPlayer');

    final idleDeck = _playingDeck == 0 ? 1 : 0;
    final idlePlayer = idleDeck == 0 ? _playerA : _playerB;
    final idleDeckState = idleDeck == 0 ? state.deckA : state.deckB;

    // If idle deck has no preloaded track, try to suggest one now
    if (!idleDeckState.hasTrack) {
      final suggestion = _suggestNextTrack();
      if (suggestion != null) {
        try {
          await idlePlayer.setFilePath(suggestion.filePath);
          final playingState = _playingDeck == 0 ? state.deckA : state.deckB;
          if (playingState.track != null &&
              playingState.track!.bpm > 0 &&
              suggestion.bpm > 0) {
            final speed = playingState.effectiveBpm / suggestion.bpm;
            await idlePlayer.setSpeed(speed.clamp(0.7, 1.5));
          }
          await idlePlayer.setVolume(0.0);
          final newDeck = idleDeckState.copyWith(
              track: suggestion, position: Duration.zero);
          state = idleDeck == 0
              ? state.copyWith(deckA: newDeck)
              : state.copyWith(deckB: newDeck);
        } catch (e) {
          dev.log('AutoMix: failed to load suggestion: $e', name: 'DjPlayer');
          _autoMixing = false;
          return;
        }
      } else {
        _autoMixing = false;
        return;
      }
    }

    // Start playing the idle deck (from beginning or from preloaded position)
    try {
      await idlePlayer.seek(Duration.zero);
      await idlePlayer.play();
    } catch (_) {}

    // Crossfade over 20 seconds: playing deck fades out, idle deck fades in
    const steps = 40; // 40 steps × 500ms = 20 seconds
    const stepMs = 500;

    // Target crossfader position: fully on idle deck
    final targetFader = idleDeck == 0 ? 0.0 : 1.0;
    final startFader = state.crossfader;

    for (var i = 0; i <= steps; i++) {
      if (!state.autoMix && !state.autoQueue) break;
      final t = i / steps;
      final fader = startFader + (targetFader - startFader) * t;
      await setCrossfader(fader.clamp(0.0, 1.0));
      // Also ramp idle deck volume from 0 to 1
      try {
        await idlePlayer
            .setVolume((t * state.masterVolume).clamp(0.0, 1.0));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
    }

    // Transition complete — idle deck is now the playing deck
    _playingDeck = idleDeck;
    _autoMixing = false;

    dev.log('AutoMix/Queue: transition complete, now on deck $_playingDeck',
        name: 'DjPlayer');

    // If autoQueue: schedule preload of the NEXT next track
    if (state.autoQueue) {
      // ignore: discarded_futures
      _schedulePreload();
    }
  }

  /// Find the best next track from the library:
  /// Compatible Camelot key + BPM within ±8% of currently playing deck.
  LibraryTrack? _suggestNextTrack() {
    try {
      final lib = ref.read(libraryProvider);
      if (lib.tracks.isEmpty) return null;
      final playingDeckState = _playingDeck == 0 ? state.deckA : state.deckB;
      final current = playingDeckState.track;
      if (current == null) return null;
      final currentBpm = playingDeckState.effectiveBpm;
      final candidates = lib.tracks.where((t) {
        if (t.id == current.id) return false;
        if (t.id == state.deckA.track?.id) return false;
        if (t.id == state.deckB.track?.id) return false;
        if (t.filePath.isEmpty) return false;
        final bpmOk = currentBpm <= 0 || t.bpm <= 0 ||
            (t.bpm >= currentBpm * 0.92 && t.bpm <= currentBpm * 1.08);
        final keyOk = camelotCompatible(current.key, t.key);
        return bpmOk && keyOk;
      }).toList();

      if (candidates.isEmpty) return null;
      // Sort by BPM closeness
      candidates.sort((a, b) {
        final da = (a.bpm - currentBpm).abs();
        final db = (b.bpm - currentBpm).abs();
        return da.compareTo(db);
      });
      return candidates.first;
    } catch (_) {
      return null;
    }
  }

  /// Public: get next track suggestion for UI display
  LibraryTrack? get nextSuggestion => _suggestNextTrack();

  void _onDeckCompleted(int deck) {
    if (deck == _playingDeck) {
      // The main deck finished — if auto-queue/auto-mix was supposed to transition,
      // but somehow didn't, snap the crossfader now.
      if (state.autoMix || state.autoQueue) {
        final idleDeck = deck == 0 ? 1 : 0;
        _playingDeck = idleDeck;
        _autoMixing = false;
        state = state.copyWith(crossfader: idleDeck == 0 ? 0.0 : 1.0);
        // Schedule next preload
        if (state.autoQueue) {
          // ignore: discarded_futures
          _schedulePreload();
        }
      }
    }
  }

  void hide() => state = state.copyWith(isVisible: false);
  void show() => state = state.copyWith(isVisible: true);
}

final djPlayerProvider = NotifierProvider<DjPlayerNotifier, DjPlayerState>(
  DjPlayerNotifier.new,
);
