import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/artist_repository.dart';
import '../data/sources/mock_artist_seed.dart';
import '../models/artist.dart';

final artistRepositoryProvider = Provider<ArtistRepository>((ref) {
  return ArtistRepository(buildMockArtists());
});

final artistSearchQueryProvider = StateProvider<String>((ref) => '');
final selectedArtistIdProvider = StateProvider<String?>((ref) => null);

final filteredArtistsProvider = Provider<List<Artist>>((ref) {
  final repo = ref.watch(artistRepositoryProvider);
  final query = ref.watch(artistSearchQueryProvider);
  if (query.isEmpty) return repo.getTrending(limit: 50);
  return repo.search(query);
});
