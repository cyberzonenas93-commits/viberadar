// ── CueProvider ───────────────────────────────────────────────────────────────
//
// Riverpod state management for hot-cue generation, storage, and VDJ writing.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cue_generation_result.dart';
import '../models/hot_cue.dart';
import '../models/library_track.dart';
import '../services/cue_analysis_service.dart';
import '../services/cue_export_service.dart';
import '../services/virtual_dj_cue_writer.dart';
import 'dj_export_provider.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class CueState {
  const CueState({
    this.isGenerating = false,
    this.generatingTrackId,
    this.results = const {},
    this.error,
    this.lastVdjWriteResult,
  });

  /// True while a generation task is in progress.
  final bool isGenerating;

  /// The track ID currently being processed (null when idle).
  final String? generatingTrackId;

  /// In-memory cache of generation results keyed by track ID.
  final Map<String, CueGenerationResult> results;

  /// Last non-null error message.
  final String? error;

  /// Result of the most recent VDJ database write.
  final VdjCueWriteResult? lastVdjWriteResult;

  CueState copyWith({
    bool? isGenerating,
    String? generatingTrackId,
    Map<String, CueGenerationResult>? results,
    String? error,
    VdjCueWriteResult? lastVdjWriteResult,
    bool clearGeneratingTrackId = false,
    bool clearError = false,
    bool clearVdjWriteResult = false,
  }) {
    return CueState(
      isGenerating: isGenerating ?? this.isGenerating,
      generatingTrackId: clearGeneratingTrackId
          ? null
          : (generatingTrackId ?? this.generatingTrackId),
      results: results ?? this.results,
      error: clearError ? null : (error ?? this.error),
      lastVdjWriteResult: clearVdjWriteResult
          ? null
          : (lastVdjWriteResult ?? this.lastVdjWriteResult),
    );
  }

  /// Returns cues for a given track ID, or an empty list.
  List<HotCue> cuesForTrack(String trackId) =>
      results[trackId]?.cues ?? const [];

  /// Returns the generation result for a track, or null.
  CueGenerationResult? resultForTrack(String trackId) => results[trackId];
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class CueNotifier extends Notifier<CueState> {
  late final CueAnalysisService _analysis;
  late final CueExportService _export;
  late final VirtualDjCueWriter _vdjWriter;

  @override
  CueState build() {
    _analysis = CueAnalysisService();
    _export = CueExportService();
    _vdjWriter = VirtualDjCueWriter();
    return const CueState();
  }

  // ── Generation ──────────────────────────────────────────────────────────

  /// Generates cues for a single [track] and caches the result.
  ///
  /// Does NOT write to any DJ software — use [writeToVirtualDj] for that.
  Future<CueGenerationResult> generateForTrack(LibraryTrack track) async {
    state = state.copyWith(
      isGenerating: true,
      generatingTrackId: track.id,
      clearError: true,
    );

    try {
      final result = await _analysis.generateCues(track);
      if (result.isSuccess) {
        await _export.saveCues(result);
      }

      final updated = Map<String, CueGenerationResult>.from(state.results);
      updated[track.id] = result;
      state = state.copyWith(
        isGenerating: false,
        results: updated,
        clearGeneratingTrackId: true,
      );
      return result;
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        clearGeneratingTrackId: true,
        error: 'Cue generation failed: $e',
      );
      rethrow;
    }
  }

  /// Generates cues for multiple tracks (batch / crate-level).
  ///
  /// Results are merged into [state.results] as they complete.
  Future<Map<String, CueGenerationResult>> generateForTracks(
      List<LibraryTrack> tracks) async {
    state = state.copyWith(isGenerating: true, clearError: true);
    final out = <String, CueGenerationResult>{};
    try {
      for (final track in tracks) {
        final result = await _analysis.generateCues(track);
        if (result.isSuccess) {
          await _export.saveCues(result);
        }
        out[track.id] = result;
      }
      final updated = Map<String, CueGenerationResult>.from(state.results)
        ..addAll(out);
      state = state.copyWith(
        isGenerating: false,
        results: updated,
        clearGeneratingTrackId: true,
      );
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        clearGeneratingTrackId: true,
        error: 'Batch cue generation failed: $e',
      );
    }
    return out;
  }

  // ── Loading from storage ────────────────────────────────────────────────

  /// Loads previously saved cues for [trackId] from SharedPreferences.
  Future<void> loadCuesForTrack(String trackId) async {
    final result = await _export.loadCues(trackId);
    if (result != null) {
      final updated = Map<String, CueGenerationResult>.from(state.results);
      updated[trackId] = result;
      state = state.copyWith(results: updated);
    }
  }

  /// Pre-loads cues for a list of track IDs from SharedPreferences.
  Future<void> preloadCues(List<String> trackIds) async {
    final cuemap = await _export.loadCuesForTracks(trackIds);
    if (cuemap.isEmpty) return;
    final updated = Map<String, CueGenerationResult>.from(state.results);
    for (final entry in cuemap.entries) {
      updated[entry.key] = CueGenerationResult(
        trackId: entry.key,
        status: CueGenerationStatus.success,
        cues: entry.value,
      );
    }
    state = state.copyWith(results: updated);
  }

  // ── User editing ────────────────────────────────────────────────────────

  /// Accepts a suggested cue (removes the isSuggested flag).
  Future<void> acceptCue(String trackId, HotCue cue) async {
    final accepted = await _export.acceptCue(trackId, cue);
    _replaceCueInState(trackId, accepted);
  }

  /// Accepts all suggested cues for a track.
  Future<void> acceptAllCues(String trackId) async {
    final result = state.results[trackId];
    if (result == null) return;
    final accepted = await Future.wait(
      result.cues.map((c) => _export.acceptCue(trackId, c)),
    );
    final updatedResult = CueGenerationResult(
      trackId: trackId,
      status: result.status,
      cues: accepted,
      aiUsed: result.aiUsed,
      generatedAt: result.generatedAt,
    );
    final updated = Map<String, CueGenerationResult>.from(state.results);
    updated[trackId] = updatedResult;
    state = state.copyWith(results: updated);
  }

  /// Updates a single cue (e.g., after user drags the position or edits label).
  Future<void> updateCue(String trackId, HotCue updatedCue) async {
    await _export.updateCue(trackId, updatedCue);
    _replaceCueInState(trackId, updatedCue);
  }

  /// Deletes all cues for [trackId].
  Future<void> deleteCues(String trackId) async {
    await _export.deleteCues(trackId);
    final updated = Map<String, CueGenerationResult>.from(state.results);
    updated.remove(trackId);
    state = state.copyWith(results: updated);
  }

  // ── VirtualDJ Phase-B write ─────────────────────────────────────────────

  /// Writes accepted cues for [track] to VirtualDJ's database.xml.
  ///
  /// Requires the VDJ root to be set in [djExportProvider].
  /// Only writes cues that are NOT isSuggested (accepted by user).
  Future<VdjCueWriteResult?> writeToVirtualDj(LibraryTrack track) async {
    final vdjRoot = ref.read(djExportProvider).vdjRoot;
    if (vdjRoot == null || vdjRoot.isEmpty) {
      state = state.copyWith(
        error: 'VirtualDJ root not set. Configure it in the Exports screen.',
      );
      return null;
    }

    final cues = state.cuesForTrack(track.id);
    final acceptedCues = cues.where((c) => !c.isSuggested).toList();
    if (acceptedCues.isEmpty) {
      state = state.copyWith(
        error: 'No accepted cues to write. Accept suggestions first.',
      );
      return null;
    }

    state = state.copyWith(isGenerating: true, clearError: true);
    try {
      final writeResult = await _vdjWriter.writeCues(
        vdjRoot: vdjRoot,
        trackFilePath: track.filePath,
        cues: acceptedCues,
      );

      if (writeResult.isSuccess) {
        // Mark all written cues as isWritten in storage.
        for (final cue in acceptedCues) {
          await _export.markCueWritten(track.id, cue);
        }
        // Refresh in-memory state.
        final refreshed = await _export.loadCues(track.id);
        if (refreshed != null) {
          final updated = Map<String, CueGenerationResult>.from(state.results);
          updated[track.id] = refreshed;
          state = state.copyWith(results: updated);
        }
      }

      state = state.copyWith(
        isGenerating: false,
        lastVdjWriteResult: writeResult,
      );
      return writeResult;
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: 'VDJ write failed: $e',
      );
      return null;
    }
  }

  // ── Error handling ──────────────────────────────────────────────────────

  void clearError() => state = state.copyWith(clearError: true);
  void clearVdjWriteResult() =>
      state = state.copyWith(clearVdjWriteResult: true);

  // ── Private helpers ─────────────────────────────────────────────────────

  void _replaceCueInState(String trackId, HotCue updated) {
    final result = state.results[trackId];
    if (result == null) return;
    final newCues = result.cues
        .map((c) => c.id == updated.id ? updated : c)
        .toList();
    final newResult = CueGenerationResult(
      trackId: trackId,
      status: result.status,
      cues: newCues,
      aiUsed: result.aiUsed,
      generatedAt: result.generatedAt,
    );
    final stateMap = Map<String, CueGenerationResult>.from(state.results);
    stateMap[trackId] = newResult;
    state = state.copyWith(results: stateMap);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final cueProvider = NotifierProvider<CueNotifier, CueState>(
  CueNotifier.new,
);
