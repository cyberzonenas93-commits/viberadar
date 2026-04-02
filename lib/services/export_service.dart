import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/dj_export_models.dart';
import '../models/library_track.dart';
import 'action_log_service.dart';
import '../services/dj_root_detection_service.dart';
import '../services/local_match_service.dart';
import '../services/serato_export_service.dart';
import '../services/virtual_dj_export_service.dart';

// ── Physical crate types ──────────────────────────────────────────────────────

enum CrateType { virtualOnly, copyFiles, aliasLinks }

class PhysicalCrateResult {
  const PhysicalCrateResult({
    required this.cratePath,
    required this.filesCopied,
    required this.filesSkipped,
    required this.errors,
    this.missingTracks = const [],
  });
  final String cratePath;
  final int filesCopied;
  final int filesSkipped;
  final List<String> errors;

  /// Tracks that were requested but not found on disk.
  final List<String> missingTracks;

  bool get hasErrors => errors.isNotEmpty;
  bool get hasMissing => missingTracks.isNotEmpty;
  String get summary =>
      '$filesCopied copied, $filesSkipped skipped'
      '${hasMissing ? ', ${missingTracks.length} missing' : ''}'
      '${hasErrors ? ', ${errors.length} errors' : ''}';
}

// ── Export crate container ────────────────────────────────────────────────────

class ExportCrate {
  const ExportCrate({required this.name, required this.tracks});
  final String name;
  final List<LibraryTrack> tracks;
}

// ── Export service ────────────────────────────────────────────────────────────

class ExportService {
  // ── Specialist services (lazily wired) ─────────────────────────────────────
  final _vdjService = VirtualDjExportService();
  final _seratoService = SeratoExportService();
  final _rootDetection = DjRootDetectionService();

  // ── Existing formats (unchanged) ─────────────────────────────────────────

  Future<String> exportRekordboxXml(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<DJ_PLAYLISTS Version="1.0.0">');
    buf.writeln('  <PRODUCT Name="VibeRadar" Version="1.0.0" Company="VibeRadar"/>');
    buf.writeln('  <COLLECTION Entries="${crate.tracks.length}">');
    for (var i = 0; i < crate.tracks.length; i++) {
      final t = crate.tracks[i];
      buf.writeln('    <TRACK TrackID="${i + 1}" Name="${_esc(t.title)}" '
          'Artist="${_esc(t.artist)}" Album="${_esc(t.album)}" '
          'Genre="${_esc(t.genre)}" '
          'TotalTime="${t.durationSeconds.toStringAsFixed(0)}" '
          'AverageBpm="${t.bpm.toStringAsFixed(2)}" Tonality="${t.key}" '
          'Location="${Uri.file(t.filePath)}" Size="${t.fileSizeBytes}"/>');
    }
    buf.writeln('  </COLLECTION>');
    buf.writeln('  <PLAYLISTS>');
    buf.writeln('    <NODE Type="0" Name="ROOT" Count="1">');
    buf.writeln('      <NODE Name="${_esc(crate.name)}" Type="1" KeyType="0" '
        'Entries="${crate.tracks.length}">');
    for (var i = 0; i < crate.tracks.length; i++) {
      buf.writeln('        <TRACK Key="${i + 1}"/>');
    }
    buf.writeln('      </NODE>');
    buf.writeln('    </NODE>');
    buf.writeln('  </PLAYLISTS>');
    buf.writeln('</DJ_PLAYLISTS>');
    return _save('${_safeName(crate.name)}_rekordbox.xml', buf.toString());
  }

  /// Serato-compatible CSV with extended metadata columns.
  Future<String> exportSeratoCsv(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('name,artist,album,genre,bpm,key,duration,year,bitrate,filepath');
    for (final t in crate.tracks) {
      buf.writeln('"${_csv(t.title)}","${_csv(t.artist)}","${_csv(t.album)}",'
          '"${_csv(t.genre)}","${t.bpm.toStringAsFixed(0)}","${t.key}",'
          '"${t.durationFormatted}","${t.year ?? ''}","${t.bitrate}",'
          '"${_csv(t.filePath)}"');
    }
    return _save('${_safeName(crate.name)}_serato.csv', buf.toString());
  }

  Future<String> exportM3u(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('#EXTM3U');
    buf.writeln('#PLAYLIST:${crate.name}');
    for (final t in crate.tracks) {
      buf.writeln(
          '#EXTINF:${t.durationSeconds.toStringAsFixed(0)},${t.artist} - ${t.title}');
      buf.writeln(t.filePath);
    }
    return _save('${_safeName(crate.name)}.m3u', buf.toString());
  }

  Future<String> exportTraktorNml(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buf.writeln('<NML VERSION="19">');
    buf.writeln('  <COLLECTION ENTRIES="${crate.tracks.length}">');
    for (final t in crate.tracks) {
      final dir = p.dirname(t.filePath);
      final file = p.basename(t.filePath);
      buf.writeln('    <ENTRY TITLE="${_esc(t.title)}" ARTIST="${_esc(t.artist)}">');
      buf.writeln(
          '      <LOCATION DIR="${_esc(dir)}/" FILE="${_esc(file)}" VOLUME="/" VOLUMEID=""/>');
      buf.writeln('      <INFO GENRE="${_esc(t.genre)}" KEY="${t.key}"/>');
      buf.writeln(
          '      <TEMPO BPM="${t.bpm.toStringAsFixed(6)}" BPM_QUALITY="100"/>');
      buf.writeln('    </ENTRY>');
    }
    buf.writeln('  </COLLECTION>');
    buf.writeln('  <PLAYLISTS>');
    buf.writeln('    <NODE TYPE="FOLDER" NAME="\$ROOT">');
    buf.writeln('      <SUBNODES COUNT="1">');
    buf.writeln('        <NODE TYPE="PLAYLIST" NAME="${_esc(crate.name)}">');
    buf.writeln(
        '          <PLAYLIST ENTRIES="${crate.tracks.length}" TYPE="LIST">');
    for (final t in crate.tracks) {
      buf.writeln(
          '            <ENTRY><PRIMARYKEY TYPE="TRACK" KEY="${_esc(t.filePath)}"/></ENTRY>');
    }
    buf.writeln('          </PLAYLIST>');
    buf.writeln('        </NODE>');
    buf.writeln('      </SUBNODES>');
    buf.writeln('    </NODE>');
    buf.writeln('  </PLAYLISTS>');
    buf.writeln('</NML>');
    return _save('${_safeName(crate.name)}_traktor.nml', buf.toString());
  }

  /// VirtualDJ-compatible XML database export.
  /// VirtualDJ uses a simple XML format with <Song> entries inside a <VirtualFolder>.
  Future<String> exportVirtualDjXml(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<VirtualDJ_Database Version="8">');
    for (final t in crate.tracks) {
      final fileUrl = Uri.file(t.filePath).toString();
      buf.writeln('  <Song FilePath="${_esc(fileUrl)}" '
          'Title="${_esc(t.title)}" '
          'Artist="${_esc(t.artist)}" '
          'Album="${_esc(t.album)}" '
          'Genre="${_esc(t.genre)}" '
          'Year="${t.year ?? ''}" '
          'Bpm="${t.bpm.toStringAsFixed(2)}" '
          'Key="${t.key}" '
          'Bitrate="${t.bitrate}" '
          'SongLength="${t.durationSeconds.toStringAsFixed(1)}" '
          'FileSize="${t.fileSizeBytes}"/>');
    }
    buf.writeln('</VirtualDJ_Database>');
    return _save('${_safeName(crate.name)}_virtualdj.xml', buf.toString());
  }

  /// TIDAL-aware M3U export.
  /// Annotates each track with TIDAL search hints so DJ software with TIDAL
  /// integration can locate streaming versions of tracks the user doesn't own locally.
  Future<String> exportTidalAwareM3u(ExportCrate crate, {
    List<String> missingTrackHints = const [],
  }) async {
    final buf = StringBuffer();
    buf.writeln('#EXTM3U');
    buf.writeln('#PLAYLIST:${crate.name}');
    buf.writeln('#EXTGRP:VibeRadar Export (TIDAL-aware)');

    for (final t in crate.tracks) {
      buf.writeln(
          '#EXTINF:${t.durationSeconds.toStringAsFixed(0)},${t.artist} - ${t.title}');
      // TIDAL search hint as extended comment
      buf.writeln('#EXTVLCOPT:tidal-search=${Uri.encodeComponent('${t.artist} ${t.title}')}');
      buf.writeln(t.filePath);
    }

    // Append missing tracks as TIDAL-only search hints
    if (missingTrackHints.isNotEmpty) {
      buf.writeln('');
      buf.writeln('# ── Missing tracks (TIDAL search hints) ──');
      for (final hint in missingTrackHints) {
        buf.writeln('#EXTINF:-1,$hint');
        buf.writeln('#EXTVLCOPT:tidal-search=${Uri.encodeComponent(hint)}');
        buf.writeln('# NOT_IN_LOCAL_LIBRARY');
      }
    }

    return _save('${_safeName(crate.name)}_tidal.m3u', buf.toString());
  }

  /// Generate a manifest of missing tracks (tracks requested but not in library).
  Future<String> exportMissingManifest(String crateName, List<String> missingTracks) async {
    final buf = StringBuffer();
    buf.writeln('# VibeRadar — Missing Track Manifest');
    buf.writeln('# Crate: $crateName');
    buf.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('# ${missingTracks.length} tracks not found in local library');
    buf.writeln('');
    for (var i = 0; i < missingTracks.length; i++) {
      buf.writeln('${i + 1}. ${missingTracks[i]}');
    }
    buf.writeln('');
    buf.writeln('# Search these on: Apple Music, Spotify, YouTube, TIDAL, Beatport');
    return _save('${_safeName(crateName)}_missing.txt', buf.toString());
  }

  // ── DJ software exports ───────────────────────────────────────────────────

  /// Exports [matches] to VirtualDJ.
  ///
  /// Resolves the VirtualDJ root automatically; falls back to [overrideRoot]
  /// when auto-detection fails and the caller has already prompted the user.
  /// Persists the confirmed root for future calls.
  Future<DjExportResult> exportToVirtualDj({
    required String playlistName,
    required List<TrackMatch> matches,
    bool useTidal = false,
    Map<String, String> tidalIds = const {},
    String? overrideRoot,
  }) async {
    final root = await _resolveAndPersistVdjRoot(overrideRoot);
    if (root == null) {
      throw StateError(
        'VirtualDJ root not found. Please open VirtualDJ at least once or'
        ' choose the folder manually.',
      );
    }

    return _vdjService.export(
      playlistName: playlistName,
      matches: matches,
      vdjRoot: root,
      useTidal: useTidal,
      tidalIds: tidalIds,
    );
  }

  /// Exports [matches] to a Serato `.crate` file.
  ///
  /// Resolves the Serato root automatically; falls back to [overrideRoot]
  /// when the caller has already prompted the user.
  /// Persists the confirmed root for future calls.
  Future<DjExportResult> exportToSerato({
    required String playlistName,
    required List<TrackMatch> matches,
    String? parentCrateName,
    String? overrideRoot,
  }) async {
    final root = await _resolveAndPersistSeratoRoot(overrideRoot);
    if (root == null) {
      throw StateError(
        'Serato root not found. Please open Serato at least once or choose'
        ' the folder manually.',
      );
    }

    return _seratoService.export(
      playlistName: playlistName,
      matches: matches,
      seratoRoot: root,
      parentCrateName: parentCrateName,
    );
  }

  // ── Root resolution helpers ───────────────────────────────────────────────

  Future<String?> _resolveAndPersistVdjRoot(String? override) async {
    if (override != null && _rootDetection.validateVirtualDjRoot(override)) {
      await _rootDetection.persistVirtualDjRoot(override);
      return override;
    }
    final root = await _rootDetection.resolveVirtualDjRoot();
    if (root != null) await _rootDetection.persistVirtualDjRoot(root);
    return root;
  }

  Future<String?> _resolveAndPersistSeratoRoot(String? override) async {
    if (override != null && _rootDetection.validateSeratoRoot(override)) {
      await _rootDetection.persistSeratoRoot(override);
      return override;
    }
    final root = await _rootDetection.resolveSeratoRoot();
    if (root != null) await _rootDetection.persistSeratoRoot(root);
    return root;
  }

  // ── Physical crate creation ───────────────────────────────────────────────

  Future<PhysicalCrateResult> createPhysicalCrate({
    required List<LibraryTrack> tracks,
    required String crateName,
    required CrateType type,
    required String destinationDir,
    bool overwriteExisting = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (type == CrateType.virtualOnly) {
      final m3uPath =
          await exportM3u(ExportCrate(name: crateName, tracks: tracks));
      return PhysicalCrateResult(
        cratePath: m3uPath,
        filesCopied: 0,
        filesSkipped: 0,
        errors: [],
      );
    }

    final safeFolder = _safeName(crateName);
    final crateDir = Directory(p.join(destinationDir, safeFolder));
    await crateDir.create(recursive: true);

    int copied = 0;
    int skipped = 0;
    final errors = <String>[];
    final missing = <String>[];

    for (var i = 0; i < tracks.length; i++) {
      onProgress?.call(i, tracks.length);

      final t = tracks[i];
      final src = File(t.filePath);

      if (!src.existsSync()) {
        missing.add('${t.artist} - ${t.title}');
        errors.add('Source not found: ${t.filePath}');
        skipped++;
        continue;
      }

      final destName = p.basename(t.filePath);
      final destPath = p.join(crateDir.path, destName);
      final destFile = File(destPath);

      if (destFile.existsSync() && !overwriteExisting) {
        skipped++;
        continue;
      }

      try {
        if (type == CrateType.copyFiles) {
          await src.copy(destPath);
          copied++;
        } else {
          if (destFile.existsSync()) await destFile.delete();
          await Link(destPath).create(t.filePath, recursive: false);
          copied++;
        }
      } catch (e) {
        errors.add('${t.fileName}: $e');
        skipped++;
      }
    }

    onProgress?.call(tracks.length, tracks.length);

    return PhysicalCrateResult(
      cratePath: crateDir.path,
      filesCopied: copied,
      filesSkipped: skipped,
      errors: errors,
      missingTracks: missing,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Returns the default exports directory path (Desktop/VibeRadar Exports).
  static Future<String> getExportsPath() async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, 'Desktop', 'VibeRadar Exports');
  }

  /// Reveals a file in Finder.
  static Future<void> revealInFinder(String filePath) async {
    await Process.run('open', ['-R', filePath]);
  }

  /// Opens the exports folder in Finder.
  static Future<void> openExportsFolder() async {
    final path = await getExportsPath();
    await Directory(path).create(recursive: true);
    await Process.run('open', [path]);
  }

  final _actionLog = ActionLogService();

  Future<String> _save(String filename, String content) async {
    final exportsPath = await getExportsPath();
    final exportsDir = Directory(exportsPath);
    await exportsDir.create(recursive: true);
    final file = File(p.join(exportsDir.path, filename));
    await file.writeAsString(content);
    // Auto-log every export
    await _actionLog.logExport(
      format: p.extension(filename).replaceFirst('.', ''),
      exportPath: file.path,
      trackCount: content.split('\n').where((l) => l.trim().isNotEmpty).length,
    );
    return file.path;
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String _csv(String s) => s.replaceAll('"', '""');
  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  // ── AI Crate exports (metadata-only, no local files) ─────────────────────

  /// Export an AI-generated crate as M3U with platform URLs.
  Future<String> exportAiCrateM3u(String crateName, List<dynamic> tracks) async {
    final buf = StringBuffer();
    buf.writeln('#EXTM3U');
    buf.writeln('#PLAYLIST:$crateName');
    buf.writeln('#EXTGRP:VibeRadar AI Crate');
    for (final t in tracks) {
      final title = t.title as String;
      final artist = t.artist as String;
      final url = t.bestUrl as String;
      buf.writeln('#EXTINF:-1,$artist - $title');
      if (url.isNotEmpty) {
        buf.writeln(url);
      } else {
        buf.writeln('# NOT FOUND ON PLATFORMS');
      }
    }
    return _save('${_safeName(crateName)}_ai.m3u', buf.toString());
  }

  /// Export an AI crate as CSV (importable to Serato/VirtualDJ/Rekordbox).
  Future<String> exportAiCrateCsv(String crateName, List<dynamic> tracks) async {
    final buf = StringBuffer();
    buf.writeln('title,artist,bpm,key,spotify_url,apple_url,status');
    for (final t in tracks) {
      buf.writeln('"${_csv(t.title as String)}","${_csv(t.artist as String)}",'
          '"${t.bpm}","${t.key}",'
          '"${_csv(t.spotifyUrl as String? ?? '')}","${_csv(t.appleUrl as String? ?? '')}",'
          '"${(t.resolved as bool) ? 'found' : 'missing'}"');
    }
    return _save('${_safeName(crateName)}_ai.csv', buf.toString());
  }

  /// Export an AI crate as a text manifest (human-readable).
  Future<String> exportAiCrateManifest(String crateName, List<dynamic> tracks) async {
    final buf = StringBuffer();
    buf.writeln('# VibeRadar AI Crate: $crateName');
    buf.writeln('# Generated: ${DateTime.now().toIso8601String()}');
    buf.writeln('# ${tracks.length} tracks');
    buf.writeln('');
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final status = (t.resolved as bool) ? 'FOUND' : 'MISSING';
      buf.writeln('${i + 1}. ${t.artist} - ${t.title} (${t.bpm} BPM, ${t.key}) [$status]');
      if (t.spotifyUrl != null) buf.writeln('   Spotify: ${t.spotifyUrl}');
      if (t.appleUrl != null) buf.writeln('   Apple Music: ${t.appleUrl}');
      if (!(t.resolved as bool)) buf.writeln('   ⚠️ Not found — search manually');
      buf.writeln('');
    }
    return _save('${_safeName(crateName)}_ai_manifest.txt', buf.toString());
  }
}
