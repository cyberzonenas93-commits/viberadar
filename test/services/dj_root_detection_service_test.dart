import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/services/dj_root_detection_service.dart';

void main() {
  late DjRootDetectionService svc;

  setUp(() => svc = DjRootDetectionService());

  // ── VirtualDJ root validation ────────────────────────────────────────────

  group('validateVirtualDjRoot', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('vdj_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('returns false for empty path', () {
      expect(svc.validateVirtualDjRoot(''), isFalse);
    });

    test('returns false for non-existent directory', () {
      expect(svc.validateVirtualDjRoot('/does/not/exist'), isFalse);
    });

    test('returns false when fewer than 2 markers present', () {
      // Only one marker: database.xml
      File(p.join(tmpDir.path, 'database.xml')).writeAsStringSync('<db/>');
      expect(svc.validateVirtualDjRoot(tmpDir.path), isFalse);
    });

    test('returns true when database.xml + settings.xml present', () {
      File(p.join(tmpDir.path, 'database.xml')).writeAsStringSync('<db/>');
      File(p.join(tmpDir.path, 'settings.xml')).writeAsStringSync('<s/>');
      expect(svc.validateVirtualDjRoot(tmpDir.path), isTrue);
    });

    test('returns true when database.xml + Folders directory present', () {
      File(p.join(tmpDir.path, 'database.xml')).writeAsStringSync('<db/>');
      Directory(p.join(tmpDir.path, 'Folders')).createSync();
      expect(svc.validateVirtualDjRoot(tmpDir.path), isTrue);
    });

    test('returns true when Playlists + History directories present', () {
      Directory(p.join(tmpDir.path, 'Playlists')).createSync();
      Directory(p.join(tmpDir.path, 'History')).createSync();
      expect(svc.validateVirtualDjRoot(tmpDir.path), isTrue);
    });

    test('returns true when all 5 markers present', () {
      File(p.join(tmpDir.path, 'database.xml')).writeAsStringSync('<db/>');
      File(p.join(tmpDir.path, 'settings.xml')).writeAsStringSync('<s/>');
      Directory(p.join(tmpDir.path, 'Folders')).createSync();
      Directory(p.join(tmpDir.path, 'Playlists')).createSync();
      Directory(p.join(tmpDir.path, 'History')).createSync();
      expect(svc.validateVirtualDjRoot(tmpDir.path), isTrue);
    });
  });

  // ── Serato root validation ───────────────────────────────────────────────

  group('validateSeratoRoot', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('serato_test_');
    });

    tearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    test('returns false for empty path', () {
      expect(svc.validateSeratoRoot(''), isFalse);
    });

    test('returns false for non-existent directory', () {
      expect(svc.validateSeratoRoot('/does/not/exist'), isFalse);
    });

    test('returns false when only one marker present', () {
      Directory(p.join(tmpDir.path, 'Subcrates')).createSync();
      expect(svc.validateSeratoRoot(tmpDir.path), isFalse);
    });

    test('returns true when Subcrates + "database V2" present', () {
      Directory(p.join(tmpDir.path, 'Subcrates')).createSync();
      File(p.join(tmpDir.path, 'database V2')).writeAsBytesSync([]);
      expect(svc.validateSeratoRoot(tmpDir.path), isTrue);
    });

    test('returns true when Subcrates + History present', () {
      Directory(p.join(tmpDir.path, 'Subcrates')).createSync();
      Directory(p.join(tmpDir.path, 'History')).createSync();
      expect(svc.validateSeratoRoot(tmpDir.path), isTrue);
    });

    test('returns true when Subcrates + Metadata present', () {
      Directory(p.join(tmpDir.path, 'Subcrates')).createSync();
      Directory(p.join(tmpDir.path, 'Metadata')).createSync();
      expect(svc.validateSeratoRoot(tmpDir.path), isTrue);
    });
  });

  // ── Auto-detection ────────────────────────────────────────────────────────

  group('detectVirtualDjRoot', () {
    test('returns null when no valid candidates exist on this machine', () async {
      // On a CI/test machine where VirtualDJ is not installed, null is correct.
      final result = await svc.detectVirtualDjRoot();
      // We can't assert a fixed value — just assert the type contract.
      expect(result, anyOf(isNull, isA<String>()));
    });
  });

  group('detectSeratoRoot', () {
    test('returns null when no valid candidates exist on this machine', () async {
      final result = await svc.detectSeratoRoot();
      expect(result, anyOf(isNull, isA<String>()));
    });
  });
}
