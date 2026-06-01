import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/services/platform_search_service.dart';
import 'package:viberadar/ui/mobile/search_tab.dart';

// ---------------------------------------------------------------------------
// Fake service — returns two fixed results synchronously-ish
// ---------------------------------------------------------------------------

class _FakePlatformSearchService extends PlatformSearchService {
  static final _fakeResults = [
    const PlatformTrackResult(
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      artworkUrl: null,
      spotifyUrl: 'https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b',
      appleUrl: 'https://music.apple.com/us/album/1499209373',
      youtubeUrl: 'https://www.youtube.com/watch?v=4NRXx6U8ABQ',
      durationMs: 200040,
      popularity: 95,
    ),
    const PlatformTrackResult(
      title: 'Levitating',
      artist: 'Dua Lipa',
      artworkUrl: null,
      spotifyUrl: 'https://open.spotify.com/track/463CkQjx2Zk1yXoBuierM9',
      appleUrl: null,
      youtubeUrl: null,
      durationMs: 203064,
      popularity: 88,
    ),
  ];

  @override
  Future<List<PlatformTrackResult>> search(String query, {int limit = 50}) async {
    // Immediate return; debounce in the real widget handles delay.
    return _fakeResults;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap({PlatformSearchService? service}) {
  return ProviderScope(
    overrides: [
      platformSearchServiceProvider
          .overrideWithValue(service ?? _FakePlatformSearchService()),
    ],
    child: const MaterialApp(home: Scaffold(body: SearchTab())),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SearchTab — initial / empty state', () {
    testWidgets('shows hint text when query is empty', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(
        find.text('Search Spotify, Apple Music, YouTube'),
        findsOneWidget,
      );
    });

    testWidgets('TextField is present', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('SearchTab — search flow', () {
    testWidgets('results appear after typing and debounce elapses',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Enter query
      await tester.enterText(find.byType(TextField), 'weeknd');
      // Let debounce (400 ms) pass, plus settle rendering
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Both titles should be visible
      expect(find.text('Blinding Lights'), findsOneWidget);
      expect(find.text('Levitating'), findsOneWidget);
    });

    testWidgets('both artists are shown', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'pop hits');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('The Weeknd'), findsOneWidget);
      expect(find.text('Dua Lipa'), findsOneWidget);
    });

    testWidgets('Open in affordance is present for a result with multiple URLs',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'pop hits');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // "Blinding Lights" has Spotify + Apple + YouTube, so at minimum one
      // "Open in" button or icon is visible (we look for IconButtons or the
      // text "Open in" — impl uses IconButtons with tooltips).
      // The implementation renders IconButtons for each present URL.
      expect(find.byType(IconButton), findsWidgets);
    });
  });

  group('SearchTab — no results state', () {
    testWidgets('shows "No results" when service returns empty', (tester) async {
      // Use a service that returns nothing
      final emptyService = _EmptySearchService();

      await tester.pumpWidget(_wrap(service: emptyService));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzzunknown');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('No results'), findsOneWidget);
    });
  });
}

class _EmptySearchService extends PlatformSearchService {
  @override
  Future<List<PlatformTrackResult>> search(String query,
      {int limit = 50}) async {
    return [];
  }
}
