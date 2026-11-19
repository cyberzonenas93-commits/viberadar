import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/data/repositories/session_repository.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/services/account_deletion_service.dart';
import 'package:viberadar/ui/mobile/mobile_settings_sheet.dart';

// ---------------------------------------------------------------------------
// Hand-written fakes — avoids heavy mocking deps (no mockito/mocktail needed).
//
// Approach: The service accepts an injectable `AccountDeletionBackend`
// interface that wraps the account-deletion callable. We fake that interface in
// tests without touching Firebase SDK internals.
// ---------------------------------------------------------------------------

class _FakeBackend implements AccountDeletionBackend {
  _FakeBackend({this.error});

  final Object? error;
  bool deleteCalled = false;

  @override
  Future<void> deleteAccount() async {
    final error = this.error;
    if (error != null) throw error;
    deleteCalled = true;
  }
}

class _NullUserBackend implements AccountDeletionBackend {
  @override
  Future<void> deleteAccount() => throw StateError('No signed-in user');
}

// ---------------------------------------------------------------------------
// Fake SessionRepository (needed by sheet's sign-out logic)
// ---------------------------------------------------------------------------

class _FakeSessionRepository implements SessionRepository {
  bool signOutCalled = false;

  @override
  Stream<SessionState> sessionChanges() => const Stream.empty();

  @override
  Future<void> signOut() async => signOutCalled = true;

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {}
}

// ---------------------------------------------------------------------------
// Service tests
// ---------------------------------------------------------------------------

void main() {
  group('AccountDeletionService — success path', () {
    test(
      'deleteAccount calls the backend account-deletion operation',
      () async {
        final backend = _FakeBackend();
        final service = AccountDeletionService.withBackend(backend);

        await service.deleteAccount();

        expect(backend.deleteCalled, isTrue);
      },
    );
  });

  group('AccountDeletionService — no signed-in user', () {
    test('throws StateError when currentUser is null', () async {
      final service = AccountDeletionService.withBackend(_NullUserBackend());

      expect(() => service.deleteAccount(), throwsA(isA<StateError>()));
    });
  });

  group('AccountDeletionService — backend errors', () {
    test('propagates backend deletion failures', () async {
      final backend = _FakeBackend(error: StateError('backend failed'));
      final service = AccountDeletionService.withBackend(backend);

      expect(() => service.deleteAccount(), throwsA(isA<StateError>()));
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — MobileSettingsSheet
  // ---------------------------------------------------------------------------

  group('MobileSettingsSheet — email display', () {
    testWidgets('shows signed-in email in sheet', (tester) async {
      final backend = _FakeBackend();
      final service = AccountDeletionService.withBackend(backend);
      final fakeRepo = _FakeSessionRepository();

      const session = SessionState(
        userId: 'u1',
        displayName: 'DJ Test',
        email: 'dj@test.com',
        providerLabel: 'Email',
        isAuthenticated: true,
        isDemo: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountDeletionServiceProvider.overrideWithValue(service),
            sessionProvider.overrideWith((ref) => Stream.value(session)),
            sessionRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ProviderScope(
                        overrides: [
                          accountDeletionServiceProvider.overrideWithValue(
                            service,
                          ),
                          sessionProvider.overrideWith(
                            (ref) => Stream.value(session),
                          ),
                          sessionRepositoryProvider.overrideWithValue(fakeRepo),
                        ],
                        child: const MobileSettingsSheet(),
                      ),
                    ),
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('dj@test.com'), findsOneWidget);
    });
  });

  group('MobileSettingsSheet — Delete account flow', () {
    testWidgets(
      'tapping Delete account, then confirming, calls deleteAccount',
      (tester) async {
        final backend = _FakeBackend();
        final service = AccountDeletionService.withBackend(backend);
        final fakeRepo = _FakeSessionRepository();

        const session = SessionState(
          userId: 'u2',
          displayName: 'DJ Test',
          email: 'dj@test.com',
          providerLabel: 'Email',
          isAuthenticated: true,
          isDemo: false,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accountDeletionServiceProvider.overrideWithValue(service),
              sessionProvider.overrideWith((ref) => Stream.value(session)),
              sessionRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) => ProviderScope(
                          overrides: [
                            accountDeletionServiceProvider.overrideWithValue(
                              service,
                            ),
                            sessionProvider.overrideWith(
                              (ref) => Stream.value(session),
                            ),
                            sessionRepositoryProvider.overrideWithValue(
                              fakeRepo,
                            ),
                          ],
                          child: const MobileSettingsSheet(),
                        ),
                      ),
                      child: const Text('Open'),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Tap "Delete account" button (scroll it into view first — the
        // settings sheet is scrollable and the button sits below the fold).
        await tester.ensureVisible(
          find.byKey(const Key('delete_account_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete_account_button')));
        await tester.pumpAndSettle();

        // Confirm dialog should appear
        expect(find.byType(AlertDialog), findsOneWidget);

        // Tap confirm
        await tester.tap(find.byKey(const Key('confirm_delete_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        // Verify deleteAccount was invoked.
        expect(backend.deleteCalled, isTrue);
      },
    );
  });
}
