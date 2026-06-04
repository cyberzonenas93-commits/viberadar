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
// the mobile-native shell's nav structure.
//
// MobileShell now mirrors the macOS app by hosting the real feature screens,
// which open Firebase-backed provider subscriptions. We override the handful
// the default (Home) tab needs so it renders with empty data instead of a
// perpetual spinner, and we use pump() (not pumpAndSettle) since some screens
// never "settle" without a live backend. We assert the shell + nav structure,
// not async screen content.
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
        sessionProvider.overrideWith((ref) => Stream.value(
              const SessionState.demo(),
            )),
        userProfileProvider.overrideWith((ref) => Stream.value(
              UserProfile.empty(
                id: 'test',
                displayName: 'Test DJ',
                preferredRegion: 'GH',
              ),
            )),
        trackStreamProvider.overrideWith((ref) => Stream.value(const <Track>[])),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  testWidgets('MobileShell shown on iOS; desktop placeholder absent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const _AdaptiveShellUnderTest()));
    await tester.pump();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(_DesktopPlaceholder), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Desktop placeholder shown on macOS; MobileShell absent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(_wrap(const _AdaptiveShellUnderTest()));
    await tester.pump();

    expect(find.byType(_DesktopPlaceholder), findsOneWidget);
    expect(find.byType(MobileShell), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('MobileShell renders all 5 nav destinations', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const MobileShell()));
    await tester.pump();

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Trending'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('More'), findsWidgets);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping More opens its (static) menu', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_wrap(const MobileShell()));
    await tester.pump();

    // More is the only tab with purely static content (no async spinners).
    await tester.tap(find.text('More').last);
    await tester.pump();

    // Assert items near the top of the menu — a test viewport can't show the
    // whole scrolling list, and the lazy ListView won't build off-screen rows.
    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
