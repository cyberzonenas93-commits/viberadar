import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/ui/mobile/trending_tab.dart';

// ---------------------------------------------------------------------------
// Fake UserRepository that captures the last saveCrate call
// ---------------------------------------------------------------------------

class _FakeUserRepository implements UserRepository {
  Crate? capturedCrate;

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
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
// Track helper — only the fields we care about for these tests
// ---------------------------------------------------------------------------

Track _track(
  String id, {
  String title = 'Untitled',
  int bpm = 0,
  double trendScore = 0.0,
}) {
  final now = DateTime(2025, 1, 1);
  return Track(
    id: id,
    title: title,
    artist: 'Test Artist',
    artworkUrl: '',
    bpm: bpm,
    keySignature: '4A',
    genre: 'Afrobeats',
    vibe: 'club',
    trendScore: trendScore,
    regionScores: const {},
    platformLinks: const {},
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
    sources: const ['spotify'],
  );
}

Crate _crate({required String id, required String name}) => Crate(
      id: id,
      name: name,
      context: 'Open format',
      trackIds: const [],
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 6, 1),
    );

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

/// Returns a widget + a callback to seed the session after first pump.
///
/// Usage:
///   final (widget, seedSession) = _wrapWithSession(...);
///   await tester.pumpWidget(widget);   // provider subscribes
///   seedSession();                     // emit the session
///   await tester.pump(Duration.zero);  // process the stream event
///   await tester.pumpAndSettle();
(Widget, VoidCallback) _wrapWithSession({
  required List<Track> tracks,
  List<Crate> setlists = const [],
  UserRepository? userRepo,
  SessionState? session,
}) {
  final fakeRepo = userRepo ?? _FakeUserRepository();
  final effectiveSession = session ??
      const SessionState(
        userId: 'user-1',
        displayName: 'DJ Test',
        email: 'dj@test.com',
        providerLabel: 'Google',
        isAuthenticated: true,
        isDemo: false,
      );

  final sessionCtrl = StreamController<SessionState>.broadcast();

  // _SessionKeepalive watches sessionProvider so that the StreamProvider
  // maintains an active subscription and caches the latest emitted value.
  // Without this, nothing in TrendingTab's widget tree subscribes to the
  // session, so broadcast-stream events are lost and ref.read() returns
  // AsyncLoading when SetlistActions.save() checks authentication.
  final widget = ProviderScope(
    overrides: [
      trackStreamProvider.overrideWith((ref) => Stream.value(tracks)),
      setlistsProvider.overrideWithValue(setlists),
      sessionProvider.overrideWith((ref) => sessionCtrl.stream),
      userRepositoryProvider.overrideWithValue(fakeRepo),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const TrendingTab(),
            // Invisible consumer to keep sessionProvider subscribed so
            // its cached AsyncValue stays up to date (broadcast stream needs
            // at least one listener before events are emitted).
            Offstage(
              child: Consumer(
                builder: (_, ref, __) {
                  ref.watch(sessionProvider);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  return (widget, () => sessionCtrl.add(effectiveSession));
}

/// Simpler wrapper for tests that don't need to verify saveCrate calls.
Widget _wrap({
  required List<Track> tracks,
  List<Crate> setlists = const [],
  UserRepository? userRepo,
  SessionState? session,
}) {
  final (widget, _) = _wrapWithSession(
    tracks: tracks,
    setlists: setlists,
    userRepo: userRepo,
    session: session,
  );
  return widget;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TrendingTab — render', () {
    testWidgets('displays tracks sorted by trendScore descending',
        (tester) async {
      final t1 = _track('t1', title: 'Low Score', trendScore: 0.3);
      final t2 = _track('t2', title: 'Top Track', trendScore: 0.9);
      final t3 = _track('t3', title: 'Middle Track', trendScore: 0.6);

      await tester.pumpWidget(_wrap(tracks: [t1, t2, t3]));
      await tester.pumpAndSettle();

      // All three titles appear
      expect(find.text('Top Track'), findsOneWidget);
      expect(find.text('Middle Track'), findsOneWidget);
      expect(find.text('Low Score'), findsOneWidget);

      // Check ordering — 'Top Track' should appear before 'Middle Track' in the
      // widget tree (higher in the list).
      final topPos = tester.getTopLeft(find.text('Top Track'));
      final midPos = tester.getTopLeft(find.text('Middle Track'));
      final lowPos = tester.getTopLeft(find.text('Low Score'));

      expect(topPos.dy, lessThan(midPos.dy));
      expect(midPos.dy, lessThan(lowPos.dy));
    });

    testWidgets('shows a + button for each track', (tester) async {
      final tracks = [
        _track('t1', title: 'Track A', trendScore: 0.8),
        _track('t2', title: 'Track B', trendScore: 0.5),
      ];

      await tester.pumpWidget(_wrap(tracks: tracks));
      await tester.pumpAndSettle();

      // There should be at least one add IconButton per track
      expect(find.byIcon(Icons.add_circle_outline), findsNWidgets(2));
    });

    testWidgets('shows empty state when there are no tracks', (tester) async {
      await tester.pumpWidget(_wrap(tracks: []));
      await tester.pumpAndSettle();

      expect(find.text('No trending tracks yet.'), findsOneWidget);
    });

    testWidgets('shows loading spinner while stream is pending', (tester) async {
      // Never-completing stream simulates loading
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackStreamProvider.overrideWith(
              (ref) => const Stream<List<Track>>.empty(),
            ),
            setlistsProvider.overrideWithValue(const []),
            sessionProvider.overrideWith(
              (ref) => Stream.value(const SessionState(
                userId: 'u',
                displayName: 'DJ',
                email: 'dj@test.com',
                providerLabel: 'Google',
                isAuthenticated: true,
                isDemo: false,
              )),
            ),
            userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
          ],
          child: const MaterialApp(home: Scaffold(body: TrendingTab())),
        ),
      );
      await tester.pump(); // do NOT pumpAndSettle — stream never ends

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders BPM chip for track with known BPM', (tester) async {
      final tracks = [_track('t1', title: 'BPM Track', bpm: 128)];

      await tester.pumpWidget(_wrap(tracks: tracks));
      await tester.pumpAndSettle();

      expect(find.text('128 BPM'), findsOneWidget);
    });

    testWidgets('renders em-dash BPM for unknown BPM (0)', (tester) async {
      final tracks = [_track('t1', title: 'No BPM', bpm: 0)];

      await tester.pumpWidget(_wrap(tracks: tracks));
      await tester.pumpAndSettle();

      expect(find.text('— BPM'), findsOneWidget);
    });
  });

  group('TrendingTab — add flow', () {
    testWidgets('tapping + opens bottom sheet with setlist names',
        (tester) async {
      final tracks = [_track('t1', title: 'Track One', trendScore: 0.9)];
      final setlists = [
        _crate(id: 's1', name: 'Friday Night'),
        _crate(id: 's2', name: 'Sunday Warm-Up'),
      ];

      await tester.pumpWidget(_wrap(tracks: tracks, setlists: setlists));
      await tester.pumpAndSettle();

      // Tap the + button of the first row
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Sunday Warm-Up'), findsOneWidget);
      expect(find.text('New setlist…'), findsOneWidget);
    });

    testWidgets('tapping setlist in sheet calls saveCrate with track id',
        (tester) async {
      final fakeRepo = _FakeUserRepository();
      const session = SessionState(
        userId: 'user-42',
        displayName: 'DJ Test',
        email: 'dj@test.com',
        providerLabel: 'Google',
        isAuthenticated: true,
        isDemo: false,
      );

      final tracks = [_track('t1', title: 'Banger', trendScore: 0.95)];
      final setlist = _crate(id: 's1', name: 'Weekend Vibes');

      final (widget, seedSession) = _wrapWithSession(
        tracks: tracks,
        setlists: [setlist],
        userRepo: fakeRepo,
        session: session,
      );

      // 1. Pump widget so the provider subscribes to the stream.
      await tester.pumpWidget(widget);
      // 2. Seed the session (now there's a listener).
      seedSession();
      // 3. Let Riverpod process the stream event.
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();

      // Tap + button
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      // Tap the setlist option
      await tester.tap(find.text('Weekend Vibes'));
      await tester.pumpAndSettle();

      // The captured crate should now contain 't1'
      expect(fakeRepo.capturedCrate, isNotNull);
      expect(fakeRepo.capturedCrate!.trackIds, contains('t1'));
    });

    testWidgets('tapping setlist shows SnackBar with setlist name',
        (tester) async {
      final tracks = [_track('t1', title: 'Anthem', trendScore: 0.8)];
      final setlist = _crate(id: 's1', name: 'Late Night');

      await tester.pumpWidget(
        _wrap(tracks: tracks, setlists: [setlist]),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Late Night'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Added to Late Night'), findsOneWidget);
    });

    testWidgets('shows only "New setlist…" when user has no setlists',
        (tester) async {
      final tracks = [_track('t1', title: 'Solo Track', trendScore: 0.5)];

      await tester.pumpWidget(_wrap(tracks: tracks, setlists: []));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('New setlist…'), findsOneWidget);
      // No other ListTile text visible besides the option
      expect(find.textContaining('Weekend'), findsNothing);
    });
  });

  group('SetlistActions.addTrack', () {
    test('appends trackId to setlist and calls saveCrate', () async {
      final fakeRepo = _FakeUserRepository();
      const session = SessionState(
        userId: 'user-99',
        displayName: 'DJ',
        email: 'dj@test.com',
        providerLabel: 'Google',
        isAuthenticated: true,
        isDemo: false,
      );

      final crate = _crate(id: 'c1', name: 'My Set');
      final sessionCtrl = StreamController<SessionState>()..add(session);

      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => sessionCtrl.stream),
          userRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessionCtrl.close);

      container.listen(sessionProvider, (_, __) {});

      // Pump event loop so session propagates
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await container.read(setlistActionsProvider).addTrack(crate, 'track-1');

      expect(fakeRepo.capturedCrate, isNotNull);
      expect(fakeRepo.capturedCrate!.trackIds, contains('track-1'));
    });

    test('does not duplicate trackId if already present', () async {
      final fakeRepo = _FakeUserRepository();
      const session = SessionState(
        userId: 'user-99',
        displayName: 'DJ',
        email: 'dj@test.com',
        providerLabel: 'Google',
        isAuthenticated: true,
        isDemo: false,
      );

      final crate = Crate(
        id: 'c1',
        name: 'My Set',
        context: 'Open format',
        trackIds: const ['track-1'],
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 6, 1),
      );

      final sessionCtrl = StreamController<SessionState>()..add(session);

      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => sessionCtrl.stream),
          userRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(sessionCtrl.close);

      container.listen(sessionProvider, (_, __) {});

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Track already in crate — should be a no-op
      await container.read(setlistActionsProvider).addTrack(crate, 'track-1');

      // saveCrate should NOT have been called
      expect(fakeRepo.capturedCrate, isNull);
    });
  });
}
