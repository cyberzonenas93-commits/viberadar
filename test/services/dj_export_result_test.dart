import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/dj_export_result.dart';

void main() {
  // ── DjTrackResolution ──────────────────────────────────────────────────────

  group('DjTrackResolution', () {
    test('local track exportPath returns local file path', () {
      const r = DjTrackResolution(
        title: 'T',
        artist: 'A',
        status: DjTrackStatus.local,
        localFilePath: '/music/track.mp3',
      );
      expect(r.isLocal, isTrue);
      expect(r.isTidal, isFalse);
      expect(r.isSkipped, isFalse);
      expect(r.exportPath, '/music/track.mp3');
    });

    test('tidal track exportPath uses netsearch:// prefix', () {
      const r = DjTrackResolution(
        title: 'T',
        artist: 'A',
        status: DjTrackStatus.tidal,
        tidalTrackId: '12345',
      );
      expect(r.isTidal, isTrue);
      expect(r.exportPath, 'netsearch://td12345');
    });

    test('skipped track exportPath is empty', () {
      const r = DjTrackResolution(
        title: 'T',
        artist: 'A',
        status: DjTrackStatus.skipped,
        skipReason: 'not found',
      );
      expect(r.isSkipped, isTrue);
      expect(r.exportPath, '');
    });

    test('tidal track with null ID returns empty exportPath', () {
      const r = DjTrackResolution(
        title: 'T',
        artist: 'A',
        status: DjTrackStatus.tidal,
      );
      expect(r.exportPath, 'netsearch://tdnull');
    });
  });

  // ── DjExportResult ────────────────────────────────────────────────────────

  group('DjExportResult', () {
    DjExportResult _result(List<DjTrackResolution> tracks) => DjExportResult(
          target: DjExportTarget.virtualDj,
          crateName: 'Test',
          rootPath: '/vdj',
          outputPath: '/vdj/out.vdjfolder',
          tracks: tracks,
          exportedAt: DateTime(2026, 1, 1),
        );

    test('totalTracks returns correct count', () {
      final r = _result([
        const DjTrackResolution(
            title: 'A', artist: 'X', status: DjTrackStatus.local, localFilePath: '/a.mp3'),
        const DjTrackResolution(
            title: 'B', artist: 'X', status: DjTrackStatus.skipped),
      ]);
      expect(r.totalTracks, 2);
    });

    test('localCount counts only local tracks', () {
      final r = _result([
        const DjTrackResolution(
            title: 'A', artist: 'X', status: DjTrackStatus.local, localFilePath: '/a.mp3'),
        const DjTrackResolution(
            title: 'B', artist: 'X', status: DjTrackStatus.tidal, tidalTrackId: '1'),
        const DjTrackResolution(
            title: 'C', artist: 'X', status: DjTrackStatus.skipped),
      ]);
      expect(r.localCount, 1);
      expect(r.tidalCount, 1);
      expect(r.skippedCount, 1);
    });

    test('summary includes TIDAL count when present', () {
      final r = _result([
        const DjTrackResolution(
            title: 'A', artist: 'X', status: DjTrackStatus.tidal, tidalTrackId: '1'),
      ]);
      expect(r.summary, contains('TIDAL'));
    });

    test('summary omits TIDAL when count is 0', () {
      final r = _result([
        const DjTrackResolution(
            title: 'A', artist: 'X', status: DjTrackStatus.local, localFilePath: '/a.mp3'),
      ]);
      expect(r.summary, isNot(contains('TIDAL')));
    });
  });

  // ── DjExportTarget label ──────────────────────────────────────────────────

  group('DjExportTarget', () {
    test('VirtualDJ label', () {
      expect(DjExportTarget.virtualDj.label, 'VirtualDJ');
    });

    test('Serato label', () {
      expect(DjExportTarget.serato.label, 'Serato');
    });
  });
}
