// test/dj_root_detection_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/services/dj_root_detection_service.dart';

void main() {
  late Directory tempDir;
  late DjRootDetectionService svc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vr_root_test_');
  });
  tearDownAll(() => tempDir.delete(recursive: true));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    svc = DjRootDetectionService();
  });

  // ── validateVirtualDjRoot ─────────────────────────────────────────────────

  group('validateVirtualDjRoot', () {
    test('accepts dir with database.xml + Folders', () async {
      final root = await Directory('${tempDir.path}/vdj_ok').create();
      await File('${root.path}/database.xml').create();
      await Directory('${root.path}/Folders').create();
      expect(svc.validateVirtualDjRoot(root.path), isTrue);
    });

    test('rejects dir with only one marker', () async {
      final root = await Directory('${tempDir.path}/vdj_one').create();
      await File('${root.path}/database.xml').create();
      expect(svc.validateVirtualDjRoot(root.path), isFalse);
    });

    test('rejects non-existent path', () {
      expect(svc.validateVirtualDjRoot('/no/such/path_abc123'), isFalse);
    });

    test('rejects empty directory', () async {
      final root = await Directory('${tempDir.path}/vdj_empty').create();
      expect(svc.validateVirtualDjRoot(root.path), isFalse);
    });
  });

  // ── validateSeratoRoot ────────────────────────────────────────────────────

  group('validateSeratoRoot', () {
    test('accepts dir with Subcrates', () async {
      final root = await Directory('${tempDir.path}/serato_ok').create();
      await Directory('${root.path}/Subcrates').create();
      expect(svc.validateSeratoRoot(root.path), isTrue);
    });

    test('accepts dir with database V2', () async {
      final root = await Directory('${tempDir.path}/serato_db').create();
      await File('${root.path}/database V2').create();
      expect(svc.validateSeratoRoot(root.path), isTrue);
    });

    test('rejects empty directory', () async {
      final root = await Directory('${tempDir.path}/serato_empty').create();
      expect(svc.validateSeratoRoot(root.path), isFalse);
    });

    test('rejects non-existent path', () {
      expect(svc.validateSeratoRoot('/no/serato_xyz99'), isFalse);
    });
  });

  // ── Persisted root round-trip ─────────────────────────────────────────────

  group('persist round-trip', () {
    test('persistVirtualDjRoot → getPersistedVirtualDjRoot', () async {
      await svc.persistVirtualDjRoot('/some/vdj/path');
      expect(await svc.getPersistedVirtualDjRoot(), equals('/some/vdj/path'));
    });
  });

  // ── resolveVirtualDjRoot honours persisted valid root ─────────────────────

  group('resolveVirtualDjRoot', () {
    test('returns persisted root when it validates', () async {
      final root = await Directory('${tempDir.path}/vdj_persist').create();
      await File('${root.path}/database.xml').create();
      await Directory('${root.path}/Folders').create();

      SharedPreferences.setMockInitialValues({'vdj_root_path': root.path});
      svc = DjRootDetectionService();

      expect(await svc.resolveVirtualDjRoot(), equals(root.path));
    });

    test('ignores stale persisted root', () async {
      SharedPreferences.setMockInitialValues(
          {'vdj_root_path': '/tmp/deleted_vdj_abc'});
      svc = DjRootDetectionService();
      final result = await svc.resolveVirtualDjRoot();
      expect(result, isNot(equals('/tmp/deleted_vdj_abc')));
    });
  });

  // ── resolveSeratoRoot honours persisted valid root ────────────────────────

  group('resolveSeratoRoot', () {
    test('returns persisted root when it validates', () async {
      final root = await Directory('${tempDir.path}/serato_persist').create();
      await Directory('${root.path}/Subcrates').create();

      SharedPreferences.setMockInitialValues({'serato_root_path': root.path});
      svc = DjRootDetectionService();

      expect(await svc.resolveSeratoRoot(), equals(root.path));
    });
  });
}
