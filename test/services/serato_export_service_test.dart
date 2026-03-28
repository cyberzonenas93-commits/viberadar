import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/dj_export_result.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/serato_export_service.dart';

// ── Fixture decoder (mirrors the encoder for validation) ────────────────────

/// Decodes TLV chunks from a Serato crate byte array.
/// Returns a list of {tag, data} maps.
List<Map<String, dynamic>> _decodeTlv(Uint8List bytes) {
  final chunks = <Map<String, dynamic>>[];
  int offset = 0;
  while (offset + 8 <= bytes.length) {
    final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final len = (bytes[offset + 4] << 24) |
        (bytes[offset + 5] << 16) |
        (bytes[offset + 6] << 8) |
        bytes[offset + 7];
    offset += 8;
    final data = bytes.sublist(offset, offset + len);
    offset += len;
    chunks.add({'tag': tag, 'data': data});
  }
  return chunks;
}

/// Decodes UTF-16 BE bytes back to a Dart string.
String _decodeUtf16Be(Uint8List bytes) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

LibraryTrack _track({
  String id = 't1',
  String title = 'Test',
  String artist = 'Artist',
  String filePath = '/music/test.mp3',
}) =>
    LibraryTrack(
      id: id,
      filePath: filePath,
      fileName: p.basename(filePath),
      title: title,
      artist: artist,
      album: '',
      genre: '',
      bpm: 128.0,
      key: '8A',
      durationSeconds: 200.0,
      fileSizeBytes: 1000000,
      fileExtension: '.mp3',
      md5Hash: '',
      bitrate: 320,
      sampleRate: 44100,
    );

void main() {
  late SeratoExportService svc;

  setUp(() => svc = SeratoExportService());

  // ── Crate filename generation ─────────────────────────────────────────────

  group('crateFilename', () {
    test('top-level crate has no %% prefix', () {
      expect(svc.crateFilename('House'), 'House.crate');
    });

    test('nested crate uses %% separator', () {
      expect(
        svc.crateFilename('Afro', parentCrateName: 'House'),
        'House%%Afro.crate',
      );
    });

    test('deeply nested crate: parent already contains %%', () {
      // A crate named "Vocals%%Clean" inside "Hip-Hop"
      expect(
        svc.crateFilename('Vocals%%Clean', parentCrateName: 'Hip-Hop'),
        'Hip-Hop%%Vocals%%Clean.crate',
      );
    });

    test('empty parent crate name produces top-level filename', () {
      expect(svc.crateFilename('Jazz', parentCrateName: ''), 'Jazz.crate');
    });

    test('sanitises illegal characters in crate name', () {
      final name = svc.crateFilename('My/Crate:Test');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, endsWith('.crate'));
    });
  });

  // ── Binary serializer — vrsn header ──────────────────────────────────────

  group('buildCrateBytes — vrsn header', () {
    test('first chunk tag is vrsn', () {
      final bytes = svc.buildCrateBytes([]);
      final chunks = _decodeTlv(bytes);
      expect(chunks, isNotEmpty);
      expect(chunks.first['tag'], 'vrsn');
    });

    test('vrsn value is "1.0/Serato ScratchLive Crate" in UTF-16 BE', () {
      final bytes = svc.buildCrateBytes([]);
      final chunks = _decodeTlv(bytes);
      final vrsnData = chunks.first['data'] as Uint8List;
      expect(_decodeUtf16Be(vrsnData), '1.0/Serato ScratchLive Crate');
    });

    test('vrsn data length is exactly 56 bytes (28 chars × 2)', () {
      final bytes = svc.buildCrateBytes([]);
      final chunks = _decodeTlv(bytes);
      expect((chunks.first['data'] as Uint8List).length, 56);
    });
  });

  // ── Binary serializer — track chunks ─────────────────────────────────────

  group('buildCrateBytes — track chunks', () {
    test('empty path list produces no otrk chunks', () {
      final bytes = svc.buildCrateBytes([]);
      final chunks = _decodeTlv(bytes);
      expect(chunks.where((c) => c['tag'] == 'otrk'), isEmpty);
    });

    test('single path produces one otrk chunk', () {
      final bytes = svc.buildCrateBytes(['/music/track.mp3']);
      final chunks = _decodeTlv(bytes);
      expect(chunks.where((c) => c['tag'] == 'otrk').length, 1);
    });

    test('three paths produce three otrk chunks', () {
      final bytes = svc.buildCrateBytes([
        '/a.mp3',
        '/b.mp3',
        '/c.mp3',
      ]);
      final chunks = _decodeTlv(bytes);
      expect(chunks.where((c) => c['tag'] == 'otrk').length, 3);
    });

    test('otrk contains a nested ptrk chunk with correct path', () {
      const path = '/Users/test/Music/track.mp3';
      final bytes = svc.buildCrateBytes([path]);
      final chunks = _decodeTlv(bytes);
      final otrkData = chunks
          .firstWhere((c) => c['tag'] == 'otrk')['data'] as Uint8List;
      final innerChunks = _decodeTlv(otrkData);
      expect(innerChunks.first['tag'], 'ptrk');
      final pathDecoded =
          _decodeUtf16Be(innerChunks.first['data'] as Uint8List);
      expect(pathDecoded, path);
    });

    test('ptrk data length is path.length × 2 (UTF-16 BE, no BOM)', () {
      const path = '/music/hello.mp3'; // 16 chars
      final bytes = svc.buildCrateBytes([path]);
      final chunks = _decodeTlv(bytes);
      final otrkData =
          chunks.firstWhere((c) => c['tag'] == 'otrk')['data'] as Uint8List;
      final inner = _decodeTlv(otrkData);
      expect((inner.first['data'] as Uint8List).length, path.length * 2);
    });
  });

  // ── Fixture-based binary validation ──────────────────────────────────────
  //
  // These fixtures are derived from the well-documented community format
  // (serato-tags, serato-crates) and verified byte-by-byte.

  group('fixture validation', () {
    /// Expected bytes for an empty crate (vrsn only, no tracks).
    /// vrsn tag: 76 72 73 6E
    /// vrsn len: 00 00 00 38  (= 56)
    /// "1.0/Serato ScratchLive Crate" in UTF-16 BE: 28 chars → 56 bytes
    test('empty crate matches expected fixture bytes', () {
      final bytes = svc.buildCrateBytes([]);

      // First 4 bytes: 'vrsn' ASCII
      expect(bytes[0], 0x76); // 'v'
      expect(bytes[1], 0x72); // 'r'
      expect(bytes[2], 0x73); // 's'
      expect(bytes[3], 0x6E); // 'n'

      // Next 4 bytes: length = 56 = 0x00000038
      expect(bytes[4], 0x00);
      expect(bytes[5], 0x00);
      expect(bytes[6], 0x00);
      expect(bytes[7], 0x38);

      // First character of version string: '1' = 0x0031 in UTF-16 BE
      expect(bytes[8], 0x00);
      expect(bytes[9], 0x31);

      // Total length = 8 (tag+len) + 56 (data) = 64
      expect(bytes.length, 64);
    });

    /// Expected bytes for a single-track crate.
    /// Path: "/t" (2 chars) → 4 bytes UTF-16 BE
    /// ptrk inner data: 4 bytes
    /// ptrk chunk total: 4 (tag) + 4 (len) + 4 (data) = 12 bytes
    /// otrk chunk total: 4 (tag) + 4 (len) + 12 (inner) = 20 bytes
    test('single short-path crate matches expected structure', () {
      final bytes = svc.buildCrateBytes(['/t']);

      // After vrsn (64 bytes), expect otrk tag
      expect(bytes[64], 0x6F); // 'o'
      expect(bytes[65], 0x74); // 't'
      expect(bytes[66], 0x72); // 'r'
      expect(bytes[67], 0x6B); // 'k'

      // otrk length = 12 (ptrk 4+4+4)
      expect(bytes[68], 0x00);
      expect(bytes[69], 0x00);
      expect(bytes[70], 0x00);
      expect(bytes[71], 12);

      // ptrk tag inside otrk
      expect(bytes[72], 0x70); // 'p'
      expect(bytes[73], 0x74); // 't'
      expect(bytes[74], 0x72); // 'r'
      expect(bytes[75], 0x6B); // 'k'

      // ptrk length = 4 ('/t' = 2 chars × 2 bytes)
      expect(bytes[76], 0x00);
      expect(bytes[77], 0x00);
      expect(bytes[78], 0x00);
      expect(bytes[79], 4);

      // '/' in UTF-16 BE = 0x002F
      expect(bytes[80], 0x00);
      expect(bytes[81], 0x2F);
      // 't' in UTF-16 BE = 0x0074
      expect(bytes[82], 0x00);
      expect(bytes[83], 0x74);
    });
  });

  // ── exportCrate integration ───────────────────────────────────────────────

  group('exportCrate', () {
    late Directory tmpSeratoRoot;

    setUp(() {
      tmpSeratoRoot =
          Directory.systemTemp.createTempSync('serato_export_test_');
    });

    tearDown(() {
      if (tmpSeratoRoot.existsSync()) {
        tmpSeratoRoot.deleteSync(recursive: true);
      }
    });

    test('skips tracks whose files do not exist on disk', () async {
      final track = _track(filePath: '/does/not/exist/track.mp3');
      final result = await svc.exportCrate(
        seratoRoot: tmpSeratoRoot.path,
        crateName: 'Missing',
        tracks: [track],
      );
      expect(result.skippedCount, 1);
      expect(result.warnings, isNotEmpty);
    });

    test('exports valid local tracks and writes .crate file', () async {
      // Create a temporary music file to simulate a real local track.
      final musicFile =
          File(p.join(Directory.systemTemp.path, 'serato_test_track.mp3'));
      musicFile.writeAsBytesSync([0xFF, 0xFB, 0x90]); // minimal MP3 header

      final track = _track(filePath: musicFile.path);
      final result = await svc.exportCrate(
        seratoRoot: tmpSeratoRoot.path,
        crateName: 'My House',
        tracks: [track],
      );

      expect(result.localCount, 1);
      expect(result.skippedCount, 0);
      expect(File(result.outputPath).existsSync(), isTrue);
      expect(result.outputPath, endsWith('.crate'));

      // Verify the written file is valid binary
      final written = File(result.outputPath).readAsBytesSync();
      final chunks = _decodeTlv(Uint8List.fromList(written));
      expect(chunks.first['tag'], 'vrsn');
      expect(chunks.where((c) => c['tag'] == 'otrk').length, 1);

      musicFile.deleteSync();
    });

    test('nested crate filename uses %% separator', () async {
      final musicFile =
          File(p.join(Directory.systemTemp.path, 'serato_nested_track.mp3'));
      musicFile.writeAsBytesSync([]);
      final track = _track(filePath: musicFile.path);

      final result = await svc.exportCrate(
        seratoRoot: tmpSeratoRoot.path,
        crateName: 'Afro',
        tracks: [track],
        parentCrateName: 'House',
      );

      expect(p.basename(result.outputPath), 'House%%Afro.crate');
      musicFile.deleteSync();
    });

    test('result target is DjExportTarget.serato', () async {
      final musicFile =
          File(p.join(Directory.systemTemp.path, 'serato_target_track.mp3'));
      musicFile.writeAsBytesSync([]);
      final track = _track(filePath: musicFile.path);

      final result = await svc.exportCrate(
        seratoRoot: tmpSeratoRoot.path,
        crateName: 'TargetTest',
        tracks: [track],
      );

      expect(result.target, DjExportTarget.serato);
      musicFile.deleteSync();
    });

    test('streaming-only tracks are not written (skipped)', () async {
      // Simulate a track with an empty filePath (streaming-only)
      final streamTrack = _track(filePath: '');
      final result = await svc.exportCrate(
        seratoRoot: tmpSeratoRoot.path,
        crateName: 'StreamingTest',
        tracks: [streamTrack],
      );
      expect(result.skippedCount, 1);
      expect(result.localCount, 0);
    });
  });

  // ── DjExportResult summary ────────────────────────────────────────────────

  group('DjExportResult summary', () {
    test('summary string lists local count', () {
      final r = DjExportResult(
        target: DjExportTarget.serato,
        crateName: 'Test',
        rootPath: '/serato',
        outputPath: '/serato/Subcrates/Test.crate',
        tracks: const [
          DjTrackResolution(
              title: 'T1',
              artist: 'A',
              status: DjTrackStatus.local,
              localFilePath: '/a.mp3'),
        ],
        exportedAt: DateTime(2026, 1, 1),
      );
      expect(r.summary, contains('1 local'));
    });

    test('summary string lists skipped count when tracks are skipped', () {
      final r = DjExportResult(
        target: DjExportTarget.serato,
        crateName: 'Test',
        rootPath: '/serato',
        outputPath: '/serato/Subcrates/Test.crate',
        tracks: const [
          DjTrackResolution(
              title: 'T1',
              artist: 'A',
              status: DjTrackStatus.skipped,
              skipReason: 'not found'),
        ],
        exportedAt: DateTime(2026, 1, 1),
      );
      expect(r.summary, contains('1 skipped'));
    });
  });
}
