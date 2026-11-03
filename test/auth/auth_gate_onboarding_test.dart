import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/data/repositories/track_repository.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/services/messaging_service.dart';
import 'package:viberadar/ui/auth/auth_gate.dart';
import 'package:viberadar/ui/auth/onboarding_screen.dart';

const _session = SessionState(
  userId: 'user-1',
  displayName: 'DJ Test',
  email: 'dj@test.com',
  providerLabel: 'password',
  isAuthenticated: true,
  isDemo: false,
);

class _NoopMessagingService implements MessagingService {
  @override
  Future<void> register(String uid) async {}

  @override
  Future<void> unregister() async {}
}

class _CapturingUserRepository implements UserRepository {
  _CapturingUserRepository({
    this.existingFollowedArtists = const <String>[],
    this.failSetFollowedArtists = false,
    this.failWatchUser = false,
  });

  final List<String> existingFollowedArtists;
  final bool failSetFollowedArtists;
  final bool failWatchUser;
  String? capturedUserId;
  String? capturedFallbackName;
  List<String>? capturedArtists;

  @override
  Future<void> setFollowedArtists({
    required String userId,
    required String fallbackName,
    required List<String> artists,
  }) async {
    if (failSetFollowedArtists) {
      throw StateError('profile write unavailable');
    }
    capturedUserId = userId;
    capturedFallbackName = fallbackName;
    capturedArtists = List<String>.from(artists);
  }

  @override
  Future<void> followArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {}

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) async {}

  @override
  Future<void> unfollowArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) async {}

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) {
    if (failWatchUser) {
      return Stream<UserProfile>.error(StateError('profile unavailable'));
    }
    return Stream.value(
      UserProfile.empty(
        id: userId,
        displayName: fallbackName,
        followedArtists: existingFollowedArtists,
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('pre-auth walkthrough does not collect artist preferences', (
    tester,
  ) async {
    List<String>? completedArtists;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onComplete: (artists) => completedArtists = artists,
        ),
      ),
    );

    expect(find.byType(OnboardingArtistPicker), findsNothing);
    expect(find.text('Choose Artists'), findsNothing);

    await tester.tap(find.text('Skip'));
    expect(completedArtists, isEmpty);
  });

  testWidgets('signed-in users choose artists after auth and save to account', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_intro_v1': true,
      'feature_onboarding_completed_v1': true,
    });

    final repo = _CapturingUserRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(const AsyncData(_session)),
          userRepositoryProvider.overrideWithValue(repo),
          messagingServiceProvider.overrideWithValue(_NoopMessagingService()),
        ],
        child: MaterialApp(
          home: AuthGate(
            statusMessage: 'Ready',
            artistImageLookup: (_) async => const {},
            artistSearch: (_) async => const [],
          ),
        ),
      ),
    );

    await _pumpPastSplashAndProfileLoad(tester);

    expect(find.text('Choose Your Artists'), findsOneWidget);
    expect(find.text('Sign in with Email'), findsNothing);

    await tester.tap(find.text('Drake'));
    await tester.pump();
    await tester.tap(find.text('Get Started'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(repo.capturedUserId, 'user-1');
    expect(repo.capturedFallbackName, 'DJ Test');
    expect(repo.capturedArtists, contains('Drake'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('artist_preferences_completed_v1_user-1'), isTrue);
  });

  testWidgets(
    'existing account artist preferences skip setup on a fresh device',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_intro_v1': true,
        'feature_onboarding_completed_v1': true,
      });

      final repo = _CapturingUserRepository(
        existingFollowedArtists: const ['Drake'],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(const AsyncData(_session)),
            userRepositoryProvider.overrideWithValue(repo),
            trackRepositoryProvider.overrideWithValue(
              const EmptyTrackRepository(),
            ),
            messagingServiceProvider.overrideWithValue(_NoopMessagingService()),
          ],
          child: const MaterialApp(home: AuthGate(statusMessage: 'Ready')),
        ),
      );

      await _pumpPastSplashAndProfileLoad(tester);

      expect(find.text('Choose Your Artists'), findsNothing);
      expect(repo.capturedArtists, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('artist_preferences_completed_v1_user-1'), isTrue);
    },
  );

  testWidgets(
    'profile load failure after auth does not show a post-login error',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_intro_v1': true,
        'feature_onboarding_completed_v1': true,
      });

      final repo = _CapturingUserRepository(failWatchUser: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(const AsyncData(_session)),
            userRepositoryProvider.overrideWithValue(repo),
            trackRepositoryProvider.overrideWithValue(
              const EmptyTrackRepository(),
            ),
            messagingServiceProvider.overrideWithValue(_NoopMessagingService()),
          ],
          child: const MaterialApp(home: AuthGate(statusMessage: 'Ready')),
        ),
      );

      await _pumpPastSplashAndProfileLoad(tester);

      expect(find.text('Choose Your Artists'), findsNothing);
      expect(
        find.textContaining('could not load your artist preferences'),
        findsNothing,
      );
      expect(find.text('Sign in with Email'), findsNothing);
    },
  );

  testWidgets(
    'artist preference save failure is deferred instead of blocking the app',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_intro_v1': true,
        'feature_onboarding_completed_v1': true,
      });

      final repo = _CapturingUserRepository(failSetFollowedArtists: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(const AsyncData(_session)),
            userRepositoryProvider.overrideWithValue(repo),
            trackRepositoryProvider.overrideWithValue(
              const EmptyTrackRepository(),
            ),
            messagingServiceProvider.overrideWithValue(_NoopMessagingService()),
          ],
          child: MaterialApp(
            home: AuthGate(
              statusMessage: 'Ready',
              artistImageLookup: (_) async => const {},
              artistSearch: (_) async => const [],
            ),
          ),
        ),
      );

      await _pumpPastSplashAndProfileLoad(tester);

      await tester.tap(find.text('Drake'));
      await tester.pump();
      await tester.tap(find.text('Get Started'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(
        find.textContaining('could not save your artist preferences'),
        findsNothing,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('artist_preferences_completed_v1_user-1'), isTrue);
      expect(
        prefs.getStringList('pending_followed_artists'),
        contains('Drake'),
      );
    },
  );
}

Future<void> _pumpPastSplashAndProfileLoad(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 3700));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}
