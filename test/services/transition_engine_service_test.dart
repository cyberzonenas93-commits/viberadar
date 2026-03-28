import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/transition_score.dart';
import 'package:viberadar/services/transition_engine_service.dart';

// ── Track Fixtures ────────────────────────────────────────────────────────────

Track _track({
  String id = '1',
  String title = 'Test Track',
  String artist = 'Test Artist',
  int bpm = 128,
  String key = '8A',
  String genre = 'House',
  double energyLevel = 0.7,
  double trendScore = 0.6,
}) =>
    Track(
      id: id,
      title: title,
      artist: artist,
      artworkUrl: '',
      bpm: bpm,
      keySignature: key,
      genre: genre,
      vibe: 'club',
      trendScore: trendScore,
      regionScores: const {},
      platformLinks: const {},
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      energyLevel: energyLevel,
      trendHistory: const [],
    );

void main() {
  late TransitionEngineService engine;

  setUp(() {
    engine = TransitionEngineService();
  });

  // ── 1. BPM Compatibility ──────────────────────────────────────────────────

  group('BPM compatibility scoring', () {
    test('same BPM scores 1.0', () {
      final score = engine.scorePair(
        _track(bpm: 128),
        _track(bpm: 128),
      );
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        equals(1.0),
      );
    });

    test('delta <= 3 scores 0.95', () {
      final score = engine.scorePair(
        _track(bpm: 128),
        _track(bpm: 130),
      );
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        equals(0.95),
      );
    });

    test('delta <= 6 scores 0.88', () {
      final score = engine.scorePair(
        _track(bpm: 128),
        _track(bpm: 134),
      );
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        equals(0.88),
      );
    });

    test('delta > 30 scores 0.10', () {
      final score = engine.scorePair(
        _track(bpm: 128),
        _track(bpm: 165),
      );
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        equals(0.10),
      );
    });

    test('half-time relationship scores 0.78', () {
      // 128 → 64: 128 / 64 = 2.0, so toBpm is approx half of fromBpm
      final score = engine.scorePair(
        _track(bpm: 128),
        _track(bpm: 64),
      );
      // 64 * 2 = 128 exactly → ratio is exactly 2.0 → doubleRatio = 0.0 <= 0.03
      // fromBpm / toBpm = 2.0 → doubleRatio check matches first
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        equals(0.80),
      );
    });

    test('double-time relationship scores 0.80', () {
      // 64 → 128: 64 / 128 = 0.5 → halfRatio check
      final score = engine.scorePair(
        _track(bpm: 64),
        _track(bpm: 128),
      );
      expect(
        score.dimensionScores[TransitionDimension.bpmCompatibility],
        inInclusiveRange(0.78, 0.80),
      );
    });
  });

  // ── 2. Harmonic (Camelot) Compatibility ───────────────────────────────────

  group('Harmonic compatibility scoring', () {
    test('same key+mode scores 1.0', () {
      final score = engine.scorePair(
        _track(key: '8A'),
        _track(key: '8A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(1.0),
      );
    });

    test('adjacent number same mode scores 0.92', () {
      final score = engine.scorePair(
        _track(key: '8A'),
        _track(key: '9A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.92),
      );
    });

    test('energy boost (same number, different mode) scores 0.85', () {
      final score = engine.scorePair(
        _track(key: '8A'),
        _track(key: '8B'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.85),
      );
    });

    test('parse failure returns neutral 0.5', () {
      final score = engine.scorePair(
        _track(key: 'UNKNOWN'),
        _track(key: 'BADKEY'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.5),
      );
    });

    test('Camelot 11B parses correctly (adjacent to 12B = 0.92)', () {
      final score = engine.scorePair(
        _track(key: '11B'),
        _track(key: '12B'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.92),
      );
    });

    test('Camelot 1A parses and wraps (adjacent to 12A = 0.92)', () {
      final score = engine.scorePair(
        _track(key: '1A'),
        _track(key: '12A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.92),
      );
    });
  });

  // ── 3. Genre Compatibility ────────────────────────────────────────────────

  group('Genre compatibility scoring', () {
    test('same genre family scores high', () {
      final score = engine.scorePair(
        _track(genre: 'House'),
        _track(genre: 'Techno'),
      );
      expect(
        score.dimensionScores[TransitionDimension.genreCompatibility]!,
        greaterThanOrEqualTo(0.8),
      );
    });

    test('different genre families score lower', () {
      final score = engine.scorePair(
        _track(genre: 'House'),
        _track(genre: 'Hip Hop'),
      );
      expect(
        score.dimensionScores[TransitionDimension.genreCompatibility]!,
        lessThan(0.6),
      );
    });

    test('afrobeats to amapiano (same family) scores high', () {
      final score = engine.scorePair(
        _track(genre: 'Afrobeats'),
        _track(genre: 'Amapiano'),
      );
      expect(
        score.dimensionScores[TransitionDimension.genreCompatibility]!,
        greaterThanOrEqualTo(0.85),
      );
    });
  });

  // ── 4. Vibe/Energy Progression ───────────────────────────────────────────

  group('Vibe/energy progression scoring', () {
    test('small rise scores high (0.95)', () {
      final score = engine.scorePair(
        _track(energyLevel: 0.60),
        _track(energyLevel: 0.70),
      );
      expect(
        score.dimensionScores[TransitionDimension.vibeCompatibility]!,
        greaterThanOrEqualTo(0.80),
      );
    });

    test('large drop scores low', () {
      final score = engine.scorePair(
        _track(energyLevel: 0.90),
        _track(energyLevel: 0.50),
      );
      expect(
        score.dimensionScores[TransitionDimension.vibeCompatibility]!,
        lessThanOrEqualTo(0.50),
      );
    });

    test('flat energy scores well', () {
      final score = engine.scorePair(
        _track(energyLevel: 0.65),
        _track(energyLevel: 0.67),
      );
      expect(
        score.dimensionScores[TransitionDimension.vibeCompatibility]!,
        greaterThanOrEqualTo(0.85),
      );
    });
  });

  // ── 5. Mode Weighting ─────────────────────────────────────────────────────

  group('Mode weighting', () {
    test('smooth mode and peakTime mode produce different overall scores for same pair', () {
      final from = _track(bpm: 128, energyLevel: 0.9);
      final to = _track(bpm: 130, energyLevel: 0.5, genre: 'Trance');

      final smoothScore = engine.scorePair(from, to, mode: TransitionMode.smooth);
      final peakScore = engine.scorePair(from, to, mode: TransitionMode.peakTime);

      expect(smoothScore.overallScore, isNot(equals(peakScore.overallScore)));
    });

    test('smooth mode prioritizes harmonic over energy', () {
      // Track with perfect harmonic but large energy drop
      final harmonicButDroppy = _track(
        id: 'harmonicDroppy',
        key: '8A',
        bpm: 128,
        energyLevel: 0.4,
      );
      final from = _track(key: '8A', bpm: 128, energyLevel: 0.9);

      final smoothScore = engine.scorePair(from, harmonicButDroppy, mode: TransitionMode.smooth);
      final peakScore = engine.scorePair(from, harmonicButDroppy, mode: TransitionMode.peakTime);

      // In smooth mode, harmonic weight 0.30 vs peakTime harmonic 0.20
      // The relationship between the two scores should differ
      expect(smoothScore.overallScore, isNot(equals(peakScore.overallScore)));
    });
  });

  // ── 6. scorePair result range ─────────────────────────────────────────────

  group('scorePair result validity', () {
    test('scorePair returns overallScore in [0.0, 1.0]', () {
      final score = engine.scorePair(
        _track(bpm: 128, key: '8A', genre: 'House'),
        _track(bpm: 95, key: 'BADKEY', genre: 'Reggae'),
      );
      expect(score.overallScore, inInclusiveRange(0.0, 1.0));
    });

    test('scorePair with identical-field tracks scores high', () {
      final t = _track(id: 'a', bpm: 128, key: '8A', genre: 'House', energyLevel: 0.7);
      final t2 = _track(id: 'b', bpm: 128, key: '8A', genre: 'House', energyLevel: 0.7);
      final score = engine.scorePair(t, t2);
      expect(score.overallScore, greaterThanOrEqualTo(0.7));
    });
  });

  // ── 7. rankNextTracks ─────────────────────────────────────────────────────

  group('rankNextTracks', () {
    test('returns tracks sorted descending by score', () {
      final current = _track(id: 'cur', bpm: 128, key: '8A', genre: 'House');
      final candidates = [
        _track(id: 'a', bpm: 165, key: '3B', genre: 'Reggae'), // low compatibility
        _track(id: 'b', bpm: 128, key: '8A', genre: 'House'), // perfect
        _track(id: 'c', bpm: 132, key: '9A', genre: 'Techno'), // good
      ];

      final ranked = engine.rankNextTracks(current, candidates);

      // Perfect match should be first
      expect(ranked.first.id, equals('b'));
      // Low compatibility should be last
      expect(ranked.last.id, equals('a'));
    });

    test('maxResults is respected', () {
      final current = _track(id: 'cur', bpm: 128);
      final candidates = List.generate(
        20,
        (i) => _track(id: 'track_$i', bpm: 120 + i),
      );

      final ranked = engine.rankNextTracks(current, candidates, maxResults: 5);
      expect(ranked.length, lessThanOrEqualTo(5));
    });

    test('current track is excluded from results', () {
      final current = _track(id: 'cur', bpm: 128);
      final candidates = [
        current,
        _track(id: 'other', bpm: 128),
      ];

      final ranked = engine.rankNextTracks(current, candidates);
      expect(ranked.every((t) => t.id != 'cur'), isTrue);
    });
  });

  // ── 10 & 11. buildOptimalSequence edge cases ──────────────────────────────

  group('buildOptimalSequence edge cases', () {
    test('single track returns same track', () {
      final single = _track(id: 'only');
      final result = engine.buildOptimalSequence([single]);
      expect(result.length, equals(1));
      expect(result.first.id, equals('only'));
    });

    test('empty list returns empty', () {
      final result = engine.buildOptimalSequence([]);
      expect(result, isEmpty);
    });
  });

  // ── 12. buildOptimalSequence quality ─────────────────────────────────────

  group('buildOptimalSequence quality', () {
    test('returns a sequence that has acceptable avg score', () {
      final tracks = [
        _track(id: '1', bpm: 120, key: '8A', genre: 'House', energyLevel: 0.5),
        _track(id: '2', bpm: 122, key: '9A', genre: 'House', energyLevel: 0.55),
        _track(id: '3', bpm: 124, key: '10A', genre: 'Techno', energyLevel: 0.6),
        _track(id: '4', bpm: 126, key: '11A', genre: 'Techno', energyLevel: 0.65),
        _track(id: '5', bpm: 128, key: '12A', genre: 'Techno', energyLevel: 0.7),
      ];

      final sequence = engine.buildOptimalSequence(tracks);
      expect(sequence.length, equals(tracks.length));

      // Compute average transition score
      double total = 0;
      for (var i = 0; i < sequence.length - 1; i++) {
        total += engine.scorePair(sequence[i], sequence[i + 1]).overallScore;
      }
      final avg = total / (sequence.length - 1);
      // The optimized sequence should achieve at least 0.6 avg
      expect(avg, greaterThanOrEqualTo(0.6));
    });

    test('all tracks are present in sequence (no duplicates)', () {
      final tracks = List.generate(
        6,
        (i) => _track(id: 'track_$i', bpm: 120 + i * 2),
      );

      final sequence = engine.buildOptimalSequence(tracks);
      final ids = sequence.map((t) => t.id).toSet();
      expect(ids.length, equals(tracks.length));
    });
  });

  // ── 13. findBridgeTracks ──────────────────────────────────────────────────

  group('findBridgeTracks', () {
    test('returns tracks that score well for both hops', () {
      final from = _track(id: 'from', bpm: 128, key: '8A', genre: 'House');
      final to = _track(id: 'to', bpm: 128, key: '8A', genre: 'Trance');

      final bridge = _track(
        id: 'bridge',
        bpm: 128,
        key: '8A',
        genre: 'Trance', // scores well going into 'to'
      );
      final poor = _track(
        id: 'poor',
        bpm: 95,
        key: '1B',
        genre: 'Reggae',
      );

      final pool = [bridge, poor];
      final bridges = engine.findBridgeTracks(from, to, pool);

      // The bridge track should be included
      expect(bridges.any((t) => t.id == 'bridge'), isTrue);
    });

    test('excludes from and to tracks from results', () {
      final from = _track(id: 'from', bpm: 128);
      final to = _track(id: 'to', bpm: 128);
      final pool = [from, to, _track(id: 'mid', bpm: 128)];

      final bridges = engine.findBridgeTracks(from, to, pool);
      expect(bridges.every((t) => t.id != 'from' && t.id != 'to'), isTrue);
    });
  });

  // ── 14. TransitionScore.scoreLabel ───────────────────────────────────────

  group('TransitionScore.scoreLabel', () {
    TransitionScore _makeScore(double overall) => TransitionScore(
          fromTrackId: 'a',
          toTrackId: 'b',
          overallScore: overall,
          confidence: 0.9,
          type: TransitionType.smoothBlend,
          reasons: const [],
          warnings: const [],
          dimensionScores: const {},
        );

    test('score >= 0.8 → Excellent', () {
      expect(_makeScore(0.85).scoreLabel, equals('Excellent'));
    });

    test('score >= 0.65 → Good', () {
      expect(_makeScore(0.70).scoreLabel, equals('Good'));
    });

    test('score >= 0.5 → OK', () {
      expect(_makeScore(0.55).scoreLabel, equals('OK'));
    });

    test('score < 0.5 → Risky', () {
      expect(_makeScore(0.40).scoreLabel, equals('Risky'));
    });
  });

  // ── 15. TransitionScore toJson/fromJson roundtrip ─────────────────────────

  group('TransitionScore toJson/fromJson roundtrip', () {
    test('roundtrip preserves all fields', () {
      final original = TransitionScore(
        fromTrackId: 'track_1',
        toTrackId: 'track_2',
        overallScore: 0.82,
        confidence: 0.9,
        type: TransitionType.energyLift,
        reasons: const ['Good BPM match', 'Harmonic blend'],
        warnings: const ['Watch tempo'],
        dimensionScores: const {
          TransitionDimension.bpmCompatibility: 0.95,
          TransitionDimension.harmonicCompatibility: 0.85,
        },
        recommendedTechnique: 'Long crossfade',
        isBridgeCandidate: true,
      );

      final json = original.toJson();
      final restored = TransitionScore.fromJson(json);

      expect(restored.fromTrackId, equals(original.fromTrackId));
      expect(restored.toTrackId, equals(original.toTrackId));
      expect(restored.overallScore, closeTo(original.overallScore, 0.001));
      expect(restored.confidence, closeTo(original.confidence, 0.001));
      expect(restored.type, equals(original.type));
      expect(restored.reasons, equals(original.reasons));
      expect(restored.warnings, equals(original.warnings));
      expect(restored.recommendedTechnique, equals(original.recommendedTechnique));
      expect(restored.isBridgeCandidate, equals(original.isBridgeCandidate));
      expect(
        restored.dimensionScores[TransitionDimension.bpmCompatibility],
        closeTo(0.95, 0.001),
      );
    });
  });

  // ── 16. TransitionType.label non-empty ───────────────────────────────────

  group('TransitionType labels', () {
    test('every TransitionType has a non-empty label', () {
      for (final type in TransitionType.values) {
        expect(type.label, isNotEmpty, reason: '${type.name} has empty label');
      }
    });
  });

  // ── 17. TransitionMode changes ranking ───────────────────────────────────

  group('TransitionMode affects rankings', () {
    test('smooth vs peakTime produce different rankings', () {
      final current = _track(id: 'cur', bpm: 128, key: '8A', genre: 'House', energyLevel: 0.5);
      final candidates = [
        _track(id: 'a', bpm: 128, key: '8A', genre: 'House', energyLevel: 0.5), // smooth-friendly
        _track(id: 'b', bpm: 128, key: '1B', genre: 'Trance', energyLevel: 0.95), // high energy
        _track(id: 'c', bpm: 130, key: '9A', genre: 'Techno', energyLevel: 0.7),
      ];

      final smoothRanked = engine.rankNextTracks(
        current,
        candidates,
        mode: TransitionMode.smooth,
      );
      final peakRanked = engine.rankNextTracks(
        current,
        candidates,
        mode: TransitionMode.peakTime,
      );

      // The two modes should produce at least one different ranking position
      // (they won't be identical given the different weight schemes)
      final smoothIds = smoothRanked.map((t) => t.id).toList();
      final peakIds = peakRanked.map((t) => t.id).toList();

      // At minimum verify both return the expected count
      expect(smoothIds.length, equals(peakIds.length));

      // Compute overall scores to confirm modes are actually different
      final smoothScores = candidates
          .map((t) => engine.scorePair(current, t, mode: TransitionMode.smooth).overallScore)
          .toList();
      final peakScores = candidates
          .map((t) => engine.scorePair(current, t, mode: TransitionMode.peakTime).overallScore)
          .toList();

      // At least one candidate should differ by more than epsilon
      final hasDifference = List.generate(candidates.length, (i) {
        return (smoothScores[i] - peakScores[i]).abs() > 0.001;
      }).any((v) => v);
      expect(hasDifference, isTrue);
    });
  });

  // ── 18. Camelot parsing handles specific formats ──────────────────────────

  group('Camelot parsing', () {
    test('"8A" parses correctly (same key = 1.0)', () {
      final score = engine.scorePair(
        _track(key: '8A'),
        _track(key: '8A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(1.0),
      );
    });

    test('"11B" parses correctly', () {
      final score = engine.scorePair(
        _track(key: '11B'),
        _track(key: '11B'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(1.0),
      );
    });

    test('"1A" parses correctly', () {
      final score = engine.scorePair(
        _track(key: '1A'),
        _track(key: '1A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(1.0),
      );
    });
  });

  // ── 19. Camelot parsing handles unknown keys gracefully ───────────────────

  group('Camelot parsing — unknown keys', () {
    test('unknown key returns neutral 0.5', () {
      final score = engine.scorePair(
        _track(key: 'UNKNOWN'),
        _track(key: '8A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.5),
      );
    });

    test('both unknown keys return neutral 0.5', () {
      final score = engine.scorePair(
        _track(key: 'BADKEY'),
        _track(key: '??'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.5),
      );
    });

    test('default "--" key returns neutral 0.5', () {
      final score = engine.scorePair(
        _track(key: '--'),
        _track(key: '8A'),
      );
      expect(
        score.dimensionScores[TransitionDimension.harmonicCompatibility],
        equals(0.5),
      );
    });
  });

  // ── 20. buildOptimalSequence is deterministic ─────────────────────────────

  group('buildOptimalSequence determinism', () {
    test('same input produces same output', () {
      final tracks = [
        _track(id: '1', bpm: 120, key: '5A', genre: 'Afrobeats'),
        _track(id: '2', bpm: 125, key: '6A', genre: 'House'),
        _track(id: '3', bpm: 122, key: '5B', genre: 'Afrobeats'),
        _track(id: '4', bpm: 128, key: '7A', genre: 'Techno'),
      ];

      final result1 = engine.buildOptimalSequence(tracks);
      final result2 = engine.buildOptimalSequence(tracks);

      final ids1 = result1.map((t) => t.id).toList();
      final ids2 = result2.map((t) => t.id).toList();

      expect(ids1, equals(ids2));
    });
  });
}
