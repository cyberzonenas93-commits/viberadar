import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/dj_export_models.dart';
import '../models/library_track.dart';
import '../services/local_match_service.dart';

// ── Serato crate binary serialiser ───────────────────────────────────────────
//
// Format specification (verified against real .crate fixtures and multiple
// open-source Serato tools):
//
//   Tag-Length-Value structure
//   ─────────────────────────
//   [4-byte ASCII tag] [4-byte big-endian uint32 length] [<length> bytes value]
//
//   Top-level tags
//   ──────────────
//   vrsn  — version string "1.0/Serato ScratchLive Crate" (UTF-16BE, no BOM)
//   otrk  — track entry; value is a nested TLV payload
//
//   Nested tags inside otrk
//   ────────────────────────
//   ptrk  — absolute file path (UTF-16BE, no BOM)
//
// Streaming tracks (e.g. Spotify/Apple Music only) are NOT added to Serato
// crates because Serato has no standardised way to reference streaming sources
// in the .crate binary format.  They are reported as skipped in the result.

class SeratoExportService {
  // ── Public API ────────────────────────────────────────────────────────────

  /// Resolves each match against the local library and writes a binary
  /// `.crate` file to `<seratoRoot>/Subcrates/`.
  ///
  /// Tracks without a local file match are reported as
  /// [DjTrackResolution.skipped] and omitted from the crate.
  Future<DjExportResult> export({
    required String playlistName,
    required List<TrackMatch> matches,
    required String seratoRoot,

    /// Optional parent crate name for nesting (encoded as `parent%%child`).
    String? parentCrateName,
  }) async {
    final exportTracks = _resolve(matches);

    // Skip tracks with invalid or missing paths. Serato parses .crate files
    // eagerly at app-startup; a single bad path can corrupt the library view.
    final localPaths = <String>[];
    for (final t in exportTracks) {
      if (!t.isLocalMatch || t.localFilePath == null) continue;
      final path = t.localFilePath!;
      if (!_isValidExportPath(path)) {
        developer.log('Skipping Serato export for invalid path: $path',
            name: 'SeratoExportService');
        continue;
      }
      localPaths.add(path);
    }

    final crateBytes = buildCrateBytes(localPaths);
    final crateFilename = buildCrateFilename(playlistName, parentCrateName);
    final outputPath =
        await _writeCrateFile(seratoRoot, crateFilename, crateBytes);

    return DjExportResult(
      target: DjTarget.serato,
      playlistName: playlistName,
      totalTracks: exportTracks.length,
      localMatchCount: exportTracks.where((t) => t.isLocalMatch).length,
      tidalCount: 0, // Serato does not support TIDAL entries
      skippedCount: exportTracks.where((t) => t.isSkipped).length,
      outputPath: outputPath,
      djRoot: seratoRoot,
      tracks: exportTracks,
      warning:
          'Restart Serato or click Refresh in the crates panel to see the'
          ' new crate.',
    );
  }

  // ── Resolution ────────────────────────────────────────────────────────────

  List<DjExportTrack> _resolve(List<TrackMatch> matches) {
    return matches.map((m) {
      if (m.isFound || m.isFuzzy) {
        return DjExportTrack(
          cloudTrack: m.vibeTrack,
          localTrack: _libTrackFor(m),
          resolution: DjTrackResolution.localMatch,
        );
      }
      return DjExportTrack(
        cloudTrack: m.vibeTrack,
        resolution: DjTrackResolution.skipped,
        skipReason: 'Track not found in local library — Serato requires local'
            ' files',
      );
    }).toList();
  }

  LibraryTrack? _libTrackFor(TrackMatch m) {
    if (m.localFilePath == null) return null;
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

  // ── Binary serialiser ─────────────────────────────────────────────────────

  /// Builds the raw bytes of a `.crate` file for the given [filePaths].
  ///
  /// Each path must be an absolute POSIX path (e.g. `/Users/…/track.mp3`).
  /// Paths are stored as UTF-16BE-encoded strings (no BOM).
  Uint8List buildCrateBytes(List<String> filePaths) {
    final parts = <Uint8List>[];

    // vrsn ────────────────────────────────────────────────────────────────────
    const versionString = '1.0/Serato ScratchLive Crate';
    parts.add(_tlv('vrsn', _utf16BE(versionString)));

    // otrk per track ──────────────────────────────────────────────────────────
    for (final path in filePaths) {
      final ptrkValue = _utf16BE(path);
      final ptrkTlv = _tlv('ptrk', ptrkValue);
      parts.add(_tlv('otrk', ptrkTlv));
    }

    // Concatenate all parts
    final totalLength = parts.fold<int>(0, (sum, p) => sum + p.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return result;
  }

  // ── Crate filename ────────────────────────────────────────────────────────

  /// Returns the `.crate` filename for a given [crateName] with optional
  /// [parentCrateName].
  ///
  /// Serato encodes hierarchy using `%%` as the separator:
  ///   parentCrateName=null          → `House.crate`
  ///   parentCrateName='LocalMusic'  → `LocalMusic%%House.crate`
  ///
  /// Arbitrary nesting depth is supported by passing pre-joined parent paths.
  String buildCrateFilename(String crateName, String? parentCrateName) {
    final safe = _safeCrateName(crateName);
    if (parentCrateName == null || parentCrateName.isEmpty) return '$safe.crate';
    final safeParent = parentCrateName
        .split('%%')
        .map(_safeCrateName)
        .join('%%');
    return '$safeParent%%$safe.crate';
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<String> _writeCrateFile(
    String seratoRoot,
    String filename,
    Uint8List bytes,
  ) async {
    final subcrates = Directory(p.join(seratoRoot, 'Subcrates'));
    await subcrates.create(recursive: true);

    final file = File(p.join(subcrates.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Encodes [text] as UTF-16BE (big-endian, no BOM).
  Uint8List _utf16BE(String text) {
    // Each code unit → 2 bytes: high byte first, then low byte.
    final bytes = Uint8List(text.length * 2);
    for (var i = 0; i < text.length; i++) {
      final cu = text.codeUnitAt(i);
      bytes[i * 2] = (cu >> 8) & 0xFF;
      bytes[i * 2 + 1] = cu & 0xFF;
    }
    return bytes;
  }

  /// Builds a TLV (tag-length-value) block.
  ///
  ///   [4 ASCII bytes = tag] [4 bytes BE uint32 = value.length] [value bytes]
  Uint8List _tlv(String tag, Uint8List value) {
    assert(tag.length == 4, 'TLV tag must be exactly 4 ASCII chars');
    final result = Uint8List(4 + 4 + value.length);
    // Tag (4 ASCII bytes)
    for (var i = 0; i < 4; i++) {
      result[i] = tag.codeUnitAt(i);
    }
    // Length (4-byte big-endian uint32)
    final len = value.length;
    result[4] = (len >> 24) & 0xFF;
    result[5] = (len >> 16) & 0xFF;
    result[6] = (len >> 8) & 0xFF;
    result[7] = len & 0xFF;
    // Value
    result.setRange(8, 8 + value.length, value);
    return result;
  }

  /// Replaces characters that are illegal in Serato crate filenames.
  String _safeCrateName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|%]'), '_');

  /// Validates a track path before writing it into a .crate file.
  ///
  /// Requirements:
  ///   - non-empty
  ///   - absolute POSIX path (Serato stores absolute paths)
  ///   - no unresolved `..` components (defends against path traversal when
  ///     the playlist is sourced from an untrusted import)
  ///
  /// We do NOT require the file to exist at export time — Serato tolerates
  /// references to offline drives and will relink when they reappear.
  bool _isValidExportPath(String path) {
    if (path.isEmpty) return false;
    if (!p.isAbsolute(path)) return false;
    return !p.normalize(path).split(p.separator).contains('..');
  }
}
