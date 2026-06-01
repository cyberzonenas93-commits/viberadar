import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/dj_export_models.dart';
import '../models/library_track.dart';
import '../models/track.dart';
import '../services/local_match_service.dart';

// ── VirtualDJ export service ──────────────────────────────────────────────────

/// Writes VirtualDJ `.vdjfolder` XML playlist files and keeps the
/// `order` file up-to-date.
///
/// File layout written by this service:
///   `<vdjRoot>/Folders/LocalMusic/<PlaylistName>.vdjfolder`
///   `<vdjRoot>/Folders/LocalMusic/order`  (updated, not replaced)
class VirtualDjExportService {
  // ── Public API ────────────────────────────────────────────────────────────

  /// Resolves each match in [matches] to a [DjExportTrack], writes the
  /// `.vdjfolder` file and updates the `order` file.
  ///
  /// [tidalIds] maps `cloudTrack.id` → real TIDAL track ID (digits only).
  /// Only used when [useTidal] is `true`.
  Future<DjExportResult> export({
    required String playlistName,
    required List<TrackMatch> matches,
    required String vdjRoot,
    bool useTidal = false,
    Map<String, String> tidalIds = const {},
  }) async {
    final exportTracks = _resolve(matches, useTidal: useTidal, tidalIds: tidalIds);

    // Build XML
    final xml = buildVdjFolderXml(exportTracks);

    // Write .vdjfolder file
    final outputPath = await _writeFolderFile(vdjRoot, playlistName, xml);

    // Update order file
    await updateOrderFile(vdjRoot, playlistName);

    return DjExportResult(
      target: DjTarget.virtualDj,
      playlistName: playlistName,
      totalTracks: exportTracks.length,
      localMatchCount: exportTracks.where((t) => t.isLocalMatch).length,
      tidalCount: exportTracks.where((t) => t.isTidalFallback).length,
      skippedCount: exportTracks.where((t) => t.isSkipped).length,
      outputPath: outputPath,
      djRoot: vdjRoot,
      tracks: exportTracks,
      warning: 'Refresh the VirtualDJ browser or restart the app to see your'
          ' new playlist.',
    );
  }

  // ── Resolution ────────────────────────────────────────────────────────────

  List<DjExportTrack> _resolve(
    List<TrackMatch> matches, {
    required bool useTidal,
    required Map<String, String> tidalIds,
  }) {
    return matches.map((m) {
      // 1 ── Local match ─────────────────────────────────────────────────────
      if (m.isFound || m.isFuzzy) {
        return DjExportTrack(
          cloudTrack: m.vibeTrack,
          localTrack: _libTrackFor(m),
          resolution: DjTrackResolution.localMatch,
        );
      }

      // 2 ── TIDAL fallback (VDJ only) ───────────────────────────────────────
      if (useTidal) {
        final tidalId = _resolveTidalId(m.vibeTrack, tidalIds);
        if (tidalId != null) {
          return DjExportTrack(
            cloudTrack: m.vibeTrack,
            resolution: DjTrackResolution.tidalFallback,
            tidalId: tidalId,
          );
        }
      }

      // 3 ── Skip ────────────────────────────────────────────────────────────
      return DjExportTrack(
        cloudTrack: m.vibeTrack,
        resolution: DjTrackResolution.skipped,
        skipReason: useTidal
            ? 'Not found locally and no TIDAL ID resolved'
            : 'Not found in local library',
      );
    }).toList();
  }

  /// Extracts the TIDAL track ID from the provided [tidalIds] map first,
  /// then falls back to parsing the track's `platformLinks['tidal']` URL.
  String? _resolveTidalId(Track t, Map<String, String> tidalIds) {
    // Caller-supplied (e.g. from a prior TIDAL search step)
    if (tidalIds.containsKey(t.id)) return tidalIds[t.id];

    // Parse from platform link: https://tidal.com/browse/track/12345678
    final tidalLink = t.platformLinks['tidal'];
    if (tidalLink == null) return null;
    final match = RegExp(r'/track/(\d+)').firstMatch(tidalLink);
    return match?.group(1);
  }

  /// Returns a minimal synthetic [LibraryTrack] from the match (to access
  /// file-level metadata like size / duration from the local file).
  LibraryTrack? _libTrackFor(TrackMatch m) {
    if (m.localFilePath == null) return null;
    // We only have the path here; the caller can pass richer LibraryTrack data
    // through [matchesWithLibrary] if needed.  For now return a path-only stub
    // sufficient for the path= attribute.
    return LibraryTrack(
      id: m.vibeTrack.id,
      filePath: m.localFilePath!,
      fileName: p.basename(m.localFilePath!),
      title: m.vibeTrack.title,
      artist: m.vibeTrack.artist,
      album: '',
      genre: m.vibeTrack.genre,
      bpm: m.vibeTrack.bpm.toDouble(),
      key: m.vibeTrack.keySignature,
      durationSeconds: 0,
      fileSizeBytes: 0,
      fileExtension: p.extension(m.localFilePath!),
      md5Hash: '',
      bitrate: 0,
      sampleRate: 0,
    );
  }

  // ── .vdjfolder XML serialisation ──────────────────────────────────────────

  /// Produces the XML content of a `.vdjfolder` file.
  ///
  /// Skipped tracks (no exportPath) are omitted entirely.
  /// Track order is preserved; `idx` is zero-based sequential.
  String buildVdjFolderXml(List<DjExportTrack> tracks) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<VirtualFolder>');

    int idx = 0;
    for (final t in tracks) {
      final path = t.exportPath;
      if (path == null) continue; // skip unresolved tracks

      buf.write('  <song path="${_esc(path)}"');

      if (t.isLocalMatch && t.localTrack != null) {
        final lt = t.localTrack!;
        if (lt.fileSizeBytes > 0) buf.write(' size="${lt.fileSizeBytes}"');
        if (lt.durationSeconds > 0) {
          buf.write(' songlength="${lt.durationSeconds.toStringAsFixed(3)}"');
        }
        if (lt.bpm > 0) buf.write(' bpm="${lt.bpm.toStringAsFixed(2)}"');
        if (lt.key.isNotEmpty) buf.write(' key="${_esc(lt.key)}"');
        if (lt.artist.isNotEmpty) buf.write(' artist="${_esc(lt.artist)}"');
        if (lt.title.isNotEmpty) buf.write(' title="${_esc(lt.title)}"');
      } else {
        // TIDAL or minimal fallback — write cloud metadata
        if (t.cloudTrack != null) {
          final ct = t.cloudTrack!;
          if (ct.artist.isNotEmpty) buf.write(' artist="${_esc(ct.artist)}"');
          if (ct.title.isNotEmpty) buf.write(' title="${_esc(ct.title)}"');
          if (ct.bpm > 0) {
            buf.write(' bpm="${ct.bpm.toStringAsFixed(2)}"');
          }
          if (ct.keySignature.isNotEmpty) {
            buf.write(' key="${_esc(ct.keySignature)}"');
          }
        }
      }

      buf.write(' idx="$idx"');
      buf.writeln('/>');
      idx++;
    }

    buf.writeln('</VirtualFolder>');
    return buf.toString();
  }

  // ── order file ────────────────────────────────────────────────────────────

  /// Inserts [playlistName] into the VirtualDJ `order` file exactly once,
  /// preserving all existing entries.
  ///
  /// The `order` file lives at `<vdjRoot>/Folders/LocalMusic/order`.
  Future<void> updateOrderFile(String vdjRoot, String playlistName) async {
    final orderFile = File(p.join(vdjRoot, 'Folders', 'LocalMusic', 'order'));

    List<String> lines = [];
    if (orderFile.existsSync()) {
      lines = (await orderFile.readAsString())
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // Insert exactly once
    if (!lines.contains(playlistName)) {
      lines.add(playlistName);
      await orderFile.parent.create(recursive: true);
      await orderFile.writeAsString('${lines.join('\n')}\n');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<String> _writeFolderFile(
    String vdjRoot,
    String playlistName,
    String xml,
  ) async {
    final dir = Directory(p.join(vdjRoot, 'Folders', 'LocalMusic'));
    await dir.create(recursive: true);

    final safeName = _safeFilename(playlistName);
    final file = File(p.join(dir.path, '$safeName.vdjfolder'));
    await file.writeAsString(xml, flush: true);
    return file.path;
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _safeFilename(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
