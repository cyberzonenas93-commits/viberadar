import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/data/repositories/track_repository.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/entitlement.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/billing_provider.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/services/live_track_catalog_service.dart';

class _ThrowingTrackRepository implements TrackRepository {
  @override
  Future<void> refresh() => throw StateError('live track refresh used');

  @override
  Stream<List<Track>> watchTracks() =>
      throw StateError('live track stream used');
}

class _ThrowingUserRepository implements UserRepository {
  @override
  Future<void> followArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) => throw StateError('live user write used');

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) => throw StateError('live user write used');

  @override
  Future<void> setFollowedArtists({
    required String userId,
    required String fallbackName,
    required List<String> artists,
  }) => throw StateError('live user write used');

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) => throw StateError('live user write used');

  @override
  Future<void> unfollowArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) => throw StateError('live user write used');

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) => throw StateError('live user write used');

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) => throw StateError('live user stream used');
}

class _FixedLiveTrackCatalogService extends LiveTrackCatalogService {
  _FixedLiveTrackCatalogService(this.tracks);

  final List<Track> tracks;
  String? fetchedRegion;
  String? fetchedGenre;

  @override
  Future<List<Track>> fetchTrendingTracks({
    required String region,
    String? genre,
    int limit = 100,
  }) async {
    fetchedRegion = region;
    fetchedGenre = genre;
    return tracks;
  }
}

void main() {
  const signedInSession = SessionState(
    userId: 'signed-in-user',
    displayName: 'Signed In DJ',
    email: 'dj@example.com',
    providerLabel: 'Email',
    isAuthenticated: true,
    isDemo: false,
  );

  ProviderContainer guestContainer() {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(const AsyncData(SessionState.demo())),
        trackRepositoryProvider.overrideWithValue(_ThrowingTrackRepository()),
        userRepositoryProvider.overrideWithValue(_ThrowingUserRepository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('guest mode uses mock tracks and local profile only', () async {
    final container = guestContainer();
    container.listen(trackStreamProvider, (_, __) {});
    container.listen(userProfileProvider, (_, __) {});

    await _pumpUntil(
      () =>
          container.read(trackStreamProvider).value?.isNotEmpty == true &&
          container.read(userProfileProvider).value != null,
    );

    final tracks = container.read(trackStreamProvider).value;
    final profile = container.read(userProfileProvider).value;

    expect(tracks, isNotNull);
    expect(tracks, isNotEmpty);
    expect(profile?.id, 'demo-dj');
    expect(profile?.displayName, 'Demo DJ');
  });

  test('guest mode does not initialize StoreKit billing', () {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithValue(const AsyncData(SessionState.demo())),
        iapServiceProvider.overrideWith(
          (ref) => throw StateError('IAP service used'),
        ),
      ],
    );
    addTearDown(container.dispose);

    final billing = container.read(billingControllerProvider);

    expect(billing.loadingProducts, isFalse);
    expect(billing.storeAvailable, isFalse);
  });

  test(
    'signed-in free accounts use mock tracks and skip live track reads',
    () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithValue(const AsyncData(signedInSession)),
          trackRepositoryProvider.overrideWithValue(_ThrowingTrackRepository()),
        ],
      );
      addTearDown(container.dispose);

      container.listen(trackStreamProvider, (_, __) {});

      await _pumpUntil(
        () => container.read(trackStreamProvider).value?.isNotEmpty == true,
      );

      expect(container.read(liveCatalogAccessProvider).requiresUpgrade, isTrue);
      expect(container.read(trackStreamProvider).value, isNotEmpty);
    },
  );

  test(
    'signed-in Pro accounts use live catalog instead of Firestore tracks',
    () async {
      final liveTrack = Track(
        id: 'live-track',
        title: 'Live Track',
        artist: 'Live Artist',
        artworkUrl: '',
        bpm: 120,
        keySignature: '8A',
        genre: 'House',
        vibe: 'club',
        trendScore: 0.9,
        regionScores: const {'US': 0.9},
        platformLinks: const {},
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        energyLevel: 0.8,
        trendHistory: const [],
      );
      final liveCatalog = _FixedLiveTrackCatalogService([liveTrack]);
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWithValue(const AsyncData(signedInSession)),
          appEntitlementProvider.overrideWithValue(
            const AsyncData(AppEntitlement(tier: 'pro', active: true)),
          ),
          trackRepositoryProvider.overrideWithValue(_ThrowingTrackRepository()),
          liveTrackCatalogServiceProvider.overrideWithValue(liveCatalog),
        ],
      );
      addTearDown(container.dispose);

      container.listen(trackStreamProvider, (_, __) {});

      await _pumpUntil(
        () => container.read(trackStreamProvider).value?.first == liveTrack,
      );

      expect(container.read(liveCatalogAccessProvider).hasLiveAccess, isTrue);
      expect(liveCatalog.fetchedRegion, 'Global');
    },
  );

  test('available genres stay broad when the live feed is narrow', () async {
    final now = DateTime.utc(2026);
    final tracks = [
      Track(
        id: 'open-format',
        title: 'Open Format Row',
        artist: 'DJ One',
        artworkUrl: '',
        bpm: 0,
        keySignature: '--',
        genre: 'Open Format',
        vibe: 'club',
        trendScore: 0.6,
        regionScores: const {'Global': 0.6},
        platformLinks: const {},
        createdAt: now,
        updatedAt: now,
        energyLevel: 0.5,
        trendHistory: const [],
      ),
      Track(
        id: 'afrobeats',
        title: 'Afrobeats Row',
        artist: 'DJ Two',
        artworkUrl: '',
        bpm: 0,
        keySignature: '--',
        genre: 'Afrobeats',
        vibe: 'club',
        trendScore: 0.7,
        regionScores: const {'GH': 0.7},
        platformLinks: const {},
        createdAt: now,
        updatedAt: now,
        energyLevel: 0.5,
        trendHistory: const [],
      ),
    ];
    final container = ProviderContainer(
      overrides: [
        trackStreamProvider.overrideWith((ref) => Stream.value(tracks)),
      ],
    );
    addTearDown(container.dispose);

    container.listen(trackStreamProvider, (_, __) {});

    await _pumpUntil(
      () => container.read(trackStreamProvider).value?.length == tracks.length,
    );

    final genres = container.read(availableGenresProvider);

    expect(genres.first, 'All');
    expect(
      genres,
      containsAll([
        'Open Format',
        'Afrobeats',
        'Amapiano',
        'Highlife',
        'Soca',
        'Baile Funk',
        'House',
        'Techno',
        'Drum & Bass',
        'Country',
      ]),
    );
  });
}

Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 20; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  if (!condition()) {
    throw StateError('Condition was not met before timeout.');
  }
}
