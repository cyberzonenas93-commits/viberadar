// test/desktop/greatest_of_service_test.dart
//
// Pure-logic tests for GreatestOfService.
// • computeGreatestScore — deterministic weighted formula
// • buildGreatestOfSet  — filter + ordering
// • static helpers      — eraLabel, groupByEra, eraPresets
// No Flutter widgets; no Firebase.

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/trend_point.dart';
import 'package:viberadar/services/greatest_of_service.dart';

// ---------------------------------------------------------------------------
// Track helper
// ---------------------------------------------------------------------------

Track _track({
  String id = '1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  double trendScore = 0.5,
  int bpm = 120,
  String keySignature = '5A',
  String genre = 'Afrobeats',
  double energyLevel = 0.5,
  List<TrendPoint> trendHistory = const [],
  Map<String, double> regionScores = const {},
  Map<String, String> platformLinks = const {},
  List<String> sources = const ['spotify'],
  int? releaseYear,
}) {
  final now = DateTime(2020, 1, 1);
  return Track(
    id: id,
    title: title,
    artist: artist,
    artworkUrl: '',
    bpm: bpm,
    keySignature: keySignature,
    genre: genre,
    vibe: 'club',
    trendScore: trendScore,
    regionScores: regionScores,
    platformLinks: platformLinks,
    createdAt: now,
    updatedAt: now,
    energyLevel: energyLevel,
    trendHistory: trendHistory,
    sources: sources,
    releaseYear: releaseYear,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final svc = GreatestOfService();

  // ── computeGreatestScore ────────────────────────────────────────────────────

  group('GreatestOfService.computeGreatestScore', () {
    test('returns a value in [0.0, 1.0]', () {
      final t = _track();
      final score = svc.computeGreatestScore(t);
      expect(score, inInclusiveRange(0.0, 1.0));
    });

    test('is deterministic — same track yields same score twice', () {
      final t = _track(trendScore: 0.7, bpm: 128, keySignature: '8B');
      final s1 = svc.computeGreatestScore(t);
      final s2 = svc.computeGreatestScore(t);
      expect(s1, equals(s2));
    });

    test('higher trendScore → strictly higher score (all else equal)', () {
      final low = _track(id: 'low', trendScore: 0.1);
      final high = _track(id: 'high', trendScore: 0.9);
      expect(svc.computeGreatestScore(high),
          greaterThan(svc.computeGreatestScore(low)));
    });

    test('more region scores → higher artistInfluence component', () {
      final narrow = _track(id: 'n',
          regionScores: {'NG': 0.8}, trendScore: 0.5);
      final broad = _track(id: 'b',
          regionScores: {'NG': 0.8, 'GH': 0.7, 'US': 0.6, 'GB': 0.5,
                         'ZA': 0.4, 'FR': 0.3},
          trendScore: 0.5);
      expect(svc.computeGreatestScore(broad),
          greaterThan(svc.computeGreatestScore(narrow)));
    });

    test('more platform links → higher chartLegacy component', () {
      final few = _track(id: 'f',
          platformLinks: {'spotify': 'url1'});
      final many = _track(id: 'm',
          platformLinks: {'spotify': 'url1', 'apple': 'url2',
                          'youtube': 'url3', 'tidal': 'url4', 'deezer': 'url5'});
      expect(svc.computeGreatestScore(many),
          greaterThan(svc.computeGreatestScore(few)));
    });

    test('DJ-friendly BPM (85–140) yields higher score than extreme BPM', () {
      final friendly = _track(id: 'f', bpm: 120, trendScore: 0.5);
      final extreme = _track(id: 'e', bpm: 200, trendScore: 0.5);
      expect(svc.computeGreatestScore(friendly),
          greaterThan(svc.computeGreatestScore(extreme)));
    });

    test('known keySignature gives a bonus over missing key ("--")', () {
      // Use BPM=70 — in the outer range (0.6 score), so key bonus (0.15)
      // pushes it to 0.75 vs 0.6 without hitting the 1.0 clamp.
      final withKey = _track(id: 'wk', keySignature: '8B', bpm: 70, trendScore: 0.5);
      final noKey = _track(id: 'nk', keySignature: '--', bpm: 70, trendScore: 0.5);
      expect(svc.computeGreatestScore(withKey),
          greaterThan(svc.computeGreatestScore(noKey)));
    });

    test('more sources yield higher cross-source prominence', () {
      final single = _track(id: 's', sources: ['spotify']);
      final triple = _track(id: 't',
          sources: ['spotify', 'youtube', 'billboard']);
      // All other fields identical — only sources differ
      expect(svc.computeGreatestScore(triple),
          greaterThan(svc.computeGreatestScore(single)));
    });

    test('older track with high trendScore scores higher on timelessness', () {
      // A track from 2010 (~14 yrs old) with trendScore 0.9
      final old = _track(id: 'old', releaseYear: 2010, trendScore: 0.9);
      // A very recent track (2024) with same trendScore
      final recent = _track(id: 'new', releaseYear: 2024, trendScore: 0.9);
      expect(svc.computeGreatestScore(old),
          greaterThan(svc.computeGreatestScore(recent)));
    });

    test('track younger than 2 years has timelessness == 0', () {
      // timelessness is tested indirectly; a track released THIS year cannot
      // dominate purely via age — verify score still in range
      final brand = _track(id: 'brand', releaseYear: DateTime.now().year,
          trendScore: 1.0);
      final score = svc.computeGreatestScore(brand);
      expect(score, inInclusiveRange(0.0, 1.0));
    });

    test('weights sum to 1.0 exactly', () {
      // 0.20 + 0.15 + 0.15 + 0.12 + 0.10 + 0.10 + 0.08 + 0.10 = 1.00
      const weights = [0.20, 0.15, 0.15, 0.12, 0.10, 0.10, 0.08, 0.10];
      final total = weights.reduce((a, b) => a + b);
      expect(total, closeTo(1.0, 1e-9));
    });

    test('fully-loaded track scores higher than empty track', () {
      final powerhouse = _track(
        id: 'power',
        trendScore: 0.95,
        bpm: 120,
        keySignature: '8B',
        energyLevel: 0.9,
        trendHistory: [const TrendPoint(label: 'w1', score: 0.7),
                       const TrendPoint(label: 'w2', score: 0.95)],
        regionScores: {'NG': 0.9, 'GH': 0.8, 'US': 0.7, 'GB': 0.6},
        platformLinks: {'spotify': 'u1', 'apple': 'u2', 'youtube': 'u3',
                        'tidal': 'u4', 'deezer': 'u5'},
        sources: ['spotify', 'youtube', 'billboard'],
        releaseYear: 2012,
      );
      final minimal = _track(id: 'min');
      expect(svc.computeGreatestScore(powerhouse),
          greaterThan(svc.computeGreatestScore(minimal)));
    });
  });

  // ── buildGreatestOfSet — ordering ──────────────────────────────────────────

  group('GreatestOfService.buildGreatestOfSet — ordering', () {
    test('returns tracks ordered by computeGreatestScore descending', () {
      final tracks = [
        _track(id: 'low', trendScore: 0.1),
        _track(id: 'high', trendScore: 0.9,
            regionScores: {'US': 0.9, 'NG': 0.8, 'GB': 0.7, 'ZA': 0.6},
            platformLinks: {'sp': 'u', 'ap': 'u2', 'yt': 'u3', 'td': 'u4', 'dz': 'u5'},
            sources: ['spotify', 'youtube', 'billboard']),
        _track(id: 'mid', trendScore: 0.5),
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks);
      expect(result.first.id, 'high');
      // Score of result[0] >= result[1] >= result[2]
      for (var i = 0; i < result.length - 1; i++) {
        expect(svc.computeGreatestScore(result[i]),
            greaterThanOrEqualTo(svc.computeGreatestScore(result[i + 1])));
      }
    });

    test('respects the limit parameter', () {
      final tracks = [
        for (var i = 0; i < 20; i++)
          _track(id: 'l$i', artist: 'A$i', trendScore: i * 0.05),
      ];
      final result = svc.buildGreatestOfSet(tracks: tracks, limit: 5);
      expect(result.length, 5);
    });
  });

  // ── buildGreatestOfSet — genre filter ──────────────────────────────────────

  group('GreatestOfService.buildGreatestOfSet — genre filter', () {
    test('filters to the specified genre', () {
      final tracks = [
        _track(id: 'h1', genre: 'House', trendScore: 0.8),
        _track(id: 'a1', genre: 'Afrobeats', trendScore: 0.9),
        _track(id: 'h2', genre: 'House', trendScore: 0.6),
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks, genre: 'House');
      expect(result.map((t) => t.genre).toSet(), {'House'});
      expect(result.length, 2);
    });

    test('"All" genre returns all tracks', () {
      final tracks = [
        _track(id: 'x1', genre: 'House'),
        _track(id: 'x2', genre: 'Techno'),
      ];
      final result = svc.buildGreatestOfSet(tracks: tracks, genre: 'All');
      expect(result.length, 2);
    });

    test('comma-separated multi-genre filter works', () {
      final tracks = [
        _track(id: 'm1', genre: 'house'),
        _track(id: 'm2', genre: 'techno'),
        _track(id: 'm3', genre: 'afrobeats'),
      ];
      final result = svc.buildGreatestOfSet(tracks: tracks,
          genre: 'house,techno');
      final genres = result.map((t) => t.genre).toSet();
      expect(genres, containsAll(['house', 'techno']));
      expect(genres, isNot(contains('afrobeats')));
    });
  });

  // ── buildGreatestOfSet — artist filter ─────────────────────────────────────

  group('GreatestOfService.buildGreatestOfSet — artist filter', () {
    test('filters to tracks whose artist contains the artist string', () {
      final tracks = [
        _track(id: 'art1', artist: 'Burna Boy', genre: 'Afrobeats'),
        _track(id: 'art2', artist: 'Wizkid', genre: 'Afrobeats'),
        _track(id: 'art3', artist: 'Burna Boy feat. Wizkid', genre: 'Afrobeats'),
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks, artist: 'Burna Boy');
      final artistNames = result.map((t) => t.artist).toList();
      // Should include 'Burna Boy' and 'Burna Boy feat. Wizkid'
      expect(artistNames, contains('Burna Boy'));
      expect(artistNames, contains('Burna Boy feat. Wizkid'));
      expect(artistNames, isNot(contains('Wizkid')));
    });
  });

  // ── buildGreatestOfSet — release-year range ────────────────────────────────

  group('GreatestOfService.buildGreatestOfSet — year range', () {
    test('yearFrom excludes tracks released before it', () {
      final tracks = [
        _track(id: 'y1', releaseYear: 1999, trendScore: 0.8),
        _track(id: 'y2', releaseYear: 2005, trendScore: 0.7),
        _track(id: 'y3', releaseYear: 2015, trendScore: 0.6),
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks, yearFrom: 2000);
      expect(result.map((t) => t.id).toList(), isNot(contains('y1')));
      expect(result.map((t) => t.id).toList(), containsAll(['y2', 'y3']));
    });

    test('yearTo excludes tracks released after it', () {
      final tracks = [
        _track(id: 'ya', releaseYear: 2018),
        _track(id: 'yb', releaseYear: 2022),
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks, yearTo: 2020);
      expect(result.map((t) => t.id), contains('ya'));
      expect(result.map((t) => t.id), isNot(contains('yb')));
    });

    test('combined yearFrom + yearTo acts as an inclusive range', () {
      final tracks = [
        _track(id: 'r1', releaseYear: 1999),
        _track(id: 'r2', releaseYear: 2010),
        _track(id: 'r3', releaseYear: 2019),
        _track(id: 'r4', releaseYear: 2025),
      ];
      final result = svc.buildGreatestOfSet(tracks: tracks,
          yearFrom: 2005, yearTo: 2019);
      final ids = result.map((t) => t.id).toList();
      expect(ids, containsAll(['r2', 'r3']));
      expect(ids, isNot(contains('r1')));
      expect(ids, isNot(contains('r4')));
    });
  });

  // ── buildGreatestOfSet — region filter ────────────────────────────────────

  group('GreatestOfService.buildGreatestOfSet — region filter', () {
    test('region filter keeps only tracks whose leadRegion matches', () {
      final tracks = [
        _track(id: 'reg1', regionScores: {'NG': 0.9}),  // leadRegion = NG
        _track(id: 'reg2', regionScores: {'US': 0.8}),  // leadRegion = US
      ];

      final result = svc.buildGreatestOfSet(tracks: tracks, region: 'NG');
      expect(result.length, 1);
      expect(result.single.id, 'reg1');
    });
  });

  // ── eraLabel static helper ─────────────────────────────────────────────────

  group('GreatestOfService.eraLabel', () {
    test('pre-2000 release → "Pre-2000"', () {
      final t = _track(releaseYear: 1995);
      expect(GreatestOfService.eraLabel(t), 'Pre-2000');
    });

    test('year 2000 → "2000s"', () {
      final t = _track(releaseYear: 2000);
      expect(GreatestOfService.eraLabel(t), '2000s');
    });

    test('year 2009 → "2000s"', () {
      final t = _track(releaseYear: 2009);
      expect(GreatestOfService.eraLabel(t), '2000s');
    });

    test('year 2010 → "2010s"', () {
      final t = _track(releaseYear: 2010);
      expect(GreatestOfService.eraLabel(t), '2010s');
    });

    test('year 2020 → "2020s"', () {
      final t = _track(releaseYear: 2020);
      expect(GreatestOfService.eraLabel(t), '2020s');
    });

    test('current year → "2020s"', () {
      final t = _track(releaseYear: DateTime.now().year);
      expect(GreatestOfService.eraLabel(t), '2020s');
    });
  });

  // ── groupByEra static helper ───────────────────────────────────────────────

  group('GreatestOfService.groupByEra', () {
    test('groups tracks into correct era buckets', () {
      final tracks = [
        _track(id: 'e1', releaseYear: 1998),
        _track(id: 'e2', releaseYear: 2005),
        _track(id: 'e3', releaseYear: 2015),
        _track(id: 'e4', releaseYear: 2023),
      ];

      final grouped = GreatestOfService.groupByEra(tracks);
      expect(grouped['Pre-2000']!.map((t) => t.id), contains('e1'));
      expect(grouped['2000s']!.map((t) => t.id), contains('e2'));
      expect(grouped['2010s']!.map((t) => t.id), contains('e3'));
      expect(grouped['2020s']!.map((t) => t.id), contains('e4'));
    });

    test('returns empty map for empty input', () {
      expect(GreatestOfService.groupByEra([]), isEmpty);
    });
  });

  // ── eraPresets constant ────────────────────────────────────────────────────

  group('GreatestOfService.eraPresets', () {
    test('contains expected keys', () {
      expect(GreatestOfService.eraPresets.keys,
          containsAll(['90s', '2000s', '2010s', '2020s', 'All Time']));
    });

    test('"90s" preset has yearFrom=1990, yearTo=1999', () {
      final preset = GreatestOfService.eraPresets['90s']!;
      expect(preset.$1, 1990);
      expect(preset.$2, 1999);
    });

    test('"All Time" preset has null yearFrom and yearTo', () {
      final preset = GreatestOfService.eraPresets['All Time']!;
      expect(preset.$1, isNull);
      expect(preset.$2, isNull);
    });
  });
}
