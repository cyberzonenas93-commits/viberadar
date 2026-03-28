// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/services/virtual_dj_cue_writer.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

HotCue _cue({
  int index = 0,
  CueType type = CueType.intro,
  double timeSeconds = 5.0,
  String label = 'Intro',
}) =>
    HotCue(
      id: 'cue-$index',
      trackId: 'track1',
      cueIndex: index,
      cueType: type,
      label: label,
      timeSeconds: timeSeconds,
      confidence: 0.9,
      source: CueSource.genreTemplate,
      isSuggested: false,
    );

/// Minimal valid VirtualDJ database.xml with one Song entry.
String _buildDatabase(String filePath) => '''<?xml version="1.0" encoding="UTF-8"?>
<VirtualDJ_Database Version="9">
  <Song FilePath="$filePath" FileSize="8000000">
    <Tags Author="Test Artist" Title="Test Track" Bpm="128" Key="8A"/>
  </Song>
</VirtualDJ_Database>''';

void main() {
  late VirtualDjCueWriter writer;
  late Directory tmpDir;
  late File dbFile;
  const trackPath = '/music/test.mp3';

  setUp(() {
    writer = VirtualDjCueWriter();
    tmpDir = Directory.systemTemp.createTempSync('vdj_cue_writer_test_');
    dbFile = File(p.join(tmpDir.path, 'database.xml'));
    dbFile.writeAsStringSync(_buildDatabase(trackPath));
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // ── Missing database ──────────────────────────────────────────────────────

  group('missing database.xml', () {
    test('returns databaseNotFound when no database.xml exists', () async {
      final emptyDir = Directory.systemTemp.createTempSync('vdj_empty_test_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final result = await writer.writeCues(
        vdjRoot: emptyDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      expect(result.status, VdjCueWriteStatus.databaseNotFound);
    });
  });

  // ── Track not found ───────────────────────────────────────────────────────

  group('song not found', () {
    test('returns songNotFound when track is not in database', () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: '/nonexistent/track.mp3',
        cues: [_cue()],
      );
      expect(result.status, VdjCueWriteStatus.songNotFound);
    });

    test('songNotFound result contains a user-friendly warning', () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: '/nonexistent/track.mp3',
        cues: [_cue()],
      );
      expect(result.warnings, isNotEmpty);
      expect(result.warnings.first.toLowerCase(), contains('virtualDJ'.toLowerCase()));
    });
  });

  // ── Successful write ──────────────────────────────────────────────────────

  group('successful write', () {
    test('returns success status', () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      expect(result.status, VdjCueWriteStatus.success);
    });

    test('cuesWritten equals the number of cues provided', () async {
      final cues = [_cue(index: 0), _cue(index: 1), _cue(index: 2)];
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: cues,
      );
      expect(result.cuesWritten, 3);
    });

    test('creates a backup file alongside database.xml', () async {
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      final backups = tmpDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.bak'))
          .toList();
      expect(backups, isNotEmpty);
    });

    test('backup path is returned in result', () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      expect(result.backupPath, isNotNull);
      expect(File(result.backupPath!).existsSync(), isTrue);
    });

    test('written database contains Poi element with correct Pos', () async {
      final cue = _cue(timeSeconds: 10.0);
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [cue],
      );
      final content = dbFile.readAsStringSync();
      // Pos should be 10000 ms
      expect(content, contains('Pos="10000"'));
    });

    test('written Poi has correct Type="cue"', () async {
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      final content = dbFile.readAsStringSync();
      expect(content, contains('Type="cue"'));
    });

    test('written Poi has correct Num attribute', () async {
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue(index: 3)],
      );
      final content = dbFile.readAsStringSync();
      expect(content, contains('Num="3"'));
    });

    test('written Poi has correct Name attribute', () async {
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue(label: 'My Drop')],
      );
      final content = dbFile.readAsStringSync();
      expect(content, contains('Name="My Drop"'));
    });

    test('written Poi has correct Color from cueType.vdjColor', () async {
      final cue = _cue(type: CueType.drop);
      await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [cue],
      );
      final content = dbFile.readAsStringSync();
      expect(content, contains('Color="${CueType.drop.vdjColor}"'));
    });
  });

  // ── Idempotency ───────────────────────────────────────────────────────────

  group('idempotency', () {
    test('writing cues twice replaces old cues (not duplicates)', () async {
      final cues = [_cue(index: 0, label: 'First Intro')];
      await writer.writeCues(
          vdjRoot: tmpDir.path, trackFilePath: trackPath, cues: cues);

      final cues2 = [_cue(index: 0, label: 'Second Intro')];
      await writer.writeCues(
          vdjRoot: tmpDir.path, trackFilePath: trackPath, cues: cues2);

      final content = dbFile.readAsStringSync();
      // Only the second label should appear
      expect(content, contains('Second Intro'));
      expect(content, isNot(contains('First Intro')));

      // Only one Poi should exist
      expect('Pos="'.allMatches(content).length, 1);
    });
  });

  // ── Out-of-range cue index ────────────────────────────────────────────────

  group('out-of-range cue index', () {
    test('cues with index > 7 are skipped with a warning', () async {
      final badCue = _cue(index: 9);
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [badCue],
      );
      expect(result.cuesWritten, 0);
      expect(result.warnings, isNotEmpty);
    });

    test('valid cues alongside out-of-range cues still write correctly',
        () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue(index: 0), _cue(index: 9)], // one valid, one bad
      );
      expect(result.cuesWritten, 1);
      expect(result.warnings.length, 1);
    });
  });

  // ── ParseError ────────────────────────────────────────────────────────────

  group('parse error', () {
    test('returns parseError for malformed XML', () async {
      dbFile.writeAsStringSync('<<< NOT XML >>>');
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      expect(result.status, VdjCueWriteStatus.parseError);
    });
  });

  // ── Summary helper ────────────────────────────────────────────────────────

  group('VdjCueWriteResult.summary', () {
    test('success summary contains cue count', () async {
      final result = await writer.writeCues(
        vdjRoot: tmpDir.path,
        trackFilePath: trackPath,
        cues: [_cue(index: 0), _cue(index: 1)],
      );
      expect(result.summary, contains('2'));
    });

    test('databaseNotFound summary mentions file', () async {
      final empty =
          Directory.systemTemp.createTempSync('vdj_cue_empty2_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final result = await writer.writeCues(
        vdjRoot: empty.path,
        trackFilePath: trackPath,
        cues: [_cue()],
      );
      expect(result.summary.toLowerCase(), contains('database.xml'));
    });
  });
}
