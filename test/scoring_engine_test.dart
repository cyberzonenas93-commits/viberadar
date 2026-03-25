import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/trend_point.dart';

Track _track({
  String id = '1',
  double trendScore = 0.75,
  List<TrendPoint> trendHistory = const [],
  Map<String, double> regionScores = const {},
  double energyLevel = 0.6,
  String genre = 'Afrobeats',
  String vibe = 'club',
  int bpm = 102,
}) =>
    Track(
      id: id,
      title: 'Test Track',
      artist: 'Test Artist',
      artworkUrl: '',
      bpm: bpm,
      keySignature: '5A',
      genre: genre,
      vibe: vibe,
      trendScore: trendScore,
      regionScores: regionScores,
      platformLinks: const {},
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      energyLevel: energyLevel,
      trendHistory: trendHistory,
    );

TrendPoint _pt(String label, double score) =>
    TrendPoint(label: label, score: score);

void main() {
  group('Track.isRisingFast', () {
    test('returns true when trendScore > 0.82 with no history', () {
      final t = _track(trendScore: 0.90, trendHistory: []);
      expect(t.isRisingFast, isTrue);
    });

    test('returns false when trendScore <= 0.82 with no history', () {
      final t = _track(trendScore: 0.70, trendHistory: []);
      expect(t.isRisingFast, isFalse);
    });

    test('returns true when delta >= 0.18 over trend history', () {
      final t = _track(
        trendScore: 0.78,
        trendHistory: [_pt('Week 1', 0.55), _pt('Week 2', 0.78)],
      );
      // delta = 0.78 - 0.55 = 0.23 >= 0.18
      expect(t.isRisingFast, isTrue);
    });

    test('returns false when delta < 0.18 and score < 0.84', () {
      final t = _track(
        trendScore: 0.65,
        trendHistory: [_pt('Week 1', 0.58), _pt('Week 2', 0.65)],
      );
      // delta = 0.07, score = 0.65 — neither threshold met
      expect(t.isRisingFast, isFalse);
    });

    test('returns true when trendScore >= 0.84 even with modest delta', () {
      final t = _track(
        trendScore: 0.85,
        trendHistory: [_pt('Week 1', 0.80), _pt('Week 2', 0.85)],
      );
      // delta = 0.05, but score >= 0.84
      expect(t.isRisingFast, isTrue);
    });

    test('single history point falls back to score-only check', () {
      final rising = _track(trendScore: 0.90, trendHistory: [_pt('W1', 0.90)]);
      final flat = _track(trendScore: 0.60, trendHistory: [_pt('W1', 0.60)]);
      expect(rising.isRisingFast, isTrue);
      expect(flat.isRisingFast, isFalse);
    });
  });

  group('Track.leadRegion', () {
    test('returns the region with the highest score', () {
      final t = _track(regionScores: {'US': 0.7, 'NG': 0.92, 'GB': 0.55});
      expect(t.leadRegion, 'NG');
    });

    test('returns Global when regionScores is empty', () {
      final t = _track(regionScores: {});
      expect(t.leadRegion, 'Global');
    });

    test('single region returns that region', () {
      final t = _track(regionScores: {'GH': 0.85});
      expect(t.leadRegion, 'GH');
    });

    test('handles tied scores by returning whichever comes first in sorted order', () {
      final t = _track(regionScores: {'US': 0.8, 'ZA': 0.8});
      // Both have 0.8 — leadRegion should be one of them (not crash)
      expect(['US', 'ZA'], contains(t.leadRegion));
    });
  });

  group('Trend score range validation', () {
    test('trendScore is parsed from Firestore map correctly', () {
      final map = {
        'id': 'x',
        'title': 'T',
        'artist': 'A',
        'artwork_url': '',
        'bpm': 128,
        'key': '1A',
        'genre': 'House',
        'vibe': 'club',
        'trend_score': 0.91,
        'region_scores': {'US': 0.91},
        'platform_links': <String, dynamic>{},
        'created_at': null,
        'updated_at': null,
        'energy_level': 0.8,
        'trend_history': <Map<String, dynamic>>[],
      };
      final t = Track.fromMap(map);
      expect(t.trendScore, closeTo(0.91, 0.001));
    });

    test('missing trend_score defaults to 0', () {
      final map = <String, dynamic>{
        'title': 'T',
        'artist': 'A',
        'artwork_url': '',
        'bpm': 100,
        'key': '2B',
        'genre': 'R&B',
        'vibe': 'chill',
        'region_scores': <String, dynamic>{},
        'platform_links': <String, dynamic>{},
        'created_at': null,
        'updated_at': null,
        'energy_level': 0.4,
        'trend_history': <Map<String, dynamic>>[],
      };
      final t = Track.fromMap(map);
      expect(t.trendScore, 0.0);
    });

    test('tracks with score 0 are not considered rising fast', () {
      final t = _track(trendScore: 0.0, trendHistory: []);
      expect(t.isRisingFast, isFalse);
    });

    test('tracks with score 1.0 are considered rising fast', () {
      final t = _track(trendScore: 1.0, trendHistory: []);
      expect(t.isRisingFast, isTrue);
    });
  });
}
