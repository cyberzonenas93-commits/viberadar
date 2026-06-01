import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hot_cue.dart';
import '../models/library_track.dart';
import '../models/track.dart';
import '../services/cue_analysis_service.dart';
import '../services/cue_storage_service.dart';
import '../services/virtual_dj_cue_writer.dart';

// ── Status ─────────────────────────────────────────────────────────────────────
enum CueGenStatus { idle, analyzing, done, error }

// ── VDJ write status ───────────────────────────────────────────────────────────
enum VdjWriteStatus { idle, writing, done, error }

// ── State ──────────────────────────────────────────────────────────────────────
class CueState {
  const CueState({
    this.status        = CueGenStatus.idle,
    this.results       = const [],
    this.progress      = 0,
    this.total         = 0,
    this.errorMessage,
    this.vdjWriteStatus = VdjWriteStatus.idle,
    this.vdjWriteResults = const [],
    this.vdjWriteError,
    this.storedCues    = const {},
  });

  final CueGenStatus       status;
  final List<CueGenerationResult> results;
  final int                progress;
  final int                total;
  final String?            errorMessage;
  final VdjWriteStatus     vdjWriteStatus;
  final List<VdjCueWriteResult> vdjWriteResults;
  final String?            vdjWriteError;
  final Map<String, List<HotCue>> storedCues; // trackId → cues

  bool get isAnalyzing  => status == CueGenStatus.analyzing;
  bool get isDone       => status == CueGenStatus.done;
  bool get hasResults   => results.isNotEmpty;
  bool get isWritingVdj => vdjWriteStatus == VdjWriteStatus.writing;

  CueState copyWith({
    CueGenStatus?       status,
    List<CueGenerationResult>? results,
    int?                progress,
    int?                total,
    String?             errorMessage,
    VdjWriteStatus?     vdjWriteStatus,
    List<VdjCueWriteResult>? vdjWriteResults,
    String?             vdjWriteError,
    Map<String, List<HotCue>>? storedCues,
  }) {
    return CueState(
      status:          status          ?? this.status,
      results:         results         ?? this.results,
      progress:        progress        ?? this.progress,
      total:           total           ?? this.total,
      errorMessage:    errorMessage,
      vdjWriteStatus:  vdjWriteStatus  ?? this.vdjWriteStatus,
      vdjWriteResults: vdjWriteResults ?? this.vdjWriteResults,
      vdjWriteError:   vdjWriteError,
      storedCues:      storedCues      ?? this.storedCues,
    );
  }
}

// ── Notifier ───────────────────────────────────────────────────────────────────
class CueNotifier extends Notifier<CueState> {
  late final CueAnalysisService  _analysis;
  late final CueStorageService   _storage;
  late final VirtualDjCueWriter  _vdjWriter;

  @override
  CueState build() {
    _analysis  = CueAnalysisService();
    _storage   = CueStorageService();
    _vdjWriter = VirtualDjCueWriter();
    _loadStoredCues();
    return const CueState();
  }

  // ── Generation ─────────────────────────────────────────────────────────────

  Future<void> generateForTrack(
    LibraryTrack track, {
    Track? cloudTrack,
    bool useAi = true,
  }) async {
    state = state.copyWith(
      status: CueGenStatus.analyzing, results: [], progress: 1, total: 1,
    );
    try {
      final result = await _analysis.analyzeTrack(
        track, cloudTrack: cloudTrack, useAi: useAi,
      );
      await _storage.saveCues(track.id, result.cues);
      state = state.copyWith(
        status:   CueGenStatus.done,
        results:  [result],
        progress: 1,
        total:    1,
        storedCues: Map.from(state.storedCues)..[track.id] = result.cues,
      );
    } catch (e) {
      state = state.copyWith(
        status: CueGenStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> generateForCrate(
    List<LibraryTrack> tracks, {
    List<Track> cloudTracks = const [],
    bool useAi = true,
  }) async {
    if (tracks.isEmpty) return;
    state = state.copyWith(
      status: CueGenStatus.analyzing, results: [], progress: 0, total: tracks.length,
    );
    try {
      final results = await _analysis.analyzeBatch(
        tracks,
        cloudTracks: cloudTracks,
        useAi: useAi,
        onProgress: (done, total) =>
            state = state.copyWith(progress: done, total: total),
      );
      final updatedCues = Map<String, List<HotCue>>.from(state.storedCues);
      for (final r in results) {
        await _storage.saveCues(r.trackId, r.cues);
        updatedCues[r.trackId] = r.cues;
      }
      state = state.copyWith(
        status:     CueGenStatus.done,
        results:    results,
        progress:   tracks.length,
        total:      tracks.length,
        storedCues: updatedCues,
      );
    } catch (e) {
      state = state.copyWith(
        status: CueGenStatus.error, errorMessage: e.toString(),
      );
    }
  }

  // ── Per-result cue editing ─────────────────────────────────────────────────

  void removeCue(String resultTrackId, String cueId) {
    final updated = state.results.map((r) {
      if (r.trackId != resultTrackId) return r;
      return r.copyWith(cues: r.cues.where((c) => c.id != cueId).toList());
    }).toList();
    state = state.copyWith(results: updated);
  }

  void updateCueLabel(String resultTrackId, String cueId, String newLabel) {
    final updated = state.results.map((r) {
      if (r.trackId != resultTrackId) return r;
      return r.copyWith(
        cues: r.cues.map((c) =>
          c.id == cueId ? c.copyWith(label: newLabel) : c).toList(),
      );
    }).toList();
    state = state.copyWith(results: updated);
  }

  // ── VirtualDJ cue writing ──────────────────────────────────────────────────

  /// Write cues for a single track result to VirtualDJ's database.xml.
  /// User must have already confirmed the action in the UI.
  Future<void> writeResultToVirtualDj(
    CueGenerationResult result,
    String vdjRoot, {
    bool dryRun = false,
  }) async {
    if (result.localFilePath == null) {
      state = state.copyWith(
        vdjWriteStatus: VdjWriteStatus.error,
        vdjWriteError: 'No local file path — track must be in local library.',
      );
      return;
    }
    state = state.copyWith(vdjWriteStatus: VdjWriteStatus.writing);
    try {
      final writeResult = await _vdjWriter.writeCues(
        vdjRoot: vdjRoot,
        localFilePath: result.localFilePath!,
        cues: result.cues,
        dryRun: dryRun,
      );
      if (writeResult.success) {
        // Mark cues as written
        final updatedResults = state.results.map((r) {
          if (r.trackId != result.trackId) return r;
          return r.copyWith(
            cues: r.cues.map((c) => c.copyWith(
              isWritten: true, targetSoftware: 'virtualDJ')).toList(),
          );
        }).toList();
        await _storage.saveCues(result.trackId, updatedResults
            .firstWhere((r) => r.trackId == result.trackId).cues);
        state = state.copyWith(
          vdjWriteStatus:  VdjWriteStatus.done,
          vdjWriteResults: [writeResult],
          results:         updatedResults,
        );
      } else {
        state = state.copyWith(
          vdjWriteStatus: VdjWriteStatus.error,
          vdjWriteError:  writeResult.errorMessage,
        );
      }
    } catch (e) {
      state = state.copyWith(
        vdjWriteStatus: VdjWriteStatus.error,
        vdjWriteError:  e.toString(),
      );
    }
  }

  /// Write cues for all current results to VirtualDJ in one batch.
  Future<void> writeBatchToVirtualDj(String vdjRoot) async {
    final withPaths = state.results
        .where((r) => r.localFilePath != null && r.cues.isNotEmpty)
        .toList();
    if (withPaths.isEmpty) return;

    state = state.copyWith(vdjWriteStatus: VdjWriteStatus.writing);
    final cueMap = {for (final r in withPaths) r.localFilePath!: r.cues};
    try {
      final writeResults = await _vdjWriter.writeBatch(
        vdjRoot: vdjRoot, cuesByFilePath: cueMap,
      );
      state = state.copyWith(
        vdjWriteStatus:  VdjWriteStatus.done,
        vdjWriteResults: writeResults,
      );
    } catch (e) {
      state = state.copyWith(
        vdjWriteStatus: VdjWriteStatus.error, vdjWriteError: e.toString(),
      );
    }
  }

  // ── Storage ────────────────────────────────────────────────────────────────

  Future<void> _loadStoredCues() async {
    final all = await _storage.loadAllCues();
    state = state.copyWith(storedCues: all);
  }

  Future<List<HotCue>> loadCuesForTrack(String trackId) async {
    if (state.storedCues.containsKey(trackId)) return state.storedCues[trackId]!;
    return _storage.loadCues(trackId);
  }

  // ── Reset ──────────────────────────────────────────────────────────────────

  void reset() {
    state = CueState(storedCues: state.storedCues);
  }

  void resetVdjWrite() {
    state = state.copyWith(
      vdjWriteStatus: VdjWriteStatus.idle, vdjWriteError: null,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────
final cueProvider =
    NotifierProvider<CueNotifier, CueState>(CueNotifier.new);
