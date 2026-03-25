import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/greatest_of_result.dart';
import '../models/track.dart';
import '../services/greatest_of_service.dart';
import 'app_state.dart';

final greatestOfServiceProvider =
    Provider<GreatestOfService>((ref) => GreatestOfService());

/// 'artist' or 'genre'
final greatestOfModeProvider =
    StateProvider<String>((ref) => 'artist');

final greatestOfArtistFilterProvider =
    StateProvider<String>((ref) => 'Burna Boy');

final greatestOfGenreFilterProvider =
    StateProvider<String?>((ref) => null);

final greatestOfResultsProvider = Provider<List<GreatestOfResult>>((ref) {
  final service = ref.watch(greatestOfServiceProvider);
  final tracks =
      ref.watch(trackStreamProvider).value ?? const <Track>[];
  final mode = ref.watch(greatestOfModeProvider);
  final artist = ref.watch(greatestOfArtistFilterProvider);
  final genre = ref.watch(greatestOfGenreFilterProvider);

  if (mode == 'artist') return service.computeForArtist(artist, tracks);
  if (genre != null) return service.computeForGenre(genre, tracks);
  return const [];
});
