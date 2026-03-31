import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/dj_export_result.dart';
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/virtual_dj_export_service.dart';

LibraryTrack _track({
  String id = 't1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  String filePath = '/music/test.mp3',
  double bpm = 128.0,
  String key = '8B',
  double durationSeconds = 210.0,
  int fileSizeBytes = 12345678,
}) =>
    LibraryTrack(
      id: id,
      filePath: filePath,
      fileName: p.basename(filePath),
      title: title,
      artist: artist,
      album: '',
      genre: '',
      bpm: bpm,
      key: key,
      durationSeconds: durationSeconds,
      fileSizeBytes: fileSizeBytes,
      fileExtension: p.extension(filePath),
      md5Hash: '',
      bitrate: 320,
      sampleRate: 44100,
    );

void main() {
  late VirtualDjExportService svc;

  setUp(() => svc = VirtualDjExportService());

  // ── XML builder ───────────────────────────────────────────────────────────

  group('buildVdjFolder', () {
    test('produces valid XML root element', () {
      final xml = svc.buildVdjFolder('My Crate', [], null);
      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<VirtualFolder'));
      expect(xml, contains('</VirtualFolder>'));
    });

    test('empty track list produces no Song elements', () {
      final xml = svc.buildVdjFolder('Empty', [], null);
      expect(xml, isNot(contains('<song')));
    });

    test('single local track produces one Song element with correct attrs', () {
      final resolved = [
        DjTrackResolution(
          title: 'Test Track',
          artist: 'Test Artist',
          status: DjTrackStatus.local,
          localFilePath: '/music/test.mp3',
          fileSizeBytes: 12345678,
          durationSeconds: 210.0,
          bpm: 128.0,
          key: '8B',
        ),
      ];
      final xml = svc.buildVdjFolder('Crate', resolved, null);
      expect(xml, contains('<song '));
      expect(xml, contains('path="/music/test.mp3"'));
      expect(xml, contains('songlength="210.0"'));
      expect(xml, contains('bpm="128.000"'));
      expect(xml, contains('key="8B"'));
      expect(xml, contains('artist="Test Artist"'));
      expect(xml, contains('title="Test Track"'));
      expect(xml, contains('idx="0"'));
    });

    test('multiple tracks are zero-indexed correctly', () {
      final resolved = List.generate(
        3,
        (i) => DjTrackResolution(
          title: 'Track $i',
          artist: 'Artist',
          status: DjTrackStatus.local,
          localFilePath: '/music/track$i.mp3',
        ),
      );
      final xml = svc.buildVdjFolder('Multi', resolved, null);
      expect(xml, contains('idx="0"'));
      expect(xml, contains('idx="1"'));
      expect(xml, contains('idx="2"'));
    });

    test('XML-escapes special characters in title and artist', () {
      final resolved = [
        DjTrackResolution(
          title: 'Rock & Roll <Remix>',
          artist: 'Artist "Name"',
          status: DjTrackStatus.local,
          localFilePath: '/music/rock.mp3',
        ),
      ];
      final xml = svc.buildVdjFolder('Crate', resolved, null);
      expect(xml, contains('Rock &amp; Roll &lt;Remix&gt;'));
      expect(xml, contains('Artist &quot;Name&quot;'));
    });

    test('XML-escapes ampersand in file path', () {
      final resolved = [
        DjTrackResolution(
          title: 'T',
          artist: 'A',
          status: DjTrackStatus.local,
          localFilePath: '/music/track & remix.mp3',
        ),
      ];
      final xml = svc.buildVdjFolder('Crate', resolved, null);
      expect(xml, contains('/music/track &amp; remix.mp3'));
    });

    test('skipped track (empty path) is not included', () {
      final resolved = [
        const DjTrackResolution(
          title: 'Missing',
          artist: 'Artist',
          status: DjTrackStatus.skipped,
          skipReason: 'not found',
        ),
        DjTrackResolution(
          title: 'Present',
          artist: 'Artist',
          status: DjTrackStatus.local,
          localFilePath: '/music/present.mp3',
        ),
      ];
      final xml = svc.buildVdjFolder('Crate', resolved, null);
      // Skipped track has empty exportPath so no Song for it
      final songMatches = RegExp(r'<song ').allMatches(xml);
      expect(songMatches.length, 1);
      expect(xml, contains('/music/present.mp3'));
    });
  });

  // ── Order file management ────────────────────────────────────────────────

  group('exportCrate order file', () {
    late Directory tmpVdjRoot;

    setUp(() {
      tmpVdjRoot = Directory.systemTemp.createTempSync('vdj_order_test_');
    });

    tearDown(() {
      if (tmpVdjRoot.existsSync()) tmpVdjRoot.deleteSync(recursive: true);
    });

    test('creates order file with playlist name when it does not exist',
        () async {
      // Create a fake music file so the export does not skip it
      final musicFile = File('/tmp/vdj_test_track.mp3');
      if (!musicFile.existsSync()) {
        musicFile.writeAsBytesSync([]);
      }
      final track = _track(filePath: musicFile.path);

      await svc.exportCrate(
        vdjRoot: tmpVdjRoot.path,
        playlistName: 'My Playlist',
        tracks: [track],
      );

      final orderFile =
          File(p.join(tmpVdjRoot.path, 'Folders/LocalMusic/order'));
      expect(orderFile.existsSync(), isTrue);
      expect(orderFile.readAsStringSync(), contains('My Playlist'));
    });

    test('does not duplicate entry in order file on repeated export',
        () async {
      final musicFile = File('/tmp/vdj_test_track2.mp3');
      if (!musicFile.existsSync()) {
        musicFile.writeAsBytesSync([]);
      }
      final track = _track(filePath: musicFile.path);

      // Export twice
      await svc.exportCrate(
          vdjRoot: tmpVdjRoot.path,
          playlistName: 'Dedup Test',
          tracks: [track]);
      await svc.exportCrate(
          vdjRoot: tmpVdjRoot.path,
          playlistName: 'Dedup Test',
          tracks: [track]);

      final orderFile =
          File(p.join(tmpVdjRoot.path, 'Folders/LocalMusic/order'));
      final lines = orderFile
          .readAsStringSync()
          .split('\n')
          .where((l) => l.trim() == 'Dedup Test')
          .toList();
      expect(lines.length, 1); // inserted exactly once
    });

    test('preserves existing entries when adding new playlist', () async {
      final musicFile = File('/tmp/vdj_test_track3.mp3');
      if (!musicFile.existsSync()) {
        musicFile.writeAsBytesSync([]);
      }
      final track = _track(filePath: musicFile.path);

      // Pre-populate order file
      final orderDir =
          Directory(p.join(tmpVdjRoot.path, 'Folders/LocalMusic'));
      orderDir.createSync(recursive: true);
      File(p.join(orderDir.path, 'order'))
          .writeAsStringSync('Existing Crate\n');

      await svc.exportCrate(
          vdjRoot: tmpVdjRoot.path,
          playlistName: 'New Crate',
          tracks: [track]);

      final content = File(p.join(orderDir.path, 'order')).readAsStringSync();
      expect(content, contains('Existing Crate'));
      expect(content, contains('New Crate'));
    });
  });

  // ── Full export result ────────────────────────────────────────────────────

  group('exportCrate result', () {
    late Directory tmpVdjRoot;

    setUp(() {
      tmpVdjRoot = Directory.systemTemp.createTempSync('vdj_result_test_');
    });

    tearDown(() {
      if (tmpVdjRoot.existsSync()) tmpVdjRoot.deleteSync(recursive: true);
    });

    test('result contains correct metadata', () async {
      final musicFile = File('/tmp/vdj_result_track.mp3');
      if (!musicFile.existsSync()) musicFile.writeAsBytesSync([]);
      final track = _track(filePath: musicFile.path);

      final result = await svc.exportCrate(
        vdjRoot: tmpVdjRoot.path,
        playlistName: 'Result Test',
        tracks: [track],
      );

      expect(result.target, DjExportTarget.virtualDj);
      expect(result.crateName, 'Result Test');
      expect(result.rootPath, tmpVdjRoot.path);
      expect(result.outputPath, endsWith('.vdjfolder'));
      expect(result.localCount, 1);
      expect(result.skippedCount, 0);
    });

    test('output .vdjfolder file is written to disk', () async {
      final musicFile = File('/tmp/vdj_disk_track.mp3');
      if (!musicFile.existsSync()) musicFile.writeAsBytesSync([]);
      final track = _track(filePath: musicFile.path);

      final result = await svc.exportCrate(
        vdjRoot: tmpVdjRoot.path,
        playlistName: 'Disk Test',
        tracks: [track],
      );

      expect(File(result.outputPath).existsSync(), isTrue);
    });
  });
}
