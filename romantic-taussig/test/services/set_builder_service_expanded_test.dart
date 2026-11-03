import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/set_builder_service.dart';

// ── Track fixture ───────────────────────────────────────────────────────────

Track _track({
  String id = '1',
  String title = 'Track',
  String artist = 'Artist',
  int bpm = 128,
  String key = '8A',
  String genre = 'House',
  String vibe = 'club',
  double energyLevel = 0.6,
  double trendScore = 0.5,
  int year = 2024,
}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: '',
      bpm: bpm,
      keySignature: key,
      genre: genre,
      vibe: vibe,
      trendScore: trendScore,
      regionScores: const {},
      platformLinks: const {},
      createdAt: DateTime(year),
      updatedAt: DateTime(year),
      energyLevel: energyLevel,
      trendHistory: const [],
    );

void main() {
  late SetBuilderService service;

  setUp(() => service = SetBuilderService());

  // ── Filtering ──────────────────────────────────────────────────────────────

  group('filtering', () {
    test('filters by BPM range', () {
      final tracks = [
        _track(id: '1', bpm: 100),
        _track(id: '2', bpm: 120),
        _track(id: '3', bpm: 140),
        _track(id: '4', bpm: 160),
      ];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 115,
        maxBpm: 145,
      );
      // Only bpm 120 and 140 should pass
      expect(result.every((t) => t.bpm >= 115 && t.bpm <= 145), isTrue);
    });

    test('filters by genre when not "All"', () {
      final tracks = [
        _track(id: '1', genre: 'House', bpm: 128),
        _track(id: '2', genre: 'Hip Hop', bpm: 128),
        _track(id: '3', genre: 'House', bpm: 128),
      ];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'House',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );
      expect(result.every((t) => t.genre == 'House'), isTrue);
    });

    test('filters by vibe when not "All"', () {
      final tracks = [
        _track(id: '1', vibe: 'club', bpm: 128),
        _track(id: '2', vibe: 'chill', bpm: 128),
        _track(id: '3', vibe: 'club', bpm: 128),
      ];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'club',
        minBpm: 100,
        maxBpm: 160,
      );
      expect(result.every((t) => t.vibe == 'club'), isTrue);
    });

    test('returns empty list when no tracks match filters', () {
      final tracks = [_track(id: '1', bpm: 200)];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 140,
      );
      expect(result, isEmpty);
    });

    test('filters by year range', () {
      final tracks = [
        _track(id: '1', bpm: 128, year: 2020),
        _track(id: '2', bpm: 128, year: 2022),
        _track(id: '3', bpm: 128, year: 2025),
      ];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
        yearFrom: 2021,
        yearTo: 2024,
      );
      // Only 2022 should pass
      expect(result.length, 1);
    });
  });

  // ── Target count ─────────────────────────────────────────────────────────

  group('target count', () {
    test('respects explicit trackCount parameter', () {
      final tracks = List.generate(
        30,
        (i) => _track(id: '$i', bpm: 120 + i % 10, energyLevel: 0.3 + i * 0.02),
      );
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 60,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
        trackCount: 10,
      );
      expect(result.length, 10);
    });

    test('computes target from duration when trackCount not given', () {
      final tracks = List.generate(
        50,
        (i) => _track(id: '$i', bpm: 120 + i % 10, energyLevel: 0.3 + i * 0.01),
      );
      // 60 min / 4 = 15 tracks expected
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 60,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );
      expect(result.length, 15);
    });

    test('clamps to minimum of 6', () {
      final tracks = List.generate(
        20,
        (i) => _track(id: '$i', bpm: 128, energyLevel: 0.3 + i * 0.02),
      );
      // 10 min / 4 = 2.5, but clamped to 6
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 10,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );
      expect(result.length, 6);
    });
  });

  // ── Sequencing stability ─────────────────────────────────────────────────

  group('sequencing stability', () {
    test('same input produces same output (deterministic)', () {
      final tracks = List.generate(
        10,
        (i) => _track(
          id: 'track_$i',
          bpm: 120 + i * 2,
          key: '${(i % 12) + 1}A',
          energyLevel: 0.3 + i * 0.06,
        ),
      );

      final r1 = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );
      final r2 = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );

      final ids1 = r1.map((t) => t.id).toList();
      final ids2 = r2.map((t) => t.id).toList();
      expect(ids1, equals(ids2));
    });

    test('no duplicate tracks in output', () {
      final tracks = List.generate(
        15,
        (i) => _track(id: 'u$i', bpm: 120 + i, energyLevel: 0.3 + i * 0.04),
      );
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
      );
      final ids = result.map((t) => t.id).toSet();
      expect(ids.length, result.length);
    });
  });

  // ── Harmonic compatibility ───────────────────────────────────────────────

  group('harmonic compatibility (internal)', () {
    test('identical key returns 1.0', () {
      // Using public buildSet is impractical for unit-testing private methods,
      // but we can verify via transition scoring in set output quality.
      // Two identical-key tracks should be preferred next to each other.
      final tracks = [
        _track(id: 'a', bpm: 128, key: '8A', energyLevel: 0.5),
        _track(id: 'b', bpm: 128, key: '8A', energyLevel: 0.52),
        _track(id: 'c', bpm: 128, key: '1B', energyLevel: 0.54),
      ];
      final result = service.buildSetSync(
        tracks: tracks,
        durationMinutes: 30,
        genre: 'All',
        vibe: 'All',
        minBpm: 100,
        maxBpm: 160,
        trackCount: 3,
      );
      // 'a' and 'b' share key 8A — they should end up adjacent
      final aIdx = result.indexWhere((t) => t.id == 'a');
      final bIdx = result.indexWhere((t) => t.id == 'b');
      expect((aIdx - bIdx).abs(), equals(1));
    });
  });
}
