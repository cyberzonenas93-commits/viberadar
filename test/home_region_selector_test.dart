import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/ui/features/home/home_screen.dart';

/// Regression test for the Home-tab region selector.
///
/// Bug: for an unauthenticated "guest" session the Home tab sourced its region
/// from the user profile, which for guests is a CONSTANT stream locked to 'GH'
/// (and the picker tried to persist to an empty userId, which Firestore
/// rejects). So changing the region had no effect. The region must instead be
/// driven by a reactive local override that works for everyone.
void main() {
  testWidgets('Home region reacts to the local override (guest session)',
      (tester) async {
    const guestSession = SessionState(
      userId: '',
      displayName: 'Guest DJ',
      email: '',
      providerLabel: '',
      isAuthenticated: false,
      isDemo: false,
    );
    final guestProfile = UserProfile.empty(
      id: 'public-guest',
      displayName: 'Guest DJ',
      preferredRegion: 'GH',
    );

    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => Stream.value(guestSession)),
      availableRegionsProvider.overrideWithValue(const ['Global', 'GH', 'US']),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: HomeScreen(allTracks: const [], userProfile: guestProfile),
          ),
        ),
      ),
    );
    await tester.pump();

    // The region badge initially shows the profile fallback.
    expect(find.textContaining('Region: GH'), findsWidgets);

    // Guest picks a new region — the picker sets this local override.
    container.read(selectedRegionProvider.notifier).set('US');
    await tester.pump();

    // The Home tab must now reflect the chosen region (fails before the fix,
    // which read the constant guest profile region instead of the override).
    expect(find.textContaining('Region: US'), findsWidgets);
    expect(find.textContaining('Region: GH'), findsNothing);
  });
}
