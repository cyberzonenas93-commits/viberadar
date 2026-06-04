import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/core/platform.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/ui/mobile/mobile_shell.dart';

// ---------------------------------------------------------------------------
// Verifies the platform routing (MobileShell on phones, not on desktop) and
// the mobile-native companion shell's nav structure.
//
// MobileShell hosts the four mobile companion tabs directly. Some tabs open
// provider subscriptions, so we override the shared data providers and use
// pump() instead of pumpAndSettle() when only nav structure is under test.
// ---------------------------------------------------------------------------

class _DesktopPlaceholder extends StatelessWidget {
  const _DesktopPlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Desktop')));
}

class _AdaptiveShellUnderTest extends StatelessWidget {
  const _AdaptiveShellUnderTest();
  @override
  Widget build(BuildContext context) {
    if (isMobileForm) return const MobileShell();
    return const _DesktopPlaceholder();
  }
}

Widget _wrap(Widget child) => ProviderScope(
  overrides: [
    setlistsProvider.overrideWithValue(const []),
    sessionProvider.overrideWith(
      (ref) => Stream.value(const SessionState.demo()),
    ),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(
        UserProfile.empty(
          id: 'test',
          displayName: 'Test DJ',
          preferredRegion: 'GH',
        ),
      ),
    ),
    trackStreamProvider.overrideWith((ref) => Stream.value(const <Track>[])),
  ],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('MobileShell shown on iOS; desktop placeholder absent', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const _AdaptiveShellUnderTest()));
    await tester.pump();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(_DesktopPlaceholder), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Desktop placeholder shown on macOS; MobileShell absent', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(_wrap(const _AdaptiveShellUnderTest()));
    await tester.pump();

    expect(find.byType(_DesktopPlaceholder), findsOneWidget);
    expect(find.byType(MobileShell), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('MobileShell renders all 4 companion nav destinations', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const MobileShell()));
    await tester.pump();

    expect(find.text('Setlists'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Trending'), findsWidgets);
    expect(find.text('AI'), findsWidgets);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping Search opens the mobile search tab', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const MobileShell()));
    await tester.pump();

    await tester.tap(find.text('Search').last);
    await tester.pump();

    expect(find.text('Search Spotify, Apple Music, YouTube'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
