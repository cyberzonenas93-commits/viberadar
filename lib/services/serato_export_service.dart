import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/dj_export_result.dart';
import '../models/library_track.dart';

/// Writes Serato-compatible `.crate` files into the Serato library.
///
/// Serato's database is managed exclusively by Serato DJ Pro — external writes
/// to master.sqlite are wiped on launch. Therefore:
/// - Local tracks → binary .crate file (Serato reads these natively)
/// - Streaming tracks → skip from .crate, generate a TIDAL search manifest
///   so the user can quickly find and add them in Serato's TIDAL browser
class SeratoExportService {
  static const _versionString = '1.0/Serato ScratchLive Crate';

  // ── Public API ───────────────────────────────────────────────────────────

  String crateFilename(String crateName, {String? parentCrateName}) {
    final safe = _safeName(crateName);
    if (parentCrateName != null && parentCrateName.isNotEmpty) {
      return '${_safeName(parentCrateName)}%%$safe.crate';
    }
    return '$safe.crate';
  }

  /// Export tracks as a Serato crate.
  ///
  /// Local tracks are written to the binary .crate file.
  /// Non-local tracks are reported with TIDAL IDs for manual lookup.
  Future<DjExportResult> exportCrate({
    required String seratoRoot,
    required String crateName,
    required List<LibraryTrack> tracks,
    String? parentCrateName,
    List<LibraryTrack>? localLibrary,
    bool useTidal = false,
  }) async {
    final resolved = <DjTrackResolution>[];
    final warnings = <String>[];

    // Build local library index.
    final Map<String, LibraryTrack> localIndex = {};
    if (localLibrary != null) {
      for (final lt in localLibrary) {
        if (lt.filePath.isNotEmpty) {
          localIndex[_matchKey(lt.title, lt.artist)] = lt;
        }
      }
    }

    for (final t in tracks) {
      // Priority 1: Has valid local file
      if (t.filePath.isNotEmpty && File(t.filePath).existsSync()) {
        resolved.add(DjTrackResolution(
          title: t.title, artist: t.artist,
          status: DjTrackStatus.local,
          localFilePath: t.filePath,
          fileSizeBytes: t.fileSizeBytes,
          durationSeconds: t.durationSeconds,
          bpm: t.bpm, key: t.key,
        ));
        continue;
      }

      // Priority 2: Match local library
      final localMatch = localIndex[_matchKey(t.title, t.artist)];
      if (localMatch != null && File(localMatch.filePath).existsSync()) {
        resolved.add(DjTrackResolution(
          title: t.title, artist: t.artist,
          status: DjTrackStatus.local,
          localFilePath: localMatch.filePath,
          fileSizeBytes: localMatch.fileSizeBytes,
          durationSeconds: localMatch.durationSeconds > 0
              ? localMatch.durationSeconds : t.durationSeconds,
          bpm: t.bpm > 0 ? t.bpm : localMatch.bpm,
          key: t.key.isNotEmpty ? t.key : localMatch.key,
        ));
        continue;
      }

      // Priority 3: Resolve TIDAL ID for manifest
      if (useTidal) {
        final tidalId = await _resolveTidalId(t.artist, t.title);
        if (tidalId != null) {
          resolved.add(DjTrackResolution(
            title: t.title, artist: t.artist,
            status: DjTrackStatus.tidal,
            tidalTrackId: tidalId,
            durationSeconds: t.durationSeconds,
            bpm: t.bpm, key: t.key,
          ));
          continue;
        }
        warnings.add('"${t.artist} – ${t.title}": not found on TIDAL');
      }

      resolved.add(DjTrackResolution(
        title: t.title, artist: t.artist,
        status: DjTrackStatus.skipped,
        skipReason: useTidal ? 'Not found on TIDAL' : 'No local file',
      ));
    }

    // Write binary .crate for local tracks
    final localPaths = resolved.where((r) => r.isLocal).map((r) => r.localFilePath!).toList();
    final subcratesDir = Directory(p.join(seratoRoot, 'Subcrates'));
    await subcratesDir.create(recursive: true);
    final filename = crateFilename(crateName, parentCrateName: parentCrateName);
    final crateFile = File(p.join(subcratesDir.path, filename));
    final bytes = buildCrateBytes(localPaths);
    await crateFile.writeAsBytes(bytes, flush: true);

    // Write TIDAL manifest for non-local tracks
    final tidalTracks = resolved.where((r) => r.isTidal).toList();
    if (tidalTracks.isNotEmpty) {
      final manifestPath = p.join(subcratesDir.path, '${_safeName(crateName)}_tidal_tracks.txt');
      final manifest = StringBuffer();
      manifest.writeln('# TIDAL tracks for Serato crate: $crateName');
      manifest.writeln('# Search these in Serato\'s TIDAL browser to add them to your crate');
      manifest.writeln('# Format: Artist - Title (TIDAL ID: xxx)');
      manifest.writeln('#');
      for (final t in tidalTracks) {
        manifest.writeln('${t.artist} - ${t.title}  (TIDAL ID: ${t.tidalTrackId})');
      }
      await File(manifestPath).writeAsString(manifest.toString());
    }

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

  // ── TIDAL resolution ────────────────────────────────────────────────────

  Future<String?> _resolveTidalId(String artist, String title) async {
    try {
      final query = Uri.encodeComponent(_cleanForSearch('$artist $title'));
      final url = Uri.parse(
        'https://api.tidal.com/v1/search/tracks?query=$query&limit=5&countryCode=US',
      );
      final client = HttpClient();
      final request = await client.getUrl(url);
      request.headers.set('x-tidal-token', 'CzET4vdadNUFQ5JU');
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) { client.close(); return null; }

      final chunks = <List<int>>[];
      await for (final chunk in response) { chunks.add(chunk); }
      client.close();
      final bodyBytes = chunks.expand((c) => c).toList();
      final body = String.fromCharCodes(bodyBytes);

      // Simple JSON parsing without dart:convert import conflicts
      final itemsMatch = RegExp(r'"items":\[(.+)\]', dotAll: true).firstMatch(body);
      if (itemsMatch == null) return null;

      // Extract first track ID
      final idMatch = RegExp(r'"id":(\d+)').firstMatch(body);
      if (idMatch == null) return null;

      return idMatch.group(1);
    } catch (_) {
      return null;
    }
  }

  // ── Binary serializer ────────────────────────────────────────────────────

  Uint8List buildCrateBytes(List<String> absolutePaths) {
    final out = BytesBuilder(copy: false);
    _writeChunk(out, 'vrsn', _encodeUtf16Be(_versionString));
    for (final path in absolutePaths) {
      final inner = BytesBuilder(copy: false);
      _writeChunk(inner, 'ptrk', _encodeUtf16Be(path));
      _writeChunk(out, 'otrk', Uint8List.fromList(inner.toBytes()));
    }
    return Uint8List.fromList(out.toBytes());
  }

  void _writeChunk(BytesBuilder out, String tag, Uint8List data) {
    assert(tag.length == 4);
    for (final c in tag.codeUnits) out.addByte(c);
    final len = data.length;
    out.addByte((len >> 24) & 0xFF);
    out.addByte((len >> 16) & 0xFF);
    out.addByte((len >> 8) & 0xFF);
    out.addByte(len & 0xFF);
    out.add(data);
  }

  Uint8List _encodeUtf16Be(String s) {
    final bytes = <int>[];
    for (final codeUnit in s.codeUnits) {
      if (codeUnit <= 0xFFFF) {
        bytes.add((codeUnit >> 8) & 0xFF);
        bytes.add(codeUnit & 0xFF);
      } else {
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();

  String _matchKey(String title, String artist) =>
      '${title.toLowerCase().trim()}::${artist.toLowerCase().trim()}';

  String _cleanForSearch(String s) {
    var clean = s;
    clean = clean.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    clean = clean.replaceAll(RegExp(r'\s*\[[^\]]*\]'), '');
    clean = clean.replaceAll(RegExp(r'\s*(?:feat\.?|ft\.?)\s+.*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s*-\s*(?:Radio Edit|Remix|Edit|Remaster(?:ed)?|Live|Acoustic|Version|Mix).*', caseSensitive: false), '');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean;
  }
}
