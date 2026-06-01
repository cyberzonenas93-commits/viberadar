import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/services/virtual_dj_cue_writer.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

HotCue _cue({
  int    index  = 0,
  CueType type  = CueType.intro,
  String label  = 'Intro',
  double timeSec = 0.0,
  double conf   = 0.85,
}) {
  return HotCue(
    trackId:     'track-1',
    cueIndex:    index,
    cueType:     type,
    label:       label,
    timeSeconds: timeSec,
    confidence:  conf,
    source:      CueSource.genreTemplate,
  );
}

/// Creates a minimal valid VirtualDJ database.xml in [dir].
File _fakeDb(Directory dir, {String? songBlock}) {
  final content = '''<?xml version="1.0" encoding="UTF-8"?>
<VirtualDJ_Database Version="8.5">
${songBlock ?? ''}
</VirtualDJ_Database>
''';
  return File(p.join(dir.path, 'database.xml'))
    ..writeAsStringSync(content);
}

/// Validation markers VirtualDJ root detection expects.
void _seedVdjRoot(Directory dir) {
  File(p.join(dir.path, 'database.xml')).createSync();
  Directory(p.join(dir.path, 'Folders')).createSync();
  Directory(p.join(dir.path, 'Playlists')).createSync();
}

void main() {
  late Directory tempDir;
  late VirtualDjCueWriter writer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vdj_cue_test_');
    _seedVdjRoot(tempDir);
    _fakeDb(tempDir); // replace stub with real empty db
    writer = VirtualDjCueWriter();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  // ── Root validation ──────────────────────────────────────────────────────────
  group('VirtualDjCueWriter — root validation', () {

    test('validateRoot returns true for valid VDJ directory', () {
      expect(writer.validateRoot(tempDir.path), isTrue);
    });

    test('validateRoot returns false for non-existent path', () {
      expect(writer.validateRoot('/does/not/exist'), isFalse);
    });

    test('writeCues fails with invalid root', () async {
      final result = await writer.writeCues(
        vdjRoot: '/invalid/path',
        localFilePath: '/music/track.mp3',
        cues: [_cue()],
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Invalid'));
    });
  });

  // ── New song entry injection ───────────────────────────────────────────────
  group('VirtualDjCueWriter — new Song entry', () {

    test('Writes a new <Song> entry when track is not in database', () async {
      final trackPath = '/music/new_track.mp3';
      final result = await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: trackPath,
        cues: [_cue(label: 'Intro', timeSec: 0.0), _cue(index: 1, type: CueType.drop, label: 'Drop', timeSec: 45.5)],
      );
      expect(result.success, isTrue);
      expect(result.cuesWritten, equals(2));

      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('Song'));
      expect(xml, contains(trackPath));
      expect(xml, contains('Num="0"'));
      expect(xml, contains('Num="1"'));
      expect(xml, contains('45.500'));
    });

    test('Backup file is created on first write', () async {
      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/track.mp3',
        cues: [_cue()],
      );
      final backup = File('${p.join(tempDir.path, 'database.xml')}.viberadar-backup');
      expect(backup.existsSync(), isTrue);
    });
  });

  // ── Existing Song merging ──────────────────────────────────────────────────
  group('VirtualDjCueWriter — existing Song merge', () {

    test('Adds cues to existing Song entry without removing other content', () async {
      _fakeDb(tempDir, songBlock: '''
  <Song Filepath="/music/existing.mp3" Flag="0">
    <Tags Title="Existing Track" Author="DJ Test" />
  </Song>''');

      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/existing.mp3',
        cues: [_cue(label: 'Intro', timeSec: 0.0)],
      );

      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('Tags Title="Existing Track"'));
      expect(xml, contains('Poi'));
      expect(xml, contains('Name="Intro"'));
    });

    test('Replaces only matching Poi slot numbers on re-write', () async {
      _fakeDb(tempDir, songBlock: '''
  <Song Filepath="/music/track.mp3" Flag="0">
    <Poi Pos="0.000" Type="cue" Name="Old Intro" Num="0" />
    <Poi Pos="99.000" Type="cue" Name="Manual Cue" Num="5" />
  </Song>''');

      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/track.mp3',
        cues: [_cue(index: 0, label: 'New Intro', timeSec: 1.5)],
      );

      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('New Intro'));
      expect(xml, isNot(contains('Old Intro')));
      // Slot 5 (user-defined, not in our write set) should survive
      expect(xml, contains('Manual Cue'));
    });
  });

  // ── Dry run ────────────────────────────────────────────────────────────────
  group('VirtualDjCueWriter — dry run', () {

    test('Dry run does not modify database.xml', () async {
      final before = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      final result = await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/dry.mp3',
        cues: [_cue()],
        dryRun: true,
      );
      final after = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(result.success, isTrue);
      expect(after, equals(before));
    });

    test('Dry run does not create backup file', () async {
      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/dry.mp3',
        cues: [_cue()],
        dryRun: true,
      );
      final backup = File('${p.join(tempDir.path, 'database.xml')}.viberadar-backup');
      expect(backup.existsSync(), isFalse);
    });
  });

  // ── Empty cues ──────────────────────────────────────────────────────────────
  group('VirtualDjCueWriter — edge cases', () {

    test('Empty cue list succeeds without modifying file', () async {
      final before = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      final result = await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/track.mp3',
        cues: [],
      );
      final after = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(result.success, isTrue);
      expect(result.cuesWritten, equals(0));
      expect(after, equals(before));
    });

    test('Paths with special XML characters are escaped', () async {
      final trackPath = '/music/artist & title <extended>.mp3';
      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: trackPath,
        cues: [_cue(label: 'Drop & Go')],
      );
      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('&amp;'));
      // Should not contain raw unescaped & in attribute values
      expect(xml, isNot(contains('artist & title')));
    });

    test('Cue label with quotes is escaped', () async {
      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '/music/track.mp3',
        cues: [_cue(label: 'Say "Hello"')],
      );
      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('&quot;'));
    });
  });

  // ── Batch write ─────────────────────────────────────────────────────────────
  group('VirtualDjCueWriter — batch write', () {

    test('Writes cues for multiple tracks in one database edit', () async {
      final result = await writer.writeBatch(
        vdjRoot: tempDir.path,
        cuesByFilePath: {
          '/music/track1.mp3': [_cue(label: 'Track1 Intro')],
          '/music/track2.mp3': [_cue(label: 'Track2 Intro')],
        },
      );
      expect(result.every((r) => r.success), isTrue);
      final xml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(xml, contains('track1.mp3'));
      expect(xml, contains('track2.mp3'));
    });

    test('Batch creates only one backup for multiple tracks', () async {
      await writer.writeBatch(
        vdjRoot: tempDir.path,
        cuesByFilePath: {
          '/music/a.mp3': [_cue()],
          '/music/b.mp3': [_cue()],
        },
      );
      final backups = tempDir.listSync()
          .where((e) => e.path.endsWith('.viberadar-backup'))
          .toList();
      expect(backups.length, equals(1));
    });
  });

  // ── Library safety ─────────────────────────────────────────────────────────
  group('VirtualDjCueWriter — library safety', () {

    test('Does NOT modify original audio file', () async {
      final audioFile = File(p.join(tempDir.path, 'track.mp3'))
        ..writeAsBytesSync([0x49, 0x44, 0x33]); // fake ID3 header
      final before = audioFile.readAsBytesSync();

      await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: audioFile.path,
        cues: [_cue()],
      );

      final after = audioFile.readAsBytesSync();
      expect(after, equals(before)); // audio file unchanged
    });
  });

  group('VirtualDjCueWriter — path validation', () {
    setUp(() => _seedVdjRoot(tempDir));

    test('Rejects empty track path', () async {
      final r = await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: '',
        cues: [_cue()],
      );
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('empty'));
    });

    test('Rejects relative track path', () async {
      final r = await writer.writeCues(
        vdjRoot: tempDir.path,
        localFilePath: 'Music/track.mp3',
        cues: [_cue()],
      );
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('absolute'));
    });

    test('Relative paths with .. are rejected (isAbsolute guard)', () async {
      final r = await writer.writeCues(
        vdjRoot: tempDir.path,
        // Relative path with traversal — rejected by isAbsolute check before
        // the .. check even fires. (Absolute paths with .. are safely resolved
        // by p.normalize.)
        localFilePath: '../../../etc/passwd',
        cues: [_cue()],
      );
      expect(r.success, isFalse);
      expect(r.errorMessage, contains('absolute'));
    });

    test('Batch aborts entirely if any track path is invalid', () async {
      final good = File(p.join(tempDir.path, 'good.mp3'))..createSync();
      final results = await writer.writeBatch(
        vdjRoot: tempDir.path,
        cuesByFilePath: {
          good.path: [_cue()],
          '': [_cue()], // invalid
        },
      );
      expect(results.length, 2);
      // No track wrote successfully because one path was bad.
      expect(results.every((r) => r.cuesWritten == 0), isTrue);
      // database.xml on disk should NOT have gained the good track either.
      final dbXml = File(p.join(tempDir.path, 'database.xml')).readAsStringSync();
      expect(dbXml.contains('good.mp3'), isFalse);
    });
  });
}
