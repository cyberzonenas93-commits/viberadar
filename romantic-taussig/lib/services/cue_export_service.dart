// ── CueExportService ──────────────────────────────────────────────────────────
//
// VibeRadar-internal cue storage (Phase A).
//
// Cues are stored as JSON in SharedPreferences, keyed by track ID.
// This is "Phase A" — cues live only inside VibeRadar and do not touch
// any DJ software files.
//
// Phase B (VirtualDJ database.xml) is handled by VirtualDjCueWriter.
// Phase C (Serato) is intentionally deferred.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cue_generation_result.dart';
import '../models/hot_cue.dart';

class CueExportService {
  static const String _prefsKeyPrefix = 'vr_cues_';
  static const String _prefsKeyIndex = 'vr_cues_index';

  // ── Save / Load ─────────────────────────────────────────────────────────

  /// Persists all cues from [result] to SharedPreferences.
  ///
  /// If cues already exist for the track, they are replaced entirely.
  Future<void> saveCues(CueGenerationResult result) async {
    if (result.cues.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    final encoded = jsonEncode(result.toJson());
    await prefs.setString('$_prefsKeyPrefix${result.trackId}', encoded);

    // Update the index so we can enumerate all stored track IDs quickly.
    final index = await _loadIndex(prefs);
    if (!index.contains(result.trackId)) {
      index.add(result.trackId);
      await prefs.setStringList(_prefsKeyIndex, index);
    }
  }

  /// Loads saved cues for a single [trackId].
  ///
  /// Returns null if no cues have been saved for that track.
  Future<CueGenerationResult?> loadCues(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsKeyPrefix$trackId');
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CueGenerationResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Loads the flat list of [HotCue]s for [trackId], or an empty list.
  Future<List<HotCue>> loadCueList(String trackId) async {
    final result = await loadCues(trackId);
    return result?.cues ?? const [];
  }

  /// Loads saved cues for all [trackIds] in one batch call.
  ///
  /// Returns a map of trackId → [HotCue] list (only for tracks that have data).
  Future<Map<String, List<HotCue>>> loadCuesForTracks(
      List<String> trackIds) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, List<HotCue>>{};

    for (final id in trackIds) {
      final raw = prefs.getString('$_prefsKeyPrefix$id');
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final result = CueGenerationResult.fromJson(json);
        if (result.cues.isNotEmpty) {
          out[id] = result.cues;
        }
      } catch (_) {
        // Corrupt entry — skip silently.
      }
    }
    return out;
  }

  /// Returns all track IDs that have stored cues.
  Future<List<String>> allStoredTrackIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadIndex(prefs);
  }

  // ── Update / Delete ─────────────────────────────────────────────────────

  /// Replaces a single cue by id for [trackId].
  ///
  /// If no stored result exists for [trackId], creates a new one.
  Future<void> updateCue(String trackId, HotCue updatedCue) async {
    final existing = await loadCues(trackId);
    final List<HotCue> cues;
    if (existing == null) {
      cues = [updatedCue];
    } else {
      cues = existing.cues
          .map((c) => c.id == updatedCue.id ? updatedCue : c)
          .toList();
      // If no replacement happened, append.
      if (!cues.any((c) => c.id == updatedCue.id)) {
        cues.add(updatedCue);
      }
    }

    final updated = CueGenerationResult(
      trackId: trackId,
      status: CueGenerationStatus.success,
      cues: cues,
      aiUsed: existing?.aiUsed ?? false,
      generatedAt: existing?.generatedAt ?? DateTime.now(),
    );
    await saveCues(updated);
  }

  /// Deletes all stored cues for [trackId].
  Future<void> deleteCues(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsKeyPrefix$trackId');

    final index = await _loadIndex(prefs);
    index.remove(trackId);
    await prefs.setStringList(_prefsKeyIndex, index);
  }

  /// Clears ALL stored cues from SharedPreferences.
  Future<void> clearAllCues() async {
    final prefs = await SharedPreferences.getInstance();
    final index = await _loadIndex(prefs);
    for (final id in index) {
      await prefs.remove('$_prefsKeyPrefix$id');
    }
    await prefs.remove(_prefsKeyIndex);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<List<String>> _loadIndex(SharedPreferences prefs) async {
    return List<String>.from(prefs.getStringList(_prefsKeyIndex) ?? []);
  }

  /// Marks a [HotCue] as accepted by the user (removes the isSuggested flag).
  Future<HotCue> acceptCue(String trackId, HotCue cue) async {
    final accepted = cue.copyWith(isSuggested: false);
    await updateCue(trackId, accepted);
    return accepted;
  }

  /// Marks a [HotCue] as written to DJ software.
  Future<HotCue> markCueWritten(String trackId, HotCue cue) async {
    final written = cue.copyWith(isWritten: true, isSuggested: false);
    await updateCue(trackId, written);
    return written;
  }
}
