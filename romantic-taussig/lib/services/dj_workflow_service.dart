import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Detects and manages DJ software paths for VirtualDJ, Serato, etc.
class DjWorkflowService {
  static const _prefVdjPath = 'vdj_library_path';
  static const _prefSeratoPath = 'serato_library_path';
  static const _prefVdjAutoLoad = 'vdj_auto_load';
  static const _prefSeratoAutoLoad = 'serato_auto_load';

  // ── VirtualDJ ──────────────────────────────────────────────────────────

  /// Detect likely VirtualDJ database/library path.
  static Future<String?> detectVirtualDjPath() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      p.join(home, 'Documents', 'VirtualDJ'),
      p.join(home, 'Library', 'Application Support', 'VirtualDJ'),
      p.join(home, 'Music', 'VirtualDJ'),
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  /// Get the saved or detected VirtualDJ path.
  static Future<String?> getVirtualDjPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefVdjPath);
    if (saved != null && saved.isNotEmpty && Directory(saved).existsSync()) {
      return saved;
    }
    return detectVirtualDjPath();
  }

  /// Save a manual VirtualDJ path.
  static Future<void> setVirtualDjPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVdjPath, path);
  }

  /// Whether VirtualDJ auto-load is enabled.
  static Future<bool> isVdjAutoLoadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefVdjAutoLoad) ?? false;
  }

  static Future<void> setVdjAutoLoad(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefVdjAutoLoad, enabled);
  }

  /// Place an export file into VirtualDJ's Playlists folder.
  /// Returns the destination path, or null if VDJ not found.
  static Future<String?> placeInVirtualDj(String exportFilePath) async {
    final vdjPath = await getVirtualDjPath();
    if (vdjPath == null) return null;

    final playlistsDir = Directory(p.join(vdjPath, 'Playlists'));
    await playlistsDir.create(recursive: true);

    final destPath = p.join(playlistsDir.path, p.basename(exportFilePath));
    await File(exportFilePath).copy(destPath);
    return destPath;
  }

  // ── Serato ─────────────────────────────────────────────────────────────

  /// Detect likely Serato library path.
  static Future<String?> detectSeratoPath() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      p.join(home, 'Music', '_Serato_'),
      p.join(home, 'Music', 'Serato'),
      p.join(home, 'Library', 'Application Support', 'Serato'),
      p.join(home, 'Documents', 'Serato'),
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  /// Get the saved or detected Serato path.
  static Future<String?> getSeratoPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefSeratoPath);
    if (saved != null && saved.isNotEmpty && Directory(saved).existsSync()) {
      return saved;
    }
    return detectSeratoPath();
  }

  /// Save a manual Serato path.
  static Future<void> setSeratoPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSeratoPath, path);
  }

  static Future<bool> isSeratoAutoLoadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefSeratoAutoLoad) ?? false;
  }

  static Future<void> setSeratoAutoLoad(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSeratoAutoLoad, enabled);
  }

  /// Place an export file into Serato's subcrates folder.
  static Future<String?> placeInSerato(String exportFilePath) async {
    final seratoPath = await getSeratoPath();
    if (seratoPath == null) return null;

    final subcratesDir = Directory(p.join(seratoPath, 'SubCrates'));
    await subcratesDir.create(recursive: true);

    final destPath = p.join(subcratesDir.path, p.basename(exportFilePath));
    await File(exportFilePath).copy(destPath);
    return destPath;
  }

  // ── Detection summary ──────────────────────────────────────────────────

  /// Returns a map of detected DJ software and their paths.
  static Future<Map<String, String?>> detectAll() async {
    return {
      'VirtualDJ': await getVirtualDjPath(),
      'Serato': await getSeratoPath(),
    };
  }
}

/// Safety settings for library operations.
class LibrarySafetySettings {
  static const _prefCrateMode = 'safety_crate_mode';
  static const _prefCleanupMode = 'safety_cleanup_mode';
  static const _prefConfirmActions = 'safety_confirm_actions';
  static const _prefCrateOutputPath = 'safety_crate_output_path';
  static const _prefReviewFolderPath = 'safety_review_folder_path';

  /// Default crate mode: 'copy' or 'alias'
  static Future<String> getCrateMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCrateMode) ?? 'copy';
  }

  static Future<void> setCrateMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCrateMode, mode);
  }

  /// Duplicate cleanup mode: 'trash' or 'review'
  static Future<String> getCleanupMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCleanupMode) ?? 'trash';
  }

  static Future<void> setCleanupMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCleanupMode, mode);
  }

  /// Whether to require confirmation before file actions (default: true).
  static Future<bool> getConfirmActions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefConfirmActions) ?? true;
  }

  static Future<void> setConfirmActions(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefConfirmActions, enabled);
  }

  /// Default crate output folder path.
  static Future<String?> getCrateOutputPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefCrateOutputPath);
  }

  static Future<void> setCrateOutputPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCrateOutputPath, path);
  }

  /// Default review folder for duplicate cleanup.
  static Future<String?> getReviewFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefReviewFolderPath);
  }

  static Future<void> setReviewFolderPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefReviewFolderPath, path);
  }
}
