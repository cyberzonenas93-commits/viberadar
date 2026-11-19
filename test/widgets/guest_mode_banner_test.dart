import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:viberadar/core/theme/app_theme.dart';
import 'package:viberadar/data/repositories/session_repository.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/ui/widgets/guest_mode_banner.dart';

class _FakeSessionRepository implements SessionRepository {
  @override
  Future<void> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {}

  @override
  Future<void> signInAnonymously() async {}

  @override
  Future<void> signInWithApple() async {}

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {}

  @override
  Stream<SessionState> sessionChanges() => const Stream.empty();
}

void main() {
  testWidgets('GuestModeBanner clearly says songs are mock only', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWithValue(_FakeSessionRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(body: GuestModeBanner()),
        ),
      ),
    );

    expect(find.textContaining('MOCK SONGS ONLY'), findsOneWidget);
    expect(find.textContaining('not real live songs'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
