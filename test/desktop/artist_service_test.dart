// test/desktop/artist_service_test.dart
//
// Pure-logic tests for ArtistService.buildArtistCatalog / getArtist.
// No Flutter widgets; no Firebase; deterministic.

import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/services/artist_service.dart';

// ---------------------------------------------------------------------------
// Track helper — mirrors the pattern in scoring_engine_test.dart
// ---------------------------------------------------------------------------

Track _track({
  required String id,
  required String artist,
  String title = 'Test Track',
  double trendScore = 0.5,
  String genre = 'Afrobeats',
  String vibe = 'club',
  int bpm = 120,
  double energyLevel = 0.6,
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
    keySignature: '5A',
    genre: genre,
    vibe: vibe,
    trendScore: trendScore,
    regionScores: regionScores,
    platformLinks: platformLinks,
    createdAt: now,
    updatedAt: now,
    energyLevel: energyLevel,
    trendHistory: const [],
    sources: sources,
    releaseYear: releaseYear,
  );
}

void main() {
  final svc = ArtistService();

  // ── buildArtistCatalog ──────────────────────────────────────────────────────

  group('ArtistService.buildArtistCatalog', () {
    test('groups tracks by artist (case-sensitive key preserved)', () {
      final tracks = [
        _track(id: 'a1', artist: 'Burna Boy', trendScore: 0.8),
        _track(id: 'a2', artist: 'Burna Boy', trendScore: 0.6),
        _track(id: 'b1', artist: 'Wizkid', trendScore: 0.9),
      ];

      final catalog = svc.buildArtistCatalog(tracks);

      expect(catalog.length, 2);
      final names = catalog.map((a) => a.name).toSet();
      expect(names, containsAll(['Burna Boy', 'Wizkid']));

      final burna = catalog.firstWhere((a) => a.name == 'Burna Boy');
      expect(burna.trackCount, 2);
      expect(burna.allTracks.length, 2);
    });

    test('catalog is sorted by trendScore descending', () {
      final tracks = [
        _track(id: 'x1', artist: 'LowArtist', trendScore: 0.2),
        _track(id: 'x2', artist: 'HighArtist', trendScore: 0.95),
        _track(id: 'x3', artist: 'MidArtist', trendScore: 0.5),
      ];

      final catalog = svc.buildArtistCatalog(tracks);
      expect(catalog.map((a) => a.name).toList(),
          ['HighArtist', 'MidArtist', 'LowArtist']);
    });

    test('tracks with empty artist name are silently ignored', () {
      final tracks = [
        _track(id: 'z1', artist: '', trendScore: 0.7),
        _track(id: 'z2', artist: 'Known Artist', trendScore: 0.7),
      ];

      final catalog = svc.buildArtistCatalog(tracks);
      expect(catalog.length, 1);
      expect(catalog.single.name, 'Known Artist');
    });

    test('empty track list returns empty catalog', () {
      expect(svc.buildArtistCatalog([]), isEmpty);
    });
  });

  // ── genres aggregation ──────────────────────────────────────────────────────

  group('ArtistModel.genres — most common first', () {
    test('single genre fills genres list', () {
      final tracks = [
        _track(id: 'g1', artist: 'DJ A', genre: 'House'),
        _track(id: 'g2', artist: 'DJ A', genre: 'House'),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.genres, ['House']);
      expect(model.primaryGenre, 'House');
    });

    test('most common genre appears first', () {
      final tracks = [
        _track(id: 'g1', artist: 'DJ B', genre: 'House'),
        _track(id: 'g2', artist: 'DJ B', genre: 'House'),
        _track(id: 'g3', artist: 'DJ B', genre: 'Techno'),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.genres.first, 'House');
      expect(model.genres, contains('Techno'));
    });

    test('tracks with empty genre are excluded from genre list', () {
      final tracks = [
        _track(id: 'g4', artist: 'DJ C', genre: ''),
        _track(id: 'g5', artist: 'DJ C', genre: 'Afrobeats'),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.genres, ['Afrobeats']);
      expect(model.genres, isNot(contains('')));
    });
  });

  // ── BPM range ───────────────────────────────────────────────────────────────

  group('ArtistModel.bpmRange — 0-BPM tracks excluded', () {
    test('returns [min, max] when all tracks have BPM > 0', () {
      final tracks = [
        _track(id: 'b1', artist: 'Producer X', bpm: 100),
        _track(id: 'b2', artist: 'Producer X', bpm: 130),
        _track(id: 'b3', artist: 'Producer X', bpm: 115),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.bpmRange, [100, 130]);
      expect(model.hasBpmData, isTrue);
    });

    test('0-BPM tracks are excluded from range calculation', () {
      final tracks = [
        _track(id: 'b4', artist: 'Producer Y', bpm: 0),   // unknown
        _track(id: 'b5', artist: 'Producer Y', bpm: 110),
        _track(id: 'b6', artist: 'Producer Y', bpm: 125),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      // 0 must not appear in the range
      expect(model.bpmRange, [110, 125]);
      expect(model.hasBpmData, isTrue);
    });

    test('all 0-BPM yields empty bpmRange and hasBpmData == false', () {
      final tracks = [
        _track(id: 'b7', artist: 'Producer Z', bpm: 0),
        _track(id: 'b8', artist: 'Producer Z', bpm: 0),
      ];

      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.bpmRange, isEmpty);
      expect(model.hasBpmData, isFalse);
      expect(model.bpmRangeLabel, '—');
    });

    test('single-track artist with BPM gives range [bpm, bpm]', () {
      final tracks = [_track(id: 'b9', artist: 'Solo', bpm: 128)];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.bpmRange, [128, 128]);
    });
  });

  // ── lead region ─────────────────────────────────────────────────────────────

  group('ArtistModel.leadRegion', () {
    test('returns region with highest AVERAGE score across tracks', () {
      final tracks = [
        _track(id: 'r1', artist: 'Regional Act',
            regionScores: {'NG': 0.9, 'GH': 0.1}),
        _track(id: 'r2', artist: 'Regional Act',
            regionScores: {'NG': 0.7, 'GH': 0.6}),
      ];
      // NG avg = (0.9+0.7)/2 = 0.8, GH avg = (0.1+0.6)/2 = 0.35
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.leadRegion, 'NG');
    });

    test('returns "Global" when no track has region scores', () {
      final tracks = [
        _track(id: 'r3', artist: 'Global Act', regionScores: {}),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.leadRegion, 'Global');
    });
  });

  // ── hasBpmData convenience getter ───────────────────────────────────────────

  group('ArtistModel.hasBpmData', () {
    test('true when bpmRange has two positive entries', () {
      final tracks = [_track(id: 'hb1', artist: 'A', bpm: 100)];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.hasBpmData, isTrue);
    });

    test('false when bpmRange is empty', () {
      final tracks = [_track(id: 'hb2', artist: 'B', bpm: 0)];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.hasBpmData, isFalse);
    });
  });

  // ── trendScore (top-5 average) ──────────────────────────────────────────────

  group('ArtistModel.trendScore (top-5 avg)', () {
    test('equals the single track score for a one-track artist', () {
      final tracks = [_track(id: 't1', artist: 'Solo', trendScore: 0.75)];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.trendScore, closeTo(0.75, 0.001));
    });

    test('averages only the top-5 when there are more than 5 tracks', () {
      // 6 tracks: scores 0.1, 0.2, 0.3, 0.4, 0.5, 0.6
      // top-5: 0.6, 0.5, 0.4, 0.3, 0.2 → avg = 0.4
      final tracks = [
        for (var i = 1; i <= 6; i++)
          _track(id: 'ts$i', artist: 'Multi', trendScore: i * 0.1),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.trendScore, closeTo(0.4, 0.001));
    });
  });

  // ── trendingTracks (above artist average) ──────────────────────────────────

  group('ArtistModel.trendingTracks', () {
    test('only includes tracks above the artist average', () {
      final tracks = [
        _track(id: 'tt1', artist: 'DJ Trend', trendScore: 0.3),
        _track(id: 'tt2', artist: 'DJ Trend', trendScore: 0.7),
        _track(id: 'tt3', artist: 'DJ Trend', trendScore: 0.9),
      ];
      // avg = (0.3+0.7+0.9)/3 = 0.633
      final model = svc.buildArtistCatalog(tracks).single;
      final trendingIds = model.trendingTracks.map((t) => t.id).toSet();
      expect(trendingIds, contains('tt3'));
      expect(trendingIds, contains('tt2'));
      expect(trendingIds, isNot(contains('tt1')));
    });
  });

  // ── getArtist ───────────────────────────────────────────────────────────────

  group('ArtistService.getArtist', () {
    test('returns ArtistModel for a known artist (case-insensitive lookup)', () {
      final tracks = [
        _track(id: 'ga1', artist: 'Tiwa Savage', trendScore: 0.8),
        _track(id: 'ga2', artist: 'Tiwa Savage', trendScore: 0.6),
        _track(id: 'ga3', artist: 'Other Artist', trendScore: 0.5),
      ];

      final model = svc.getArtist('tiwa savage', tracks);
      expect(model, isNotNull);
      expect(model!.trackCount, 2);
    });

    test('returns null for an artist with no matching tracks', () {
      final tracks = [_track(id: 'ga4', artist: 'Wizkid', trendScore: 0.9)];
      final model = svc.getArtist('Burna Boy', tracks);
      expect(model, isNull);
    });
  });

  // ── collaborator extraction ─────────────────────────────────────────────────

  group('ArtistService collaborator extraction', () {
    test('collaborators from "feat." syntax are extracted', () {
      final tracks = [
        _track(id: 'c1', artist: 'Main Artist feat. Guest DJ'),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      // model is built for "Main Artist feat. Guest DJ" as the full artist key
      // collaborators should list "Guest DJ"
      expect(model.collaborators, contains('Guest DJ'));
    });

    test('no collaborators for a simple artist name', () {
      final tracks = [_track(id: 'c2', artist: 'Solo Artist')];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.collaborators, isEmpty);
      expect(model.hasCollaborators, isFalse);
    });
  });

  // ── era grouping ─────────────────────────────────────────────────────────────

  group('ArtistModel.tracksByEra', () {
    test('2020 release falls into "2020s" era', () {
      final tracks = [
        _track(id: 'e1', artist: 'Modern', releaseYear: 2022),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.tracksByEra.keys, contains('2020s'));
      expect(model.tracksByEra['2020s']!.first.id, 'e1');
    });

    test('1998 release falls into "Pre-2000" era', () {
      final tracks = [
        _track(id: 'e2', artist: 'Classic', releaseYear: 1998),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.tracksByEra.keys, contains('Pre-2000'));
    });

    test('tracks split across multiple eras are grouped correctly', () {
      final tracks = [
        _track(id: 'e3', artist: 'Veteran', releaseYear: 2005),
        _track(id: 'e4', artist: 'Veteran', releaseYear: 2015),
        _track(id: 'e5', artist: 'Veteran', releaseYear: 2023),
      ];
      final model = svc.buildArtistCatalog(tracks).single;
      expect(model.tracksByEra.keys,
          containsAll(['2000s', '2010s', '2020s']));
    });
  });
}
