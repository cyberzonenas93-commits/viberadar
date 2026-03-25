import '../../models/artist.dart';

class ArtistRepository {
  ArtistRepository(this._artists);

  final List<Artist> _artists;

  List<Artist> getAll() => List.unmodifiable(_artists);

  List<Artist> search(String query) {
    final q = query.toLowerCase();
    return _artists
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.genres.any((g) => g.toLowerCase().contains(q)))
        .toList();
  }

  Artist? findById(String id) {
    try {
      return _artists.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Artist> getByGenre(String genre) {
    final q = genre.toLowerCase();
    return _artists
        .where((a) => a.genres.any((g) => g.toLowerCase().contains(q)))
        .toList();
  }

  List<Artist> getTrending({int limit = 10}) {
    final sorted = List<Artist>.from(_artists)
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));
    return sorted.take(limit).toList();
  }
}
