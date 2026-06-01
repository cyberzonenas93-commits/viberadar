import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/ui/mobile/setlist_editor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal Track with only required fields set.
Track _track(String id) => Track(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      artworkUrl: '',
      bpm: 128,
      keySignature: '8A',
      genre: 'House',
      vibe: 'energetic',
      trendScore: 0.75,
      regionScores: const {},
      platformLinks: const {},
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      energyLevel: 0.8,
      trendHistory: const [],
    );

Crate _crate({required List<String> trackIds, String name = 'Test Setlist'}) =>
    Crate(
      id: 'crate-1',
      name: name,
      context: 'Open format',
      trackIds: trackIds,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

/// Fake UserRepository that captures the last [saveCrate] call.
class _CapturingUserRepository implements UserRepository {
  Crate? lastSaved;

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
    lastSaved = crate;
  }

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) =>
      Stream.value(
        UserProfile.empty(id: userId, displayName: fallbackName),
      );

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

const _session = SessionState(
  userId: 'user-test',
  displayName: 'Test DJ',
  email: 'dj@test.com',
  providerLabel: 'Google',
  isAuthenticated: true,
  isDemo: false,
);

Widget _wrap(Widget child, _CapturingUserRepository repo) {
  return ProviderScope(
    overrides: [
      trackStreamProvider.overrideWith(
        (ref) => Stream.value([_track('a'), _track('b'), _track('c')]),
      ),
      // Supply the session as a synchronous AsyncData so that
      // ref.read(sessionProvider).value is non-null on first read.
      sessionProvider.overrideWithValue(const AsyncData(_session)),
      userRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(home: child),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SetlistEditor — remove track', () {
    testWidgets(
      'deleting track b persists crate with trackIds [a, c]',
      (tester) async {
        final repo = _CapturingUserRepository();
        final crate = _crate(trackIds: ['a', 'b', 'c']);

        await tester.pumpWidget(_wrap(SetlistEditor(crate: crate), repo));
        // Multiple pumps to let StreamProviders (session, tracks) settle.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // All three tracks should be visible.
        expect(find.text('Track a'), findsOneWidget);
        expect(find.text('Track b'), findsOneWidget);
        expect(find.text('Track c'), findsOneWidget);

        // Find the delete icon for Track b specifically.
        final bTile = find.ancestor(
          of: find.text('Track b'),
          matching: find.byType(ListTile),
        );
        final deleteIconInB = find.descendant(
          of: bTile,
          matching: find.byIcon(Icons.delete_outline),
        );
        await tester.tap(deleteIconInB);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // Track b should be gone from the list.
        expect(find.text('Track b'), findsNothing);

        // The repo should have captured the updated crate.
        expect(repo.lastSaved, isNotNull);
        expect(repo.lastSaved!.trackIds, equals(['a', 'c']));
      },
    );
  });

  group('SetlistEditor — rename', () {
    testWidgets(
      'submitting a new name persists crate with updated name',
      (tester) async {
        final repo = _CapturingUserRepository();
        final crate = _crate(trackIds: ['a', 'b', 'c'], name: 'Old Name');

        await tester.pumpWidget(_wrap(SetlistEditor(crate: crate), repo));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // The AppBar title should show the current name.
        expect(find.text('Old Name'), findsOneWidget);

        // Tap the title GestureDetector to enter edit mode — this swaps the
        // static Text for a TextField with key 'setlist_name_field'.
        await tester.tap(find.text('Old Name'));
        await tester.pumpAndSettle();

        // Now the TextField should be visible.
        final titleField = find.byKey(const Key('setlist_name_field'));
        expect(titleField, findsOneWidget);

        // Enter the new name and submit.
        await tester.enterText(titleField, 'New Name');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(repo.lastSaved, isNotNull);
        expect(repo.lastSaved!.name, equals('New Name'));
      },
    );
  });

  group('SetlistEditor — empty state', () {
    testWidgets('shows empty message when trackIds is empty', (tester) async {
      final repo = _CapturingUserRepository();
      final crate = _crate(trackIds: []);

      await tester.pumpWidget(_wrap(SetlistEditor(crate: crate), repo));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No tracks yet'),
        findsOneWidget,
      );
    });
  });

  group('SetlistEditor — unknown track graceful fallback', () {
    testWidgets('unknown track id shows fallback text (no crash)',
        (tester) async {
      final repo = _CapturingUserRepository();
      // Track 'z' is NOT in the stream (only a, b, c are).
      final crate = _crate(trackIds: ['a', 'z']);

      await tester.pumpWidget(_wrap(SetlistEditor(crate: crate), repo));
      await tester.pump();
      await tester.pumpAndSettle();

      // 'a' resolves fine; 'z' should show a fallback without crashing.
      expect(find.text('Track a'), findsOneWidget);
      // There should be exactly 2 rows; the second shows some fallback text.
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Pure unit test: reorder index math helper.
  // (Drag-gesture reorder is flaky in widget tests; we unit-test the pure fn.)
  // ---------------------------------------------------------------------------
  group('reorderTrackIds', () {
    test('moves item from oldIndex to newIndex correctly', () {
      // The helper is exposed for testing.
      final ids = ['a', 'b', 'c', 'd'];
      expect(reorderTrackIds(ids, 0, 2), ['b', 'a', 'c', 'd']);
      expect(reorderTrackIds(ids, 3, 1), ['a', 'd', 'b', 'c']);
      expect(reorderTrackIds(ids, 1, 1), ['a', 'b', 'c', 'd']); // no-op
    });

    test('handles single-element list', () {
      expect(reorderTrackIds(['x'], 0, 0), ['x']);
    });
  });
}
