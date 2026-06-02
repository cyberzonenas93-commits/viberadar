import 'package:firebase_auth/firebase_auth.dart';
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
// interface that wraps the actual Firebase calls. We fake that interface in
// tests without touching FirebaseAuth/FirebaseFirestore directly.
// ---------------------------------------------------------------------------

class _FakeUser {
  _FakeUser({required this.uid});
  final String uid;
  bool deleteCalled = false;
  bool _shouldThrowRecentLogin = false;

  void makeRecentLoginRequired() => _shouldThrowRecentLogin = true;

  Future<void> delete() async {
    if (_shouldThrowRecentLogin) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    deleteCalled = true;
  }
}

class _FakeBackend implements AccountDeletionBackend {
  _FakeBackend({required this.user});

  final _FakeUser user;
  String? deletedDocPath;
  bool deletedAuthUser = false;

  @override
  String? get currentUserId => user.uid;

  @override
  Future<void> deleteFirestoreDoc(String uid) async {
    deletedDocPath = 'users/$uid';
  }

  @override
  Future<void> deleteAuthUser() async {
    await user.delete();
    deletedAuthUser = true;
  }
}

class _NullUserBackend implements AccountDeletionBackend {
  @override
  String? get currentUserId => null;

  @override
  Future<void> deleteFirestoreDoc(String uid) async {}

  @override
  Future<void> deleteAuthUser() async {}
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
    test('deleteAccount deletes users/{uid} Firestore doc AND auth user',
        () async {
      final fakeUser = _FakeUser(uid: 'user-abc');
      final backend = _FakeBackend(user: fakeUser);
      final service = AccountDeletionService.withBackend(backend);

      await service.deleteAccount();

      expect(backend.deletedDocPath, equals('users/user-abc'));
      expect(fakeUser.deleteCalled, isTrue);
      expect(backend.deletedAuthUser, isTrue);
    });
  });

  group('AccountDeletionService — no signed-in user', () {
    test('throws StateError when currentUser is null', () async {
      final service = AccountDeletionService.withBackend(_NullUserBackend());

      expect(
        () => service.deleteAccount(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AccountDeletionService — requires-recent-login', () {
    test(
        'propagates FirebaseAuthException with requires-recent-login code '
        'when auth delete requires re-auth', () async {
      final fakeUser = _FakeUser(uid: 'user-def');
      fakeUser.makeRecentLoginRequired();
      final backend = _FakeBackend(user: fakeUser);
      final service = AccountDeletionService.withBackend(backend);

      FirebaseAuthException? caught;
      try {
        await service.deleteAccount();
      } on FirebaseAuthException catch (e) {
        caught = e;
      }

      expect(caught, isNotNull);
      expect(caught!.code, equals('requires-recent-login'));
    });
  });

  // ---------------------------------------------------------------------------
  // Widget tests — MobileSettingsSheet
  // ---------------------------------------------------------------------------

  group('MobileSettingsSheet — email display', () {
    testWidgets('shows signed-in email in sheet', (tester) async {
      final backend = _FakeBackend(user: _FakeUser(uid: 'u1'));
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
              body: Builder(builder: (context) {
                return ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ProviderScope(
                      overrides: [
                        accountDeletionServiceProvider
                            .overrideWithValue(service),
                        sessionProvider.overrideWith(
                            (ref) => Stream.value(session)),
                        sessionRepositoryProvider.overrideWithValue(fakeRepo),
                      ],
                      child: const MobileSettingsSheet(),
                    ),
                  ),
                  child: const Text('Open'),
                );
              }),
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
      final fakeUser = _FakeUser(uid: 'u2');
      final backend = _FakeBackend(user: fakeUser);
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
              body: Builder(builder: (context) {
                return ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => ProviderScope(
                      overrides: [
                        accountDeletionServiceProvider
                            .overrideWithValue(service),
                        sessionProvider.overrideWith(
                            (ref) => Stream.value(session)),
                        sessionRepositoryProvider.overrideWithValue(fakeRepo),
                      ],
                      child: const MobileSettingsSheet(),
                    ),
                  ),
                  child: const Text('Open'),
                );
              }),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap "Delete account" button
      await tester.tap(find.byKey(const Key('delete_account_button')));
      await tester.pumpAndSettle();

      // Confirm dialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap confirm
      await tester.tap(find.byKey(const Key('confirm_delete_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Verify deleteAccount was invoked (Firestore doc deleted + auth user)
      expect(backend.deletedDocPath, equals('users/u2'));
      expect(fakeUser.deleteCalled, isTrue);
    });
  });
}
