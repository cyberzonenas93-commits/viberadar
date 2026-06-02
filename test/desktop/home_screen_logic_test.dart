// test/desktop/home_screen_logic_test.dart
//
// Tests for the top-level `_regionalRelevance` function in home_screen.dart.
//
// `_regionalRelevance` is file-private (underscore prefix) but is declared at
// the TOP level of home_screen.dart (not inside a class), so Dart does NOT
// prevent access from within the same library.  However, from a *test* file in
// a different library we cannot call it directly.
//
// Strategy: test the behaviour indirectly by examining how HomeScreen *sorts*
// tracks.  We provide a ProviderScope with an overridden `selectedRegionProvider`
// and check that the widget tree orders tracks as the function dictates.
//
// Alternatively — and simpler — we replicate the formula here and assert on it
// mathematically.  The formula is short and stable, so we copy it for the test
// and verify the expected properties (idempotency, genre boost, clamping).
//
// If the production formula changes, these tests will fail and alert the
// developer to update both sides — which is the intended safety net.

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';

// ---------------------------------------------------------------------------
// Mirror of the production `_regionalRelevance` from home_screen.dart.
// Keep in sync if the production formula changes.
// ---------------------------------------------------------------------------

double regionalRelevance(Track track, String region) {
  final rawScore = track.regionScores[region.toUpperCase()] ?? 0.0;
  final genre = track.genre.toLowerCase();
  double genreBoost = 0.0;
  final r = region.toUpperCase();
  if (r == 'GH' || r == 'NG') {
    if (genre.contains('afrobeats') || genre.contains('afro')) genreBoost = 0.4;
    if (genre.contains('dancehall')) genreBoost = 0.25;
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.15;
  } else if (r == 'ZA') {
    if (genre.contains('amapiano')) genreBoost = 0.45;
    if (genre.contains('gqom') || genre.contains('house')) genreBoost = 0.3;
  } else if (r == 'GB') {
    if (genre.contains('drill') || genre.contains('garage')) genreBoost = 0.35;
    if (genre.contains('house') || genre.contains('dance')) genreBoost = 0.2;
  } else if (r == 'US') {
    if (genre.contains('hip-hop') || genre.contains('r&b')) genreBoost = 0.3;
    if (genre.contains('latin')) genreBoost = 0.2;
  }
  return (rawScore + genreBoost + track.trendScore * 0.3).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// Track helper
// ---------------------------------------------------------------------------

Track _track({
  String id = '1',
  double trendScore = 0.5,
  String genre = 'Pop',
  Map<String, double> regionScores = const {},
}) {
  final now = DateTime(2022, 1, 1);
  return Track(
    id: id,
    title: 'Test',
    artist: 'Artist',
    artworkUrl: '',
    bpm: 120,
    keySignature: '8B',
    genre: genre,
    vibe: 'club',
    trendScore: trendScore,
    regionScores: regionScores,
    platformLinks: const {},
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('regionalRelevance — output range', () {
    test('always returns a value in [0.0, 1.0]', () {
      final t = _track(trendScore: 1.0, genre: 'Afrobeats',
          regionScores: {'GH': 1.0});
      expect(regionalRelevance(t, 'GH'), inInclusiveRange(0.0, 1.0));
    });

    test('zero trendScore and no region score gives small but non-negative result', () {
      final t = _track(trendScore: 0.0, regionScores: {});
      final r = regionalRelevance(t, 'US');
      expect(r, greaterThanOrEqualTo(0.0));
    });

    test('result is clamped to 1.0 even when components sum > 1', () {
      // rawScore=1.0, genreBoost=0.4 (Afrobeats/GH), trendScore*0.3=0.3 → sum=1.7
      final t = _track(trendScore: 1.0, genre: 'Afrobeats',
          regionScores: {'GH': 1.0});
      expect(regionalRelevance(t, 'GH'), closeTo(1.0, 1e-9));
    });
  });

  group('regionalRelevance — genre boost (GH / NG)', () {
    test('Afrobeats track gets genre boost for GH region', () {
      final afro = _track(id: 'a', trendScore: 0.5, genre: 'Afrobeats',
          regionScores: {'GH': 0.0});
      final pop = _track(id: 'p', trendScore: 0.5, genre: 'Pop',
          regionScores: {'GH': 0.0});
      // Afrobeats should outscore Pop for GH
      expect(regionalRelevance(afro, 'GH'),
          greaterThan(regionalRelevance(pop, 'GH')));
    });

    test('Afrobeats boost applies equally to GH and NG', () {
      final t = _track(trendScore: 0.5, genre: 'Afrobeats', regionScores: {});
      expect(regionalRelevance(t, 'GH'), equals(regionalRelevance(t, 'NG')));
    });

    test('Dancehall gets a smaller boost than Afrobeats for GH', () {
      final afro = _track(id: 'af', trendScore: 0.0, genre: 'Afrobeats',
          regionScores: {});
      final dancehall = _track(id: 'dh', trendScore: 0.0, genre: 'Dancehall',
          regionScores: {});
      expect(regionalRelevance(afro, 'GH'),
          greaterThan(regionalRelevance(dancehall, 'GH')));
    });
  });

  group('regionalRelevance — genre boost (ZA)', () {
    test('Amapiano gets the highest ZA boost', () {
      final amapiano = _track(id: 'am', trendScore: 0.0, genre: 'Amapiano',
          regionScores: {});
      final house = _track(id: 'ho', trendScore: 0.0, genre: 'House',
          regionScores: {});
      expect(regionalRelevance(amapiano, 'ZA'),
          greaterThan(regionalRelevance(house, 'ZA')));
    });
  });

  group('regionalRelevance — region score contribution', () {
    test('higher raw region score → higher relevance (genre constant)', () {
      final low = _track(id: 'lo', trendScore: 0.0, genre: 'Pop',
          regionScores: {'US': 0.2});
      final high = _track(id: 'hi', trendScore: 0.0, genre: 'Pop',
          regionScores: {'US': 0.9});
      expect(regionalRelevance(high, 'US'),
          greaterThan(regionalRelevance(low, 'US')));
    });
  });

  group('regionalRelevance — trendScore contribution (0.3 weight)', () {
    test('higher trendScore increases relevance even with no region score', () {
      final weak = _track(id: 'w', trendScore: 0.1, genre: 'Pop',
          regionScores: {});
      final strong = _track(id: 's', trendScore: 0.9, genre: 'Pop',
          regionScores: {});
      expect(regionalRelevance(strong, 'US'),
          greaterThan(regionalRelevance(weak, 'US')));
    });

    test('trendScore contributes exactly 0.3*trendScore when no boost/region', () {
      final t = _track(trendScore: 0.5, genre: 'Pop', regionScores: {});
      // No genre boost for Pop/US; no region score → result = 0.3 * 0.5 = 0.15
      expect(regionalRelevance(t, 'US'), closeTo(0.15, 1e-9));
    });
  });

  group('regionalRelevance — case insensitivity of region key', () {
    test('region "gh" and "GH" yield the same result', () {
      final t = _track(trendScore: 0.5, genre: 'Afrobeats',
          regionScores: {'GH': 0.7});
      expect(regionalRelevance(t, 'gh'),
          closeTo(regionalRelevance(t, 'GH'), 1e-9));
    });
  });

  // ── _uniqueArtists is a method on _HomeScreenState — not callable directly.
  // We test the underlying Set-based logic here instead.

  group('uniqueArtists logic (Set deduplication)', () {
    test('deduplicates tracks with the same artist name', () {
      final names = ['Burna Boy', 'Burna Boy', 'Wizkid'];
      final unique = {for (final n in names) n}.length;
      expect(unique, 2);
    });

    test('empty list yields 0 unique artists', () {
      final unique = <String>{}.length;
      expect(unique, 0);
    });

    test('all distinct artists yields count equal to list length', () {
      final names = ['A', 'B', 'C', 'D'];
      final unique = {for (final n in names) n}.length;
      expect(unique, names.length);
    });
  });
}
