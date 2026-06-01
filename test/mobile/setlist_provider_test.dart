import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/data/repositories/user_repository.dart';

// ---------------------------------------------------------------------------
// Minimal fake UserRepository that captures saveCrate calls.
// ---------------------------------------------------------------------------

class _FakeUserRepository implements UserRepository {
  String? capturedUserId;
  Crate? capturedCrate;

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
    capturedUserId = userId;
    capturedCrate = crate;
  }

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) =>
      Stream.value(UserProfile.empty(id: userId, displayName: fallbackName));

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) async {}

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) async {}

  @override
  Future<void> followArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> unfollowArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> setFollowedArtists({
    required String userId,
    required String fallbackName,
    required List<String> artists,
  }) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Crate _makeCrate(String id, DateTime updatedAt) => Crate(
      id: id,
      name: 'Crate $id',
      context: 'Open format',
      trackIds: const [],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: updatedAt,
    );

/// Pump the event loop until [condition] is true, or [maxIterations] reached.
Future<void> _pumpUntil(
  bool Function() condition, {
  int maxIterations = 50,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('setlistsProvider', () {
    test('returns crates sorted by updatedAt descending', () async {
      final older = _makeCrate('a', DateTime(2024, 6, 1));
      final newer = _makeCrate('b', DateTime(2024, 12, 31));

      final profile = UserProfile(
        id: 'user-1',
        displayName: 'Test DJ',
        preferredRegion: 'US',
        watchlist: const {},
        savedCrates: [older, newer], // older first in the list
      );

      // Use a StreamController so we control emission timing.
      final ctrl = StreamController<UserProfile>();

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) => ctrl.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      // Start listening before emitting.
      container.listen(userProfileProvider, (_, __) {});

      // Emit the profile.
      ctrl.add(profile);
      await _pumpUntil(
        () => container.read(userProfileProvider).value != null,
      );

      final setlists = container.read(setlistsProvider);

      expect(setlists.length, 2);
      // Newest first
      expect(setlists[0].id, 'b');
      expect(setlists[1].id, 'a');
    });

    test('returns empty list when userProfile has no crates', () async {
      final profile = UserProfile.empty(
        id: 'user-1',
        displayName: 'Test DJ',
      );

      final ctrl = StreamController<UserProfile>();

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) => ctrl.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(ctrl.close);

      container.listen(userProfileProvider, (_, __) {});

      ctrl.add(profile);
      await _pumpUntil(
        () => container.read(userProfileProvider).value != null,
      );

      final setlists = container.read(setlistsProvider);
      expect(setlists, isEmpty);
    });
  });

  group('SetlistActions.create', () {
    test('calls saveCrate with correct name and userId when authenticated',
        () async {
      final fakeRepo = _FakeUserRepository();

      const session = SessionState(
        userId: 'user-42',
        displayName: 'DJ Test',
        email: 'dj@test.com',
        providerLabel: 'Google',
        isAuthenticated: true,
        isDemo: false,
      );

      final sessionCtrl = StreamController<SessionState>();
      final profileCtrl = StreamController<UserProfile>();

      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => sessionCtrl.stream),
          userRepositoryProvider.overrideWithValue(fakeRepo),
          userProfileProvider.overrideWith((ref) => profileCtrl.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessionCtrl.close);
      addTearDown(profileCtrl.close);

      // Start listening on both providers before emitting.
      container.listen(sessionProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});

      sessionCtrl.add(session);
      profileCtrl.add(
        UserProfile.empty(id: 'user-42', displayName: 'DJ Test'),
      );

      await _pumpUntil(
        () => container.read(sessionProvider).value != null,
      );

      await container.read(setlistActionsProvider).create('Sunset');

      expect(fakeRepo.capturedUserId, 'user-42');
      expect(fakeRepo.capturedCrate, isNotNull);
      expect(fakeRepo.capturedCrate!.name, 'Sunset');
      expect(fakeRepo.capturedCrate!.trackIds, isEmpty);
      expect(fakeRepo.capturedCrate!.context, 'Open format');
      // ID should be a non-empty UUID string
      expect(fakeRepo.capturedCrate!.id, isNotEmpty);
    });

    test('does nothing when session is not authenticated', () async {
      final fakeRepo = _FakeUserRepository();

      const session = SessionState(
        userId: 'demo-dj',
        displayName: 'Demo DJ',
        email: 'demo@viberadar.local',
        providerLabel: 'Demo workspace',
        isAuthenticated: false,
        isDemo: true,
      );

      final sessionCtrl = StreamController<SessionState>();
      final profileCtrl = StreamController<UserProfile>();

      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => sessionCtrl.stream),
          userRepositoryProvider.overrideWithValue(fakeRepo),
          userProfileProvider.overrideWith((ref) => profileCtrl.stream),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessionCtrl.close);
      addTearDown(profileCtrl.close);

      container.listen(sessionProvider, (_, __) {});
      container.listen(userProfileProvider, (_, __) {});

      sessionCtrl.add(session);
      profileCtrl.add(
        UserProfile.empty(id: 'demo-dj', displayName: 'Demo DJ'),
      );

      await _pumpUntil(
        () => container.read(sessionProvider).value != null,
      );

      await container.read(setlistActionsProvider).create('Blocked');

      // saveCrate should NOT have been called
      expect(fakeRepo.capturedCrate, isNull);
    });
  });

  group('Crate.copyWith', () {
    test('preserves id and createdAt; updates name and updatedAt', () {
      final original = _makeCrate('x', DateTime(2024, 1, 1));
      final newTime = DateTime(2025, 6, 1);
      final copy = original.copyWith(name: 'Renamed', updatedAt: newTime);

      expect(copy.id, 'x');
      expect(copy.createdAt, original.createdAt);
      expect(copy.name, 'Renamed');
      expect(copy.updatedAt, newTime);
      expect(copy.context, original.context);
      expect(copy.trackIds, original.trackIds);
    });

    test('returns equal values when no changes specified', () {
      final original = _makeCrate('y', DateTime(2024, 3, 15));
      final copy = original.copyWith();

      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.context, original.context);
      expect(copy.trackIds, original.trackIds);
      expect(copy.createdAt, original.createdAt);
      expect(copy.updatedAt, original.updatedAt);
    });
  });
}
