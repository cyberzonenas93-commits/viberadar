import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/dj_export_result.dart';
import '../models/library_track.dart';

/// Writes VirtualDJ-compatible playlist files into the VirtualDJ library.
///
/// Output locations:
///   Playlist file : <VDJ_ROOT>/Folders/LocalMusic/<PlaylistName>.vdjfolder
///   Order file    : <VDJ_ROOT>/Folders/LocalMusic/order
///
/// File format: UTF-8 XML with root element <VirtualFolder>.
/// Each local track is a <Song /> element; TIDAL tracks use netsearch:// paths.
class VirtualDjExportService {
  static const _localMusicSubdir = 'Folders/LocalMusic';

  // ── Public API ───────────────────────────────────────────────────────────

  /// Export [tracks] as a VirtualDJ playlist folder.
  ///
  /// [vdjRoot]      : validated root directory of VirtualDJ.
  /// [playlistName] : human-readable crate / playlist name.
  /// [tracks]       : local library tracks to export.
  ///
  /// Returns a [DjExportResult] describing what was written.
  Future<DjExportResult> exportCrate({
    required String vdjRoot,
    required String playlistName,
    required List<LibraryTrack> tracks,
  }) async {
    // Resolve tracks — all LibraryTrack objects have real local paths.
    final resolved = tracks.map((t) => DjTrackResolution(
      title: t.title,
      artist: t.artist,
      status: DjTrackStatus.local,
      localFilePath: t.filePath,
      fileSizeBytes: t.fileSizeBytes,
      durationSeconds: t.durationSeconds,
      bpm: t.bpm,
      key: t.key,
    )).toList();

    // Ensure destination directory exists.
    final destDir = Directory(p.join(vdjRoot, _localMusicSubdir));
    await destDir.create(recursive: true);

    // Write the .vdjfolder file.
    final safeName = _safeName(playlistName);
    final folderFile = File(p.join(destDir.path, '$safeName.vdjfolder'));
    final xml = buildVdjFolder(playlistName, resolved);
    await folderFile.writeAsString(xml, flush: true);

    // Insert name into the order file (idempotent).
    await _updateOrderFile(destDir.path, safeName);

    return DjExportResult(
      target: DjExportTarget.virtualDj,
      crateName: playlistName,
      rootPath: vdjRoot,
      outputPath: folderFile.path,
      tracks: resolved,
      exportedAt: DateTime.now(),
    );
  }

  // ── XML builder ──────────────────────────────────────────────────────────

  /// Builds the UTF-8 XML content for a `.vdjfolder` file.
  ///
  /// VirtualDJ .vdjfolder format:
  ///   <?xml version="1.0" encoding="UTF-8"?>
  ///   <VirtualFolder>
  ///     <Song path="..." size="..." songlength="..." bpm="..." key="..."
  ///           artist="..." title="..." idx="0"/>
  ///   </VirtualFolder>
  String buildVdjFolder(String playlistName, List<DjTrackResolution> resolved) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<VirtualFolder>');
    for (var i = 0; i < resolved.length; i++) {
      final t = resolved[i];
      if (t.exportPath.isEmpty) continue;
      final attrs = StringBuffer();
      attrs.write('path="${_esc(t.exportPath)}"');
      if (t.fileSizeBytes > 0) attrs.write(' size="${t.fileSizeBytes}"');
      if (t.durationSeconds > 0) {
        attrs.write(' songlength="${t.durationSeconds.toStringAsFixed(0)}"');
      }
      if (t.bpm > 0) attrs.write(' bpm="${t.bpm.toStringAsFixed(2)}"');
      if (t.key.isNotEmpty) attrs.write(' key="${_esc(t.key)}"');
      if (t.artist.isNotEmpty) attrs.write(' artist="${_esc(t.artist)}"');
      if (t.title.isNotEmpty) attrs.write(' title="${_esc(t.title)}"');
      attrs.write(' idx="$i"');
      buf.writeln('  <Song $attrs/>');
    }
    buf.writeln('</VirtualFolder>');
    return buf.toString();
  }

  // ── Order file management ────────────────────────────────────────────────

  /// Inserts [playlistName] into the VirtualDJ `order` file exactly once.
  ///
  /// The `order` file is plain text — one entry per line, no extensions.
  /// Existing entries are never removed or reordered.
  Future<void> _updateOrderFile(String destDirPath, String playlistName) async {
    final orderFile = File(p.join(destDirPath, 'order'));
    List<String> lines = [];
    if (orderFile.existsSync()) {
      final content = await orderFile.readAsString();
      lines = content
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }
    if (!lines.contains(playlistName)) {
      lines.add(playlistName);
      await orderFile.writeAsString(lines.join('\n') + '\n', flush: true);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// XML-escapes a string for attribute values.
  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// Produces a filesystem-safe name from [s] (preserves spaces for VDJ order).
  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
}
