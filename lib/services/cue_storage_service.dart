import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/hot_cue.dart';

/// Persists cue suggestions inside VibeRadar using SharedPreferences.
///
/// Cues are stored as JSON per-track under the key:
///   hot_cues_v1_<trackId>
///
/// A manifest key tracks which track IDs have stored cues:
///   hot_cues_track_ids_v1
///
/// This storage is for VibeRadar's internal cue database only.
/// Writing cues to external DJ software is handled by [VirtualDjCueWriter].
class CueStorageService {
  static const _kPrefix    = 'hot_cues_v1_';
  static const _kIndexKey  = 'hot_cues_track_ids_v1';

  /// Persist [cues] for [trackId], replacing any previously stored set.
  Future<void> saveCues(String trackId, List<HotCue> cues) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_kPrefix$trackId',
      jsonEncode(cues.map((c) => c.toJson()).toList()),
    );
    final ids = await _allTrackIds(prefs);
    if (!ids.contains(trackId)) {
      ids.add(trackId);
      await prefs.setString(_kIndexKey, jsonEncode(ids));
    }
  }

  /// Load stored cues for [trackId]. Returns [] if none found.
  Future<List<HotCue>> loadCues(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeCues(prefs.getString('$_kPrefix$trackId'), trackId);
  }

  /// Remove stored cues for [trackId].
  Future<void> deleteCues(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPrefix$trackId');
    final ids = await _allTrackIds(prefs);
    if (ids.remove(trackId)) {
      await prefs.setString(_kIndexKey, jsonEncode(ids));
    }
  }

  /// Load all stored cues keyed by trackId.
  ///
  /// Previously this was O(N) SharedPreferences instance fetches (one per
  /// track). Now we grab the singleton instance once and read each key from
  /// it — the instance caches all keys in memory, so this becomes O(N) cheap
  /// lookups against an in-memory map.
  Future<Map<String, List<HotCue>>> loadAllCues() async {
    final prefs = await SharedPreferences.getInstance();
    final ids   = await _allTrackIds(prefs);
    final out   = <String, List<HotCue>>{};
    for (final id in ids) {
      out[id] = _decodeCues(prefs.getString('$_kPrefix$id'), id);
    }
    return out;
  }

  /// Returns true if cues exist for [trackId].
  Future<bool> hasCues(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_kPrefix$trackId');
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  List<HotCue> _decodeCues(String? raw, String trackId) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        developer.log(
          'Cue storage for $trackId is not a JSON array — resetting to empty',
          name: 'CueStorageService',
        );
        return const [];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(HotCue.fromJson)
          .toList();
    } on FormatException catch (e, st) {
      developer.log('Corrupt cue JSON for track $trackId — returning empty',
          name: 'CueStorageService', error: e, stackTrace: st);
      return const [];
    } catch (e, st) {
      developer.log('Failed to decode cues for track $trackId',
          name: 'CueStorageService', error: e, stackTrace: st);
      return const [];
    }
  }

  Future<List<String>> _allTrackIds(SharedPreferences prefs) async {
    final raw = prefs.getString(_kIndexKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        developer.log('Cue track index is not a JSON array — resetting',
            name: 'CueStorageService');
        return [];
      }
      return decoded.whereType<String>().toList();
    } on FormatException catch (e, st) {
      developer.log('Corrupt cue track index — returning empty',
          name: 'CueStorageService', error: e, stackTrace: st);
      return [];
    }
  }
}
