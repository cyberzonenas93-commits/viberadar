// test/desktop/screen_smoke_test.dart
//
// Lightweight smoke tests for desktop screens: TrendingScreen, HomeScreen,
// and GreatestOfScreen.
//
// Each test pumps the screen inside MaterialApp + ProviderScope with the
// minimum provider overrides, asserts it builds without throwing, and verifies
// at least one key element is present.
//
// CachedNetworkImage with an empty artworkUrl gracefully falls back to the
// placeholder widget — artworkUrl is '' in all synthetic tracks so there are
// no real network calls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/ui/features/home/home_screen.dart';
import 'package:viberadar/ui/features/trending/trending_screen.dart';
import 'package:viberadar/ui/features/greatest_of/greatest_of_screen.dart';

// ---------------------------------------------------------------------------
// Track helper
// ---------------------------------------------------------------------------

Track _track({
  required String id,
  required String title,
  required String artist,
  double trendScore = 0.5,
  String genre = 'Afrobeats',
  int bpm = 120,
  int releaseYear = 2018,
}) {
  final now = DateTime(2022, 1, 1);
  return Track(
    id: id,
    title: title,
    artist: artist,
    artworkUrl: '',       // empty → no network attempt
    bpm: bpm,
    keySignature: '8B',
    genre: genre,
    vibe: 'club',
    trendScore: trendScore,
    regionScores: const {'GH': 0.7, 'NG': 0.6},
    platformLinks: const {},
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.6,
    trendHistory: const [],
    sources: const ['spotify'],
    releaseYear: releaseYear,
  );
}

// Minimal authenticated session
const _authSession = SessionState(
  userId: 'u1',
  displayName: 'Test DJ',
  email: 'dj@test.com',
  providerLabel: 'Google',
  isAuthenticated: true,
  isDemo: false,
);

// Guest user profile
UserProfile get _guestProfile =>
    UserProfile.empty(id: 'public-guest', displayName: 'Guest DJ', preferredRegion: 'GH');

// ---------------------------------------------------------------------------
// Desktop viewport helper
// ---------------------------------------------------------------------------

/// Give the test surface a desktop-like size so the screens don't overflow.
/// Each testWidgets callback runs in isolation, so the reset is harmless to skip.
void _setDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
}

// ---------------------------------------------------------------------------
// Helper: wrap a widget in ProviderScope + MaterialApp with minimum overrides
// ---------------------------------------------------------------------------

Widget _wrap(
  Widget child, {
  List<Track>? tracks,
}) {
  final effectiveTracks = tracks ??
      [
        _track(id: 't1', title: 'Track Alpha', artist: 'Burna Boy',
            trendScore: 0.9),
        _track(id: 't2', title: 'Track Beta', artist: 'Wizkid',
            trendScore: 0.6),
        _track(id: 't3', title: 'Track Gamma', artist: 'Davido',
            trendScore: 0.3),
      ];

  return ProviderScope(
    overrides: [
      trackStreamProvider.overrideWith(
          (ref) => Stream.value(effectiveTracks)),
      sessionProvider.overrideWith(
          (ref) => Stream.value(_authSession)),
      // crateProvider is a NotifierProvider — the default (empty) state is
      // fine for smoke tests; we don't need to override it.
      availableRegionsProvider.overrideWithValue(
          const ['Global', 'GH', 'NG', 'US']),
    ],
    child: MaterialApp(
      // Dark theme so AppTheme colours resolve correctly
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// TrendingScreen smoke tests
// ---------------------------------------------------------------------------

void main() {
  group('TrendingScreen smoke tests', () {
    testWidgets('builds without throwing and shows a track title',
        (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(
        _wrap(const TrendingScreen()),
      );
      await tester.pumpAndSettle();

      // Screen built; verify at least one track title is visible
      expect(find.text('Track Alpha'), findsOneWidget);
    });

    testWidgets('shows "Trending" heading', (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrap(const TrendingScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);
    });

    testWidgets('shows empty-state message when track list is empty',
        (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrap(const TrendingScreen(), tracks: []));
      await tester.pumpAndSettle();

      expect(find.text('No tracks match your filters'), findsOneWidget);
    });

    testWidgets('displays one grid card per track', (tester) async {
      _setDesktopSize(tester);
      final tracks = [
        _track(id: 's1', title: 'Alpha', artist: 'A', trendScore: 0.9),
        _track(id: 's2', title: 'Beta', artist: 'B', trendScore: 0.6),
      ];
      await tester.pumpWidget(_wrap(const TrendingScreen(), tracks: tracks));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });
  });

  // ── HomeScreen smoke tests ─────────────────────────────────────────────────

  group('HomeScreen smoke tests', () {
    testWidgets('builds without throwing', (tester) async {
      _setDesktopSize(tester);
      final tracks = [
        _track(id: 'h1', title: 'Home Track 1', artist: 'Artist One',
            trendScore: 0.85),
        _track(id: 'h2', title: 'Home Track 2', artist: 'Artist Two',
            trendScore: 0.70),
        _track(id: 'h3', title: 'Home Track 3', artist: 'Artist Three',
            trendScore: 0.55),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(_authSession)),
            availableRegionsProvider.overrideWithValue(
                const ['Global', 'GH', 'NG']),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HomeScreen(
                allTracks: tracks,
                userProfile: _guestProfile,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The "Welcome to VibeRadar" text should appear
      expect(find.text('Welcome to VibeRadar'), findsOneWidget);
    });

    testWidgets('shows Top Trending section when 3+ tracks provided',
        (tester) async {
      _setDesktopSize(tester);
      final tracks = [
        _track(id: 'ht1', title: 'Hero Track', artist: 'Star', trendScore: 0.95),
        _track(id: 'ht2', title: 'Second', artist: 'Star', trendScore: 0.80),
        _track(id: 'ht3', title: 'Third', artist: 'Star', trendScore: 0.70),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(_authSession)),
            availableRegionsProvider.overrideWithValue(const ['Global', 'GH']),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HomeScreen(allTracks: tracks, userProfile: _guestProfile),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top Trending'), findsOneWidget);
    });

    testWidgets('shows correct track count in stat pill', (tester) async {
      _setDesktopSize(tester);
      final tracks = [
        _track(id: 'hp1', title: 'T1', artist: 'X', trendScore: 0.9),
        _track(id: 'hp2', title: 'T2', artist: 'Y', trendScore: 0.8),
        _track(id: 'hp3', title: 'T3', artist: 'Z', trendScore: 0.7),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(_authSession)),
            availableRegionsProvider.overrideWithValue(const ['Global']),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: HomeScreen(allTracks: tracks, userProfile: _guestProfile),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The StatPill shows '3' as the track count
      expect(find.text('3'), findsWidgets); // may appear in multiple places
    });
  });

  // ── GreatestOfScreen smoke tests ───────────────────────────────────────────

  group('GreatestOfScreen smoke tests', () {
    testWidgets('builds without throwing and shows heading', (tester) async {
      _setDesktopSize(tester);
      final tracks = <Track>[
        _track(id: 'g1', title: 'Greatest One', artist: 'Legend',
            trendScore: 0.9, releaseYear: 2015),
        _track(id: 'g2', title: 'Greatest Two', artist: 'Icon',
            trendScore: 0.75, releaseYear: 2010),
      ];

      await tester.pumpWidget(
        _wrap(const GreatestOfScreen(), tracks: tracks),
      );
      // We use pump rather than pumpAndSettle to avoid the async platformSearch
      // timer running indefinitely.  One frame is enough to assert the widget
      // tree rendered correctly.
      await tester.pump();

      expect(find.text('Greatest Of'), findsOneWidget);
    });

    testWidgets('renders with empty track list without throwing',
        (tester) async {
      _setDesktopSize(tester);
      await tester.pumpWidget(_wrap(const GreatestOfScreen(), tracks: []));
      await tester.pump();

      // Should build cleanly — '0 tracks' in the header
      expect(find.textContaining('tracks'), findsWidgets);
    });
  });
}
