// test/virtual_dj_export_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/dj_export_models.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/virtual_dj_export_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

LibraryTrack _lt(String path) => LibraryTrack(
      id: 'id_${path.hashCode}',
      filePath: path,
      fileName: path.split('/').last,
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      genre: 'House',
      bpm: 128.0,
      key: '8A',
      durationSeconds: 240,
      fileSizeBytes: 10000000,
      fileExtension: '.mp3',
      md5Hash: '',
      bitrate: 320,
      sampleRate: 44100,
    );

DjExportTrack _local(String path) => DjExportTrack(
      localTrack: _lt(path),
      resolution: DjTrackResolution.localMatch,
    );

DjExportTrack _tidal(String id) => DjExportTrack(
      resolution: DjTrackResolution.tidalFallback,
      tidalId: id,
    );

DjExportTrack _skipped() =>
    const DjExportTrack(resolution: DjTrackResolution.skipped);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late VirtualDjExportService svc;
  setUp(() => svc = VirtualDjExportService());

  // ── buildVdjFolderXml ───────────────────────────────────────────────────────

  group('buildVdjFolderXml', () {
    test('produces XML declaration and VirtualFolder root', () {
      final xml = svc.buildVdjFolderXml([_local('/music/a.mp3')]);
      expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<VirtualFolder>'));
      expect(xml, contains('</VirtualFolder>'));
    });

    test('local track path appears in path attribute', () {
      final xml = svc.buildVdjFolderXml([_local('/Users/dj/Music/track.mp3')]);
      expect(xml, contains('path="/Users/dj/Music/track.mp3"'));
    });

    test('sequential zero-based idx on each song', () {
      final xml = svc.buildVdjFolderXml([
        _local('/a.mp3'), _local('/b.mp3'), _local('/c.mp3'),
      ]);
      expect(xml, contains('idx="0"'));
      expect(xml, contains('idx="1"'));
      expect(xml, contains('idx="2"'));
      expect(xml, isNot(contains('idx="3"')));
    });

    test('TIDAL track uses netsearch:// scheme', () {
      final xml = svc.buildVdjFolderXml([_tidal('12345678')]);
      expect(xml, contains('path="netsearch://td12345678"'));
    });

    test('skipped tracks are omitted; idx remains sequential', () {
      final xml = svc.buildVdjFolderXml([
        _local('/a.mp3'), _skipped(), _local('/c.mp3'),
      ]);
      expect(RegExp(r'<song ').allMatches(xml).length, equals(2));
      expect(xml, contains('idx="0"'));
      expect(xml, contains('idx="1"'));
    });

    test('empty list produces empty VirtualFolder', () {
      final xml = svc.buildVdjFolderXml([]);
      expect(xml, contains('<VirtualFolder>'));
      expect(xml, isNot(contains('<song')));
    });

    test('ampersand in path is XML-escaped', () {
      final xml = svc.buildVdjFolderXml([_local('/music/Rock & Roll/t.mp3')]);
      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('& Roll')));
    });

    test('double-quote in path is XML-escaped', () {
      final xml = svc.buildVdjFolderXml([_local('/music/Say "Hi"/t.mp3')]);
      expect(xml, contains('&quot;'));
    });
  });

  // ── updateOrderFile ─────────────────────────────────────────────────────────

  group('updateOrderFile', () {
    late Directory vdjRoot;
    setUp(() async {
      vdjRoot = await Directory.systemTemp.createTemp('vr_vdj_order_');
      await Directory('${vdjRoot.path}/Folders/LocalMusic')
          .create(recursive: true);
    });
    tearDown(() => vdjRoot.delete(recursive: true));

    test('creates order file when absent', () async {
      await svc.updateOrderFile(vdjRoot.path, 'HouseSet');
      final f = File('${vdjRoot.path}/Folders/LocalMusic/order');
      expect(f.existsSync(), isTrue);
      expect(f.readAsStringSync(), contains('HouseSet'));
    });

    test('appends to existing order file', () async {
      final f = File('${vdjRoot.path}/Folders/LocalMusic/order');
      f.writeAsStringSync('OldPlaylist\n');
      await svc.updateOrderFile(vdjRoot.path, 'NewPlaylist');
      expect(f.readAsStringSync(), contains('OldPlaylist'));
      expect(f.readAsStringSync(), contains('NewPlaylist'));
    });

    test('does not duplicate an existing entry', () async {
      final f = File('${vdjRoot.path}/Folders/LocalMusic/order');
      f.writeAsStringSync('HouseSet\n');
      await svc.updateOrderFile(vdjRoot.path, 'HouseSet');
      await svc.updateOrderFile(vdjRoot.path, 'HouseSet');
      final count = 'HouseSet'.allMatches(f.readAsStringSync()).length;
      expect(count, equals(1));
    });
  });

  // ── export() integration ────────────────────────────────────────────────────

  group('export()', () {
    late Directory vdjRoot;
    late Directory musicDir;

    setUp(() async {
      vdjRoot = await Directory.systemTemp.createTemp('vr_vdj_root_');
      await Directory('${vdjRoot.path}/Folders/LocalMusic')
          .create(recursive: true);
      musicDir = await Directory.systemTemp.createTemp('vr_music_');
    });
    tearDown(() async {
      await vdjRoot.delete(recursive: true);
      await musicDir.delete(recursive: true);
    });

    test('writes .vdjfolder file', () async {
      await File('${musicDir.path}/track.mp3').create();
      final result = await svc.export(
        playlistName: 'TestSet',
        matches: [],   // empty → zero tracks
        vdjRoot: vdjRoot.path,
      );
      expect(File(result.outputPath).existsSync(), isTrue);
      expect(result.outputPath, endsWith('TestSet.vdjfolder'));
    });

    test('summary counts are correct', () async {
      // export() resolves TrackMatch internally; with no matches all counts = 0
      final result = await svc.export(
        playlistName: 'Empty',
        matches: [],
        vdjRoot: vdjRoot.path,
      );
      expect(result.totalTracks, equals(0));
      expect(result.localMatchCount, equals(0));
      expect(result.tidalCount, equals(0));
      expect(result.skippedCount, equals(0));
    });
  });
}
