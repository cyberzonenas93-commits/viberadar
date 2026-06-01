// test/serato_export_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/services/serato_export_service.dart';

// ── TLV navigation helpers ────────────────────────────────────────────────────

String _readTag(Uint8List b, int off) =>
    String.fromCharCodes(b.sublist(off, off + 4));

int _readU32(Uint8List b, int off) =>
    (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

String _decodeUtf16BE(Uint8List b) {
  final chars = <int>[];
  for (var i = 0; i < b.length - 1; i += 2) {
    chars.add((b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(chars);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late SeratoExportService svc;
  setUp(() => svc = SeratoExportService());

  // ── buildCrateBytes – vrsn tag ─────────────────────────────────────────────

  group('buildCrateBytes – vrsn', () {
    test('first tag is "vrsn"', () {
      expect(_readTag(svc.buildCrateBytes([]), 0), equals('vrsn'));
    });

    test('vrsn value is "1.0/Serato ScratchLive Crate"', () {
      final b = svc.buildCrateBytes([]);
      final len = _readU32(b, 4);
      expect(_decodeUtf16BE(b.sublist(8, 8 + len)),
          equals('1.0/Serato ScratchLive Crate'));
    });

    test('vrsn value is exactly 56 bytes (28 chars × 2)', () {
      final b = svc.buildCrateBytes([]);
      expect(_readU32(b, 4), equals(56));
    });

    test('empty path list produces only vrsn block', () {
      final b = svc.buildCrateBytes([]);
      expect(b.length, equals(8 + 56)); // 4 tag + 4 len + 56 value
    });
  });

  // ── buildCrateBytes – track entries ───────────────────────────────────────

  group('buildCrateBytes – tracks', () {
    test('one path → otrk block after vrsn', () {
      final b = svc.buildCrateBytes(['/music/track.mp3']);
      final vrsnLen = _readU32(b, 4);
      expect(_readTag(b, 8 + vrsnLen), equals('otrk'));
    });

    test('ptrk nested inside otrk decodes to the supplied path', () {
      const path = '/Users/dj/Music/House/track.mp3';
      final b = svc.buildCrateBytes([path]);
      final vrsnLen = _readU32(b, 4);
      final otrkOff = 8 + vrsnLen;
      final ptrkOff = otrkOff + 8; // skip otrk tag + length
      final ptrkLen = _readU32(b, ptrkOff + 4);
      final ptrkVal = b.sublist(ptrkOff + 8, ptrkOff + 8 + ptrkLen);
      expect(_decodeUtf16BE(ptrkVal), equals(path));
    });

    test('multiple paths produce otrk blocks in order', () {
      final paths = ['/music/a.mp3', '/music/b.mp3', '/music/c.mp3'];
      final b = svc.buildCrateBytes(paths);
      final vrsnLen = _readU32(b, 4);
      final found = <String>[];
      var off = 8 + vrsnLen;
      while (off < b.length) {
        final tag = _readTag(b, off);
        final len = _readU32(b, off + 4);
        if (tag == 'otrk') {
          final ptrkLen = _readU32(b, off + 8 + 4);
          final ptrkVal = b.sublist(off + 16, off + 16 + ptrkLen);
          found.add(_decodeUtf16BE(ptrkVal));
        }
        off += 8 + len;
      }
      expect(found, orderedEquals(paths));
    });

    test('non-ASCII filenames round-trip via UTF-16BE', () {
      const path = '/music/Björk – Jóga.mp3';
      final b = svc.buildCrateBytes([path]);
      final vrsnLen = _readU32(b, 4);
      final ptrkOff = 8 + vrsnLen + 8;
      final ptrkLen = _readU32(b, ptrkOff + 4);
      final ptrkVal = b.sublist(ptrkOff + 8, ptrkOff + 8 + ptrkLen);
      expect(_decodeUtf16BE(ptrkVal), equals(path));
    });
  });

  // ── buildCrateFilename ────────────────────────────────────────────────────

  group('buildCrateFilename', () {
    test('null parent → "<name>.crate"', () {
      expect(svc.buildCrateFilename('House', null), equals('House.crate'));
    });

    test('parent provided → "<parent>%%<name>.crate"', () {
      expect(svc.buildCrateFilename('House', 'LocalMusic'),
          equals('LocalMusic%%House.crate'));
    });

    test('spaces in names are preserved', () {
      expect(svc.buildCrateFilename('Deep House', 'My Crates'),
          equals('My Crates%%Deep House.crate'));
    });
  });

  // ── export() integration ──────────────────────────────────────────────────

  group('export()', () {
    late Directory seratoRoot;

    setUp(() async {
      seratoRoot = await Directory.systemTemp.createTemp('vr_serato_');
      await Directory('${seratoRoot.path}/Subcrates').create();
    });
    tearDown(() => seratoRoot.delete(recursive: true));

    test('writes .crate file to Subcrates', () async {
      final result = await svc.export(
        playlistName: 'HouseSet',
        matches: [],
        seratoRoot: seratoRoot.path,
      );
      expect(File(result.outputPath).existsSync(), isTrue);
      expect(result.outputPath, contains('Subcrates'));
      expect(result.outputPath, endsWith('HouseSet.crate'));
    });

    test('%% separator used when parent crate provided', () async {
      final result = await svc.export(
        playlistName: 'Techno',
        matches: [],
        seratoRoot: seratoRoot.path,
        parentCrateName: 'LocalMusic',
      );
      expect(result.outputPath, contains('LocalMusic%%Techno.crate'));
    });

    test('empty match list → localMatchCount = 0', () async {
      final result = await svc.export(
        playlistName: 'Empty',
        matches: [],
        seratoRoot: seratoRoot.path,
      );
      expect(result.totalTracks, equals(0));
      expect(result.localMatchCount, equals(0));
    });
  });
}
