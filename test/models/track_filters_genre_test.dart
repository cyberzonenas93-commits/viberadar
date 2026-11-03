import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/track_filters.dart';

Track _track({required String genre, double trendScore = 0.7}) {
  final now = DateTime(2026, 1, 1);
  return Track(
    id: 'id-$genre',
    title: 'Song',
    artist: 'Artist',
    artworkUrl: '',
    bpm: 0,
    keySignature: '--',
    genre: genre,
    vibe: 'club',
    trendScore: trendScore,
    regionScores: const {'US': 0.7},
    platformLinks: const {},
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.6,
    trendHistory: const [],
    sources: const [],
  );
}

void main() {
  group('TrackFilters genre matching', () {
    test('All keeps every genre', () {
      const filters = TrackFilters(genre: 'All');
      expect(filters.matches(_track(genre: 'Other')), isTrue);
      expect(filters.matches(_track(genre: 'House')), isTrue);
    });

    test('matches compound and family genre labels tolerantly', () {
      const filters = TrackFilters(genre: 'Hip-Hop');
      expect(filters.matches(_track(genre: 'Hip-Hop/Rap')), isTrue);

      const house = TrackFilters(genre: 'House');
      expect(house.matches(_track(genre: 'Deep House')), isTrue);
    });

    test('excludes clearly off-genre tracks', () {
      const filters = TrackFilters(genre: 'House');
      expect(filters.matches(_track(genre: 'Country')), isFalse);
      expect(filters.matches(_track(genre: 'Other')), isFalse);
    });
  });
}
