import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/library_track.dart';

// ── Physical crate types ──────────────────────────────────────────────────────

enum CrateType { virtualOnly, copyFiles, aliasLinks }

class PhysicalCrateResult {
  const PhysicalCrateResult({
    required this.cratePath,
    required this.filesCopied,
    required this.filesSkipped,
    required this.errors,
  });
  final String cratePath;
  final int filesCopied;
  final int filesSkipped;
  final List<String> errors;
}

// ── Export crate container ────────────────────────────────────────────────────

class ExportCrate {
  const ExportCrate({required this.name, required this.tracks});
  final String name;
  final List<LibraryTrack> tracks;
}

// ── Export service ────────────────────────────────────────────────────────────

class ExportService {
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

  Future<String> exportSeratoCsv(ExportCrate crate) async {
    final buf = StringBuffer();
    buf.writeln('name,artist,album,genre,bpm,key,duration,filepath');
    for (final t in crate.tracks) {
      buf.writeln('"${_csv(t.title)}","${_csv(t.artist)}","${_csv(t.album)}",'
          '"${_csv(t.genre)}","${t.bpm.toStringAsFixed(0)}","${t.key}",'
          '"${t.durationFormatted}","${_csv(t.filePath)}"');
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

  // ── Physical crate creation ───────────────────────────────────────────────

  /// Creates a physical crate on disk.
  ///
  /// - [CrateType.virtualOnly]  → writes an M3U playlist only (no file copy).
  /// - [CrateType.copyFiles]    → copies each source file into `destinationDir/crateName/`.
  /// - [CrateType.aliasLinks]   → creates macOS symlinks (dart:io Link) to source files.
  ///
  /// Returns a [PhysicalCrateResult] with copy counts and any errors.
  /// The [onProgress] callback reports `(done, total)` as each file is processed.
  Future<PhysicalCrateResult> createPhysicalCrate({
    required List<LibraryTrack> tracks,
    required String crateName,
    required CrateType type,
    required String destinationDir,
    bool overwriteExisting = false,
    void Function(int done, int total)? onProgress,
  }) async {
    // Virtual-only → just write M3U and return immediately.
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

    for (var i = 0; i < tracks.length; i++) {
      onProgress?.call(i, tracks.length);

      final t = tracks[i];
      final src = File(t.filePath);

      if (!src.existsSync()) {
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
          // aliasLinks — macOS symlink
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
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<String> _save(String filename, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory(p.join(dir.path, 'VibeRadar', 'Exports'));
    await exportsDir.create(recursive: true);
    final file = File(p.join(exportsDir.path, filename));
    await file.writeAsString(content);
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
}
