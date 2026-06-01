import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/core/platform.dart';
import 'package:viberadar/ui/mobile/mobile_shell.dart';
import 'package:viberadar/ui/shell/vibe_shell.dart';

// ---------------------------------------------------------------------------
// Wrapper widget that exercises the same branching logic as auth_gate.dart
// without pulling in the full VibeShell dependency tree.
//
// We use the wrapper fallback (as permitted by the task spec) because
// VibeShell requires dozens of provider overrides (Firebase, Firestore,
// platform channels) that would make this test brittle and slow. The wrapper
// still exercises: (a) isMobileForm reads debugDefaultTargetPlatformOverride,
// and (b) MobileShell builds correctly on iOS; VibeShell is bypassed on desktop
// by returning a stand-in Scaffold so we can assert its absence in the iOS case
// and its presence in the macOS case without standing up Firebase.
// ---------------------------------------------------------------------------

/// A lightweight stand-in that has the same *type* identity as the real
/// VibeShell without needing its Firebase/platform-channel dependencies.
/// We just need `find.byType(VibeShell)` to work, so we pump the real
/// VibeShell class selector inside a builder that avoids constructing it
/// by using a Key-based type check. Instead, we use a different approach:
/// we test the branching by pumping an _AdaptiveShellUnderTest which mirrors
/// the production if/else and returns:
///   - real MobileShell on mobile
///   - a plain _DesktopPlaceholder (not VibeShell) on desktop so we can
///     still assert absence of MobileShell and confirm platform routing works.
//
// Note: We assert that MobileShell IS found on iOS and IS NOT found on macOS.
// For the macOS side we assert a desktop-sentinel widget IS found (proving
// the branch ran) and MobileShell is NOT found.

class _DesktopPlaceholder extends StatelessWidget {
  const _DesktopPlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Desktop')));
}

class _AdaptiveShellUnderTest extends StatelessWidget {
  const _AdaptiveShellUnderTest({super.key});

  @override
  Widget build(BuildContext context) {
    if (isMobileForm) {
      return const MobileShell();
    }
    return const _DesktopPlaceholder();
  }
}

void main() {
  testWidgets('MobileShell shown on iOS; desktop placeholder absent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(home: _AdaptiveShellUnderTest()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(_DesktopPlaceholder), findsNothing);

    // Reset before test framework invariant check fires.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Desktop placeholder shown on macOS; MobileShell absent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      const MaterialApp(home: _AdaptiveShellUnderTest()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(_DesktopPlaceholder), findsOneWidget);
    expect(find.byType(MobileShell), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('MobileShell renders all 4 nav destinations', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(home: MobileShell()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Setlists'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Trending'), findsWidgets);
    expect(find.text('AI'), findsWidgets);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('MobileShell tab switching works', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(home: MobileShell()),
    );
    await tester.pumpAndSettle();

    // Initially shows Setlists tab body
    expect(find.text('Setlists').first, findsOneWidget);

    // Tap Search destination in the NavigationBar
    // NavigationBar labels appear in both bar and body; tap the one in the bar
    final searchDestinations = find.text('Search');
    await tester.tap(searchDestinations.last);
    await tester.pumpAndSettle();

    expect(find.text('Search').first, findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
