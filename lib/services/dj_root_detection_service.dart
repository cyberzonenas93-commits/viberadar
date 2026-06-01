import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ── Preference keys ───────────────────────────────────────────────────────────

const _kVdjRoot = 'vdj_root_path';
const _kSeratoRoot = 'serato_root_path';

// ── Validation helpers ────────────────────────────────────────────────────────

/// Files/directories whose presence confirms a VirtualDJ root.
const _vdjMarkers = ['database.xml', 'Folders', 'Playlists', 'History'];

/// Files/directories whose presence confirms a Serato root.
const _seratoMarkers = ['Subcrates', 'database V2'];

// ── Service ───────────────────────────────────────────────────────────────────

/// Detects, validates, and persists root directories for VirtualDJ and Serato.
///
/// Detection is macOS-first:
///   VirtualDJ → `~/Library/Application Support/VirtualDJ`
///   Serato     → `~/Music/_Serato_`
///
/// If auto-detection fails the caller is expected to let the user pick a
/// folder manually, then pass the confirmed path back to
/// [persistVirtualDjRoot] / [persistSeratoRoot].
class DjRootDetectionService {
  // ── VirtualDJ ─────────────────────────────────────────────────────────────

  /// Ordered list of macOS candidate paths for the VirtualDJ root.
  List<String> get _vdjCandidates {
    final home = _home;
    return [
      p.join(home, 'Library', 'Application Support', 'VirtualDJ'),
      p.join(home, 'Documents', 'VirtualDJ'),
    ];
  }

  /// Returns the first candidate path that passes [validateVirtualDjRoot],
  /// or `null` if none is found.
  Future<String?> detectVirtualDjRoot() async {
    for (final candidate in _vdjCandidates) {
      if (validateVirtualDjRoot(candidate)) return candidate;
    }
    return null;
  }

  /// Returns `true` when [path] is a valid VirtualDJ installation root.
  ///
  /// A path is valid when it exists as a directory AND contains at least
  /// two of the expected marker files / sub-directories.
  bool validateVirtualDjRoot(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;

    int found = 0;
    for (final marker in _vdjMarkers) {
      final child = p.join(path, marker);
      if (File(child).existsSync() || Directory(child).existsSync()) found++;
    }
    return found >= 2;
  }

  // ── Serato ────────────────────────────────────────────────────────────────

  /// Ordered list of macOS candidate paths for the Serato root.
  List<String> get _seratoCandidates {
    final home = _home;
    return [
      p.join(home, 'Music', '_Serato_'),
      p.join(home, 'Documents', '_Serato_'),
    ];
  }

  /// Returns the first candidate path that passes [validateSeratoRoot],
  /// or `null` if none is found.
  Future<String?> detectSeratoRoot() async {
    for (final candidate in _seratoCandidates) {
      if (validateSeratoRoot(candidate)) return candidate;
    }
    return null;
  }

  /// Returns `true` when [path] is a valid Serato installation root.
  ///
  /// A path is valid when it exists as a directory AND contains at least
  /// one of the expected marker files / sub-directories.
  bool validateSeratoRoot(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return false;

    for (final marker in _seratoMarkers) {
      final child = p.join(path, marker);
      if (File(child).existsSync() || Directory(child).existsSync()) {
        return true;
      }
    }
    return false;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> persistVirtualDjRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kVdjRoot, path);
  }

  Future<String?> getPersistedVirtualDjRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kVdjRoot);
  }

  Future<void> persistSeratoRoot(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSeratoRoot, path);
  }

  Future<String?> getPersistedSeratoRoot() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kSeratoRoot);
  }

  // ── Resolved root (persisted → auto-detect → null) ───────────────────────

  /// Resolves the VirtualDJ root using the following priority:
  ///   1. Persisted & still valid path
  ///   2. Auto-detected candidate
  ///   3. `null` (caller must prompt for manual selection)
  Future<String?> resolveVirtualDjRoot() async {
    final persisted = await getPersistedVirtualDjRoot();
    if (persisted != null && validateVirtualDjRoot(persisted)) return persisted;
    return detectVirtualDjRoot();
  }

  /// Resolves the Serato root using the same priority as [resolveVirtualDjRoot].
  Future<String?> resolveSeratoRoot() async {
    final persisted = await getPersistedSeratoRoot();
    if (persisted != null && validateSeratoRoot(persisted)) return persisted;
    return detectSeratoRoot();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _home {
    if (Platform.isMacOS || Platform.isLinux) {
      return Platform.environment['HOME'] ?? '/tmp';
    }
    return Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
  }
}
