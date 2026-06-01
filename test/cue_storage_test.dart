import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/models/hot_cue.dart';
import 'package:viberadar/services/cue_storage_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

List<HotCue> _makeCues(String trackId, int count) {
  return List.generate(count, (i) => HotCue(
    trackId:     trackId,
    cueIndex:    i,
    cueType:     CueType.values[i % CueType.values.length],
    label:       'Cue $i',
    timeSeconds: i * 30.0,
    confidence:  0.8,
    source:      CueSource.genreTemplate,
  ));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final storage = CueStorageService();

  group('CueStorageService — basic persistence', () {

    test('saveCues and loadCues round-trip correctly', () async {
      final cues = _makeCues('track-1', 4);
      await storage.saveCues('track-1', cues);
      final loaded = await storage.loadCues('track-1');

      expect(loaded.length, equals(4));
      expect(loaded[0].label,       equals('Cue 0'));
      expect(loaded[2].timeSeconds, equals(60.0));
      expect(loaded[3].cueIndex,    equals(3));
    });

    test('loadCues returns empty list for unknown trackId', () async {
      final loaded = await storage.loadCues('does-not-exist');
      expect(loaded, isEmpty);
    });

    test('hasCues returns false before save, true after', () async {
      expect(await storage.hasCues('track-x'), isFalse);
      await storage.saveCues('track-x', _makeCues('track-x', 1));
      expect(await storage.hasCues('track-x'), isTrue);
    });

    test('Overwriting existing cues replaces them', () async {
      await storage.saveCues('track-1', _makeCues('track-1', 5));
      await storage.saveCues('track-1', _makeCues('track-1', 2));
      final loaded = await storage.loadCues('track-1');
      expect(loaded.length, equals(2));
    });
  });

  group('CueStorageService — delete', () {

    test('deleteCues removes stored cues', () async {
      await storage.saveCues('track-del', _makeCues('track-del', 3));
      await storage.deleteCues('track-del');
      final loaded = await storage.loadCues('track-del');
      expect(loaded, isEmpty);
    });

    test('hasCues returns false after delete', () async {
      await storage.saveCues('track-del', _makeCues('track-del', 2));
      await storage.deleteCues('track-del');
      expect(await storage.hasCues('track-del'), isFalse);
    });
  });

  group('CueStorageService — loadAllCues', () {

    test('loadAllCues returns all saved track cues', () async {
      await storage.saveCues('t1', _makeCues('t1', 3));
      await storage.saveCues('t2', _makeCues('t2', 2));
      await storage.saveCues('t3', _makeCues('t3', 4));

      final all = await storage.loadAllCues();
      expect(all.length, equals(3));
      expect(all['t1']!.length, equals(3));
      expect(all['t2']!.length, equals(2));
      expect(all['t3']!.length, equals(4));
    });

    test('loadAllCues returns empty map when nothing is stored', () async {
      final all = await storage.loadAllCues();
      expect(all, isEmpty);
    });

    test('Deleted tracks are excluded from loadAllCues', () async {
      await storage.saveCues('keep', _makeCues('keep', 2));
      await storage.saveCues('gone', _makeCues('gone', 2));
      await storage.deleteCues('gone');

      final all = await storage.loadAllCues();
      expect(all.containsKey('keep'), isTrue);
      expect(all.containsKey('gone'), isFalse);
    });
  });

  group('CueStorageService — HotCue field preservation', () {

    test('All HotCue fields survive storage round-trip', () async {
      final original = HotCue(
        id:           'fixed-id-123',
        trackId:      'track-fields',
        cueIndex:     3,
        cueType:      CueType.drop,
        label:        'First Drop',
        timeSeconds:  91.5,
        confidence:   0.92,
        source:       CueSource.aiRanking,
        notes:        'AI ranked highest',
        isSuggested:  true,
        isWritten:    false,
        targetSoftware: 'virtualDJ',
      );

      await storage.saveCues('track-fields', [original]);
      final loaded = (await storage.loadCues('track-fields')).first;

      expect(loaded.id,             equals('fixed-id-123'));
      expect(loaded.cueIndex,       equals(3));
      expect(loaded.cueType,        equals(CueType.drop));
      expect(loaded.label,          equals('First Drop'));
      expect(loaded.timeSeconds,    equals(91.5));
      expect(loaded.timeMs,         equals(91500));
      expect(loaded.confidence,     equals(0.92));
      expect(loaded.source,         equals(CueSource.aiRanking));
      expect(loaded.notes,          equals('AI ranked highest'));
      expect(loaded.isWritten,      isFalse);
      expect(loaded.targetSoftware, equals('virtualDJ'));
    });
  });
}
