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

  // ── Real user home (sandbox-aware) ─────────────────────────────────────

  /// Returns the real user home directory, stripping sandbox container paths.
  ///
  /// In a sandboxed macOS app, `Platform.environment['HOME']` resolves to:
  ///   `/Users/<user>/Library/Containers/<app-id>/Data`
  /// which is NOT the real user home. VirtualDJ and Serato store their data
  /// in the real `~/Library/Application Support/VirtualDJ` and `~/Music/_Serato_`,
  /// not inside any app's container.
  ///
  /// This method detects the container path pattern and extracts the real home.
  static String get _realUserHome {
    final home = Platform.environment['HOME'] ?? '';
    // Sandboxed: /Users/<user>/Library/Containers/<bundle-id>/Data
    final containerMatch = RegExp(
      r'^(/Users/[^/]+)/Library/Containers/[^/]+/Data$',
    ).firstMatch(home);
    if (containerMatch != null) {
      return containerMatch.group(1)!;
    }
    // Not sandboxed or unrecognized pattern — use as-is
    return home;
  }

  // ── Default candidate paths (macOS) ─────────────────────────────────────

  static List<String> get _vdjCandidates {
    final home = _realUserHome;
    return [
      p.join(home, 'Library', 'Application Support', 'VirtualDJ'),
    ];
  }

  static List<String> get _seratoCandidates {
    final home = _realUserHome;
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
  /// Rejects and clears any persisted path that points into a sandbox container.
  Future<String?> resolveVirtualDjRoot() async {
    final persisted = await loadPersistedVirtualDjRoot();
    if (persisted != null) {
      if (_isInsideSandboxContainer(persisted)) {
        // Previous detection used sandbox HOME — clear it and re-detect
        await clearPersistedVirtualDjRoot();
      } else if (validateVirtualDjRoot(persisted)) {
        return persisted;
      }
    }
    final detected = await detectVirtualDjRoot();
    if (detected != null) await persistVirtualDjRoot(detected);
    return detected;
  }

  /// Returns the first validated Serato root found, or null.
  Future<String?> resolveSeratoRoot() async {
    final persisted = await loadPersistedSeratoRoot();
    if (persisted != null) {
      if (_isInsideSandboxContainer(persisted)) {
        await clearPersistedSeratoRoot();
      } else if (validateSeratoRoot(persisted)) {
        return persisted;
      }
    }
    final detected = await detectSeratoRoot();
    if (detected != null) await persistSeratoRoot(detected);
    return detected;
  }

  /// Returns true if the path is inside a macOS sandbox container.
  static bool _isInsideSandboxContainer(String path) {
    return path.contains('/Library/Containers/') && path.contains('/Data/');
  }

  /// Scans [_vdjCandidates] and returns the first valid one, or null.
  /// If VirtualDJ is installed but hasn't been run yet (root dir missing),
  /// bootstraps the minimum directory structure so exports can proceed.
  Future<String?> detectVirtualDjRoot() async {
    for (final candidate in _vdjCandidates) {
      if (validateVirtualDjRoot(candidate)) return candidate;
    }

    // VDJ is installed but hasn't been launched yet — bootstrap the root
    if (await _isVdjAppInstalled()) {
      final candidate = _vdjCandidates.first;
      try {
        // Create the minimum directories VDJ expects
        await Directory(p.join(candidate, 'Folders', 'LocalMusic')).create(recursive: true);
        await Directory(p.join(candidate, 'Playlists')).create(recursive: true);
        await Directory(p.join(candidate, 'History')).create(recursive: true);
        // Create a minimal database.xml so validation passes
        final dbFile = File(p.join(candidate, 'database.xml'));
        if (!dbFile.existsSync()) {
          await dbFile.writeAsString('<?xml version="1.0" encoding="UTF-8"?>\n<VirtualDJ_Database Version="8">\n</VirtualDJ_Database>\n');
        }
        // Now validate again — should pass with Folders + database.xml + Playlists
        if (validateVirtualDjRoot(candidate)) {
          await persistVirtualDjRoot(candidate);
          return candidate;
        }
      } catch (_) {
        // Permission denied or other error — fall through to null
      }
    }

    return null;
  }

  /// Check if VirtualDJ.app is installed in /Applications
  Future<bool> _isVdjAppInstalled() async {
    return Directory('/Applications/VirtualDJ.app').existsSync();
  }

  /// Scans [_seratoCandidates] and returns the first valid one, or null.
  /// If Serato is installed but root dir is missing, bootstraps it.
  Future<String?> detectSeratoRoot() async {
    for (final candidate in _seratoCandidates) {
      if (validateSeratoRoot(candidate)) return candidate;
    }

    // Serato is installed but hasn't created its folder yet
    if (await _isSeratoAppInstalled()) {
      final candidate = _seratoCandidates.first;
      try {
        await Directory(p.join(candidate, 'Subcrates')).create(recursive: true);
        await Directory(p.join(candidate, 'History')).create(recursive: true);
        await Directory(p.join(candidate, 'Metadata')).create(recursive: true);
        // Create minimal database V2 marker
        final dbFile = File(p.join(candidate, 'database V2'));
        if (!dbFile.existsSync()) {
          await dbFile.writeAsBytes([0x76, 0x72, 0x73, 0x6E, 0x00, 0x00, 0x00, 0x04, 0x00, 0x02, 0x00, 0x00]); // vrsn header
        }
        if (validateSeratoRoot(candidate)) {
          await persistSeratoRoot(candidate);
          return candidate;
        }
      } catch (_) {}
    }

    return null;
  }

  /// Check if Serato DJ is installed
  Future<bool> _isSeratoAppInstalled() async {
    return Directory('/Applications/Serato DJ Pro.app').existsSync() ||
           Directory('/Applications/Serato DJ Lite.app').existsSync();
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
