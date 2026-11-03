import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Detects, validates and persists the root folders for VirtualDJ and Serato.
///
/// macOS-first: default candidate paths are macOS conventions.
/// Manual folder override is always supported.
class DjRootDetectionService {
  // ── Preference keys ──────────────────────────────────────────────────────

  static const _kVdjRoot = 'dj_root_virtualdj';
  static const _kSeratoRoot = 'dj_root_serato';

  // ── Default candidate paths (macOS) ─────────────────────────────────────

  static List<String> get _vdjCandidates {
    final home = Platform.environment['HOME'] ?? '';
    return [
      p.join(home, 'Library', 'Application Support', 'VirtualDJ'),
    ];
  }

  static List<String> get _seratoCandidates {
    final home = Platform.environment['HOME'] ?? '';
    return [
      p.join(home, 'Music', '_Serato_'),
    ];
  }

  // ── Validation markers ───────────────────────────────────────────────────

  /// At least 2 of these must exist to call a VirtualDJ root valid.
  static const _vdjMarkers = [
    'database.xml',
    'settings.xml',
    'Folders',
    'Playlists',
    'History',
  ];

  /// At least 2 of these must exist to call a Serato root valid.
  static const _seratoMarkers = [
    'Subcrates',
    'database V2',
    'History',
    'Metadata',
  ];

  // ── Public API ───────────────────────────────────────────────────────────

  /// Returns the first validated VirtualDJ root found, or null.
  /// Checks the persisted path first, then falls back to auto-detection.
  Future<String?> resolveVirtualDjRoot() async {
    final persisted = await loadPersistedVirtualDjRoot();
    if (persisted != null && validateVirtualDjRoot(persisted)) return persisted;
    return detectVirtualDjRoot();
  }

  /// Returns the first validated Serato root found, or null.
  Future<String?> resolveSeratoRoot() async {
    final persisted = await loadPersistedSeratoRoot();
    if (persisted != null && validateSeratoRoot(persisted)) return persisted;
    return detectSeratoRoot();
  }

  /// Scans [_vdjCandidates] and returns the first valid one, or null.
  Future<String?> detectVirtualDjRoot() async {
    for (final candidate in _vdjCandidates) {
      if (validateVirtualDjRoot(candidate)) return candidate;
    }
    return null;
  }

  /// Scans [_seratoCandidates] and returns the first valid one, or null.
  Future<String?> detectSeratoRoot() async {
    for (final candidate in _seratoCandidates) {
      if (validateSeratoRoot(candidate)) return candidate;
    }
    return null;
  }

  /// Returns true if [path] looks like a real VirtualDJ root directory.
  /// Requires at least 2 known markers to be present.
  bool validateVirtualDjRoot(String path) {
    if (path.isEmpty) return false;
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    int hits = 0;
    for (final marker in _vdjMarkers) {
      final child = p.join(path, marker);
      if (File(child).existsSync() || Directory(child).existsSync()) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  /// Returns true if [path] looks like a real Serato root directory.
  /// Requires at least 2 known markers to be present.
  bool validateSeratoRoot(String path) {
    if (path.isEmpty) return false;
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    int hits = 0;
    for (final marker in _seratoMarkers) {
      final child = p.join(path, marker);
      if (File(child).existsSync() || Directory(child).existsSync()) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> persistVirtualDjRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVdjRoot, path);
  }

  Future<void> persistSeratoRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeratoRoot, path);
  }

  Future<String?> loadPersistedVirtualDjRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVdjRoot);
  }

  Future<String?> loadPersistedSeratoRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSeratoRoot);
  }

  Future<void> clearPersistedVirtualDjRoot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVdjRoot);
  }

  Future<void> clearPersistedSeratoRoot() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeratoRoot);
  }
}
