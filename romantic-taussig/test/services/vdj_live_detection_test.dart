// Live detection test — runs against real VirtualDJ install on this machine.
// This test validates that auto-detection works with real markers.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:viberadar/models/library_track.dart';
import 'package:viberadar/services/dj_root_detection_service.dart';
import 'package:viberadar/services/virtual_dj_export_service.dart';

void main() {
  late DjRootDetectionService detection;
  late VirtualDjExportService vdj;

  setUp(() {
    detection = DjRootDetectionService();
    vdj = VirtualDjExportService();
  });

  group('Live VirtualDJ detection', () {
    test('detectVirtualDjRoot finds real VDJ install', () async {
      final root = await detection.detectVirtualDjRoot();
      // VDJ is installed on this machine
      expect(root, isNotNull);
      expect(root, contains('VirtualDJ'));
      expect(Directory(root!).existsSync(), isTrue);
    });

    test('validateVirtualDjRoot passes on real VDJ path', () {
      final home = Platform.environment['HOME'] ?? '';
      final vdjPath = p.join(home, 'Library', 'Application Support', 'VirtualDJ');
      expect(detection.validateVirtualDjRoot(vdjPath), isTrue);
    });
  });

  group('Live VirtualDJ export', () {
    test('exports .vdjfolder into real VDJ root', () async {
      final root = await detection.detectVirtualDjRoot();
      expect(root, isNotNull, reason: 'VDJ must be installed for this test');

      // Create a minimal test track
      final track = LibraryTrack(
        id: 'live_test_1',
        filePath: '/tmp/vdj_live_test.mp3',
        fileName: 'vdj_live_test.mp3',
        title: 'VibeRadar Test Track',
        artist: 'VibeRadar',
        album: 'Test',
        genre: 'Electronic',
        bpm: 128.0,
        key: '8A',
        durationSeconds: 180.0,
        fileSizeBytes: 5000000,
        fileExtension: '.mp3',
        md5Hash: 'test123',
        bitrate: 320,
        sampleRate: 44100,
      );

      final result = await vdj.exportCrate(
        vdjRoot: root!,
        playlistName: 'VibeRadar Live Test',
        tracks: [track],
      );

      // Verify result
      expect(result.crateName, 'VibeRadar Live Test');
      expect(result.localCount, 1);
      expect(result.outputPath, endsWith('.vdjfolder'));

      // Verify file was actually written
      final outputFile = File(result.outputPath);
      expect(outputFile.existsSync(), isTrue);

      // Verify XML content
      final content = outputFile.readAsStringSync();
      expect(content, contains('<VirtualFolder>'));
      expect(content, contains('title="VibeRadar Test Track"'));
      expect(content, contains('artist="VibeRadar"'));
      expect(content, contains('bpm="128.00"'));

      // Verify order file
      final orderFile = File(p.join(root, 'Folders', 'LocalMusic', 'order'));
      expect(orderFile.existsSync(), isTrue);
      final orderContent = orderFile.readAsStringSync();
      expect(orderContent, contains('VibeRadar Live Test'));

      // Clean up test file (leave order file — VDJ handles it)
      await outputFile.delete();
      // Remove our entry from order
      final cleanedOrder = orderContent.split('\n')
          .where((l) => l.trim() != 'VibeRadar Live Test')
          .join('\n');
      await orderFile.writeAsString(cleanedOrder.isEmpty ? '' : '$cleanedOrder\n');
    });
  });
}
