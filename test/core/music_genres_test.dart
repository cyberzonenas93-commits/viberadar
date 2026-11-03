import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/config/music_genres.dart';

void main() {
  group('music genre catalog', () {
    test('filter options expose broad DJ and regional genres', () {
      expect(kGenreFilterOptions.first, 'All');
      expect(
        kGenreFilterOptions,
        containsAll([
          'Afrobeats',
          'Amapiano',
          'Highlife',
          'Soca',
          'Baile Funk',
          'Hip-Hop',
          'R&B',
          'House',
          'Techno',
          'Drum & Bass',
          'Reggaeton',
          'Country',
          'Gospel',
        ]),
      );
    });

    test(
      'mergedGenreOptions keeps canonical order and appends custom genres',
      () {
        final genres = mergedGenreOptions([
          'Afrobeats',
          'Other',
          'Hyperpop',
          'hip hop',
          'Alté',
        ]);

        expect(genres.take(4), ['All', 'Afrobeats', 'Afrobeat', 'Afro-Pop']);
        expect(genres.where((genre) => genre == 'Afrobeats'), hasLength(1));
        expect(genres, containsAll(['Alté', 'Hyperpop']));
        expect(genres.indexOf('Alté'), lessThan(genres.indexOf('Hyperpop')));
        expect(genres, isNot(contains('hip hop')));
      },
    );
  });

  group('genreMatches', () {
    test('All / empty selection matches everything', () {
      expect(genreMatches('House', 'All'), isTrue);
      expect(genreMatches(null, 'All'), isTrue);
      expect(genreMatches('Other', 'All'), isTrue);
      expect(genreMatches('Afrobeats', ''), isTrue);
    });

    test('compound platform labels match canonical selections', () {
      expect(genreMatches('Hip-Hop/Rap', 'Hip-Hop'), isTrue);
      expect(genreMatches('R&B/Soul', 'R&B'), isTrue);
      expect(genreMatches('Dance/Electronic', 'Dance'), isTrue);
    });

    test('separator, case, and plural differences still match', () {
      expect(genreMatches('afro house', 'Afro-House'), isTrue);
      expect(genreMatches('AMAPIANO', 'Amapiano'), isTrue);
      expect(genreMatches('Afrobeat', 'Afrobeats'), isTrue);
    });

    test('subgenre matches a selected parent genre', () {
      expect(genreMatches('Deep House', 'House'), isTrue);
      expect(genreMatches('Tech House', 'House'), isTrue);
    });

    test('unknown track never matches a specific genre', () {
      expect(genreMatches('Other', 'House'), isFalse);
      expect(genreMatches(null, 'House'), isFalse);
      expect(genreMatches('', 'House'), isFalse);
    });

    test('unrelated genres do not match', () {
      expect(genreMatches('Afrobeats', 'House'), isFalse);
      expect(genreMatches('Country', 'Hip-Hop'), isFalse);
    });
  });

  group('canonicalGenre', () {
    test('maps messy platform labels to canonical buckets', () {
      // 'Hip-Hop/Rap' is itself a catalog entry, so it is preserved exactly;
      // 'R&B/Soul' is not, so it collapses to its 'R&B' family bucket.
      expect(canonicalGenre('Hip-Hop/Rap'), 'Hip-Hop/Rap');
      expect(canonicalGenre('R&B/Soul'), 'R&B');
      expect(canonicalGenre('afrobeats'), 'Afrobeats');
    });

    test('unknown / blank becomes Other', () {
      expect(canonicalGenre(null), 'Other');
      expect(canonicalGenre('   '), 'Other');
    });

    test('unrecognized but real genre is preserved', () {
      expect(canonicalGenre('Hyperpop'), 'Hyperpop');
    });

    test('isSpecificGenre distinguishes real lanes from All/unknown', () {
      expect(isSpecificGenre('House'), isTrue);
      expect(isSpecificGenre('All'), isFalse);
      expect(isSpecificGenre('Other'), isFalse);
      expect(isSpecificGenre(null), isFalse);
      expect(isSpecificGenre('House, Afrobeats'), isFalse);
    });
  });

  group('appleGenreFor', () {
    test('maps the house family to Apple Dance (17)', () {
      expect(appleGenreFor('House')?.id, 17);
      expect(appleGenreFor('Deep House')?.id, 17);
      expect(appleGenreFor('Techno')?.id, 17);
    });

    test('maps the hip-hop family to 18', () {
      expect(appleGenreFor('Hip-Hop')?.id, 18);
      expect(appleGenreFor('Trap')?.id, 18);
    });

    test('maps Dancehall to its Apple parent Reggae (24)', () {
      expect(appleGenreFor('Dancehall')?.id, 24);
    });

    test('Amapiano uses id 42 with a South African preferred storefront', () {
      final mapping = appleGenreFor('Amapiano');
      expect(mapping?.id, 42);
      expect(mapping?.preferredStorefronts, contains('za'));
    });

    test('Afrobeats uses id 100051 with a Nigerian preferred storefront', () {
      final mapping = appleGenreFor('Afrobeats');
      expect(mapping?.id, 100051);
      expect(mapping?.preferredStorefronts, contains('ng'));
    });

    test('global genres carry no preferred storefront', () {
      expect(appleGenreFor('Pop')?.id, 14);
      expect(appleGenreFor('Pop')?.preferredStorefronts, isEmpty);
    });

    test('returns null for All / Open Format / unmapped / null lanes', () {
      expect(appleGenreFor('All'), isNull);
      expect(appleGenreFor('Open Format'), isNull);
      expect(appleGenreFor('Disco'), isNull);
      expect(appleGenreFor(null), isNull);
    });
  });
}
