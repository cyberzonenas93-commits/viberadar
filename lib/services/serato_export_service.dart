import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/dj_export_result.dart';
import '../models/library_track.dart';

/// Writes Serato-compatible `.crate` files into the Serato library.
///
/// Output location:
///   <SERATO_ROOT>/Subcrates/<CrateName>.crate
///   or for nested: <SERATO_ROOT>/Subcrates/<Parent>%%<Child>.crate
///
/// ## Binary format (proven community-documented TLV structure)
///
/// Serato `.crate` files use a 4-byte-tag + 4-byte-BE-length + data TLV
/// structure where all strings are encoded as UTF-16 BE (no BOM).
///
/// Layout:
///   [vrsn][len=56]["1.0/Serato ScratchLive Crate" in UTF-16 BE]
///   For each track:
///     [otrk][len]
///       [ptrk][len][absolute_file_path in UTF-16 BE]
///
/// References:
///   - https://github.com/Holzhaus/serato-tags (Python reverse engineering)
///   - https://github.com/quaninte/serato-crates (Node.js implementation)
///   Both confirm this exact chunk structure with fixture validation.
///
/// ## Streaming tracks
/// Serato DJ Pro does not have a documented path format for streaming-only
/// tracks in `.crate` files. Streaming entries are intentionally NOT written
/// to protect crate integrity. Skipped tracks are reported in the result.
class SeratoExportService {
  /// The version string embedded in every valid Serato crate.
  static const _versionString = '1.0/Serato ScratchLive Crate';

  // ── Public API ───────────────────────────────────────────────────────────

  /// Builds the crate filename for a given [crateName].
  ///
  /// Serato encodes folder hierarchy by joining path segments with `%%`.
  /// Examples:
  ///   crateName='House', parentCrateName=null   → 'House.crate'
  ///   crateName='Afro',  parentCrateName='House' → 'House%%Afro.crate'
  String crateFilename(String crateName, {String? parentCrateName}) {
    final safe = _safeName(crateName);
    if (parentCrateName != null && parentCrateName.isNotEmpty) {
      return '${_safeName(parentCrateName)}%%$safe.crate';
    }
    return '$safe.crate';
  }

  /// Exports [tracks] as a Serato `.crate` file.
  ///
  /// Only tracks with a valid local file path are written.
  /// Streaming-only tracks are skipped and reported in the result.
  Future<DjExportResult> exportCrate({
    required String seratoRoot,
    required String crateName,
    required List<LibraryTrack> tracks,
    String? parentCrateName,
  }) async {
    // Resolve tracks — emit skipped for any missing file.
    final resolved = <DjTrackResolution>[];
    final warnings = <String>[];

    for (final t in tracks) {
      if (t.filePath.isEmpty || !File(t.filePath).existsSync()) {
        resolved.add(DjTrackResolution(
          title: t.title,
          artist: t.artist,
          status: DjTrackStatus.skipped,
          skipReason: 'Local file not found: ${t.filePath}',
        ));
        warnings.add('Skipped "${t.artist} – ${t.title}": file not on disk');
        continue;
      }
      resolved.add(DjTrackResolution(
        title: t.title,
        artist: t.artist,
        status: DjTrackStatus.local,
        localFilePath: t.filePath,
        fileSizeBytes: t.fileSizeBytes,
        durationSeconds: t.durationSeconds,
        bpm: t.bpm,
        key: t.key,
      ));
    }

    final localPaths = resolved
        .where((r) => r.isLocal)
        .map((r) => r.localFilePath!)
        .toList();

    // Ensure Subcrates directory exists.
    final subcratesDir = Directory(p.join(seratoRoot, 'Subcrates'));
    await subcratesDir.create(recursive: true);

    final filename = crateFilename(crateName, parentCrateName: parentCrateName);
    final crateFile = File(p.join(subcratesDir.path, filename));
    final bytes = buildCrateBytes(localPaths);
    await crateFile.writeAsBytes(bytes, flush: true);

    return DjExportResult(
      target: DjExportTarget.serato,
      crateName: crateName,
      rootPath: seratoRoot,
      outputPath: crateFile.path,
      tracks: resolved,
      exportedAt: DateTime.now(),
      warnings: warnings,
    );
  }

  // ── Binary serializer ────────────────────────────────────────────────────

  /// Builds the raw bytes for a Serato `.crate` file.
  ///
  /// Validated against the community-documented TLV format:
  /// • Tag   : 4 ASCII bytes
  /// • Length: 4-byte big-endian unsigned int (byte count of data field)
  /// • Data  : raw bytes (strings encoded as UTF-16 BE, no BOM)
  Uint8List buildCrateBytes(List<String> absolutePaths) {
    final out = BytesBuilder(copy: false);

    // Write version header.
    _writeChunk(out, 'vrsn', _encodeUtf16Be(_versionString));

    // Write one otrk container per track.
    for (final path in absolutePaths) {
      final inner = BytesBuilder(copy: false);
      _writeChunk(inner, 'ptrk', _encodeUtf16Be(path));
      _writeChunk(out, 'otrk', inner.toBytes() as Uint8List);
    }

    return out.toBytes() as Uint8List;
  }

  // ── TLV helpers ──────────────────────────────────────────────────────────

  /// Writes a single TLV chunk: [tag(4)][length(4 BE)][data].
  void _writeChunk(BytesBuilder out, String tag, Uint8List data) {
    // Tag must be exactly 4 ASCII characters.
    assert(tag.length == 4, 'TLV tag must be 4 chars, got: $tag');
    for (final c in tag.codeUnits) {
      out.addByte(c);
    }
    final len = data.length;
    out.addByte((len >> 24) & 0xFF);
    out.addByte((len >> 16) & 0xFF);
    out.addByte((len >> 8) & 0xFF);
    out.addByte(len & 0xFF);
    out.add(data);
  }

  /// Encodes [s] as UTF-16 big-endian (no BOM) — the encoding Serato uses
  /// for all string values inside TLV chunks.
  Uint8List _encodeUtf16Be(String s) {
    final bytes = <int>[];
    for (final codeUnit in s.codeUnits) {
      // Characters beyond the BMP (> 0xFFFF) are unlikely in file paths,
      // but handle them as surrogate pairs anyway.
      if (codeUnit <= 0xFFFF) {
        bytes.add((codeUnit >> 8) & 0xFF);
        bytes.add(codeUnit & 0xFF);
      } else {
        // Encode as UTF-16 surrogate pair.
        final scalar = codeUnit - 0x10000;
        final high = 0xD800 + (scalar >> 10);
        final low = 0xDC00 + (scalar & 0x3FF);
        bytes.add((high >> 8) & 0xFF);
        bytes.add(high & 0xFF);
        bytes.add((low >> 8) & 0xFF);
        bytes.add(low & 0xFF);
      }
    }
    return Uint8List.fromList(bytes);
  }

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
}
