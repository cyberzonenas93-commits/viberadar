import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/services/live_track_catalog_service.dart';

class _RecordingCatalog extends LiveTrackCatalogService {
  String? seenRegion;
  String? seenGenre;

  @override
  Future<List<Track>> fetchTrendingTracks({
    required String region,
    String? genre,
    int limit = 100,
  }) async {
    seenRegion = region;
    seenGenre = genre;
    return const <Track>[];
  }
}

void main() {
  test(
    'trackStreamProvider fetches the catalog with the selected genre lane',
    () async {
      final catalog = _RecordingCatalog();
      final container = ProviderContainer(
        overrides: [
          liveCatalogAccessProvider.overrideWithValue(LiveCatalogAccess.pro),
          liveTrackCatalogServiceProvider.overrideWithValue(catalog),
        ],
      );
      addTearDown(container.dispose);

      container.read(selectedRegionProvider.notifier).set('US');
      container.read(selectedGenreProvider.notifier).set('House');

      // Activating the provider builds the stream, which invokes the catalog
      // fetch synchronously and captures the criteria it was given.
      container.listen(trackStreamProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      expect(catalog.seenRegion, 'US');
      expect(catalog.seenGenre, 'House');
    },
  );

  test('selectedGenreProvider defaults to no lane (All)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(selectedGenreProvider), isNull);
  });
}
