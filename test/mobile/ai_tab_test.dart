import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/services/ai_copilot_service.dart';
import 'package:viberadar/ui/mobile/ai_tab.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/data/repositories/session_repository.dart';
import 'package:viberadar/models/user_profile.dart';

// ---------------------------------------------------------------------------
// Fake AiCopilotService — returns a fixed crate block with 2 tracks
// ---------------------------------------------------------------------------

const _fakeCrateResponse = '''
Here is a great set for you.

1. Burna Boy - Last Last (93 BPM, 10A)
2. Rema - Calm Down (93 BPM, 7A)

```crate
{"name":"Test Vibes","tracks":[{"title":"Last Last","artist":"Burna Boy","bpm":93,"key":"10A"},{"title":"Calm Down","artist":"Rema","bpm":93,"key":"7A"}]}
```
''';

class _FakeAiCopilotService extends AiCopilotService {
  @override
  Future<String> chat(
    List<Map<String, String>> history,
    String userMessage, {
    List<Map<String, String>>? trackContext,
    int? yearFrom,
    int? yearTo,
  }) async {
    return _fakeCrateResponse;
  }
}

// ---------------------------------------------------------------------------
// Fake SessionRepository — returns an authenticated session
// ---------------------------------------------------------------------------

class _FakeSessionRepository implements SessionRepository {
  @override
  Stream<SessionState> sessionChanges() => Stream.value(
        const SessionState(
          userId: 'test-user',
          displayName: 'Test DJ',
          email: 'test@viberadar.local',
          providerLabel: 'Test',
          isAuthenticated: true,
          isDemo: false,
        ),
      );

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

  @override
  Future<void> signOut() async {}
}

// ---------------------------------------------------------------------------
// Fake UserRepository — captures saveCrate calls
// ---------------------------------------------------------------------------

class _FakeUserRepository implements UserRepository {
  final List<Crate> savedCrates = [];

  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {
    savedCrates.add(crate);
  }

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) =>
      Stream.value(
        UserProfile.empty(
          id: userId,
          displayName: fallbackName,
          preferredRegion: 'GH',
        ),
      );

  @override
  Future<void> toggleWatchlist({
    required String userId,
    required String fallbackName,
    required String trackId,
  }) async {}

  @override
  Future<void> updatePreferredRegion({
    required String userId,
    required String fallbackName,
    required String region,
  }) async {}

  @override
  Future<void> followArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> unfollowArtist({
    required String userId,
    required String fallbackName,
    required String artistName,
  }) async {}

  @override
  Future<void> setFollowedArtists({
    required String userId,
    required String fallbackName,
    required List<String> artists,
  }) async {}
}

// ---------------------------------------------------------------------------
// Fake SetlistActions — captures saves without needing a real sessionProvider
// ---------------------------------------------------------------------------

class _CapturingSetlistActions extends SetlistActions {
  _CapturingSetlistActions(
    super.ref,
    this._fakeRepo,
  );

  final _FakeUserRepository _fakeRepo;

  @override
  Future<void> save(Crate crate) async {
    await _fakeRepo.saveCrate(
      userId: 'test-user',
      fallbackName: 'Test DJ',
      crate: crate,
    );
  }
}

// ---------------------------------------------------------------------------
// Widget wrapper
// ---------------------------------------------------------------------------

Widget _buildTestApp({
  required _FakeUserRepository fakeRepo,
}) {
  return ProviderScope(
    overrides: [
      aiCopilotServiceProvider.overrideWithValue(_FakeAiCopilotService()),
      sessionRepositoryProvider.overrideWithValue(_FakeSessionRepository()),
      userRepositoryProvider.overrideWithValue(fakeRepo),
      setlistActionsProvider.overrideWith(
        (ref) => _CapturingSetlistActions(ref, fakeRepo),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: AiTab())),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AiTab — initial state', () {
    testWidgets('shows prompt TextField and Build button', (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Build'), findsOneWidget);
    });

    testWidgets('Save as setlist button is disabled initially', (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save as setlist'),
      );
      expect(saveButton.onPressed, isNull);
    });
  });

  group('AiTab — build flow', () {
    testWidgets('entering a prompt and tapping Build shows 2 draft tracks',
        (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Build me a set');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      // Both tracks from the fake crate should appear in the list
      expect(find.textContaining('Burna Boy'), findsOneWidget);
      expect(find.textContaining('Last Last'), findsOneWidget);
      expect(find.textContaining('Rema'), findsOneWidget);
      expect(find.textContaining('Calm Down'), findsOneWidget);
    });

    testWidgets('draft track shows BPM and Key subtitle', (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Build me a set');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      expect(find.textContaining('93'), findsAtLeastNWidgets(1));
      expect(find.textContaining('10A'), findsOneWidget);
      expect(find.textContaining('7A'), findsOneWidget);
    });
  });

  group('AiTab — save flow', () {
    testWidgets(
        'after building, Save as setlist creates Crate with correct name and 2 trackIds',
        (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Build me a set');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      // Save button should now be enabled
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Save as setlist'),
      );
      expect(saveButton.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save as setlist'));
      await tester.pumpAndSettle();

      // Exactly one crate should have been saved
      expect(repo.savedCrates, hasLength(1));

      final saved = repo.savedCrates.first;
      expect(saved.name, equals('Test Vibes'));
      expect(saved.trackIds, hasLength(2));

      // Synthesized ids follow 'ai:<artist - title>' pattern (lowercased, trimmed)
      expect(
        saved.trackIds,
        containsAll([
          'ai:burna boy - last last',
          'ai:rema - calm down',
        ]),
      );
    });

    testWidgets('shows SnackBar with crate name after saving', (tester) async {
      final repo = _FakeUserRepository();
      await tester.pumpWidget(_buildTestApp(fakeRepo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Build me a set');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save as setlist'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Test Vibes'), findsAtLeastNWidgets(1));
    });
  });

  group('AiTab — non-crate response', () {
    testWidgets('shows plain text reply when no crate block present',
        (tester) async {
      // Use a custom fake that returns plain text
      final repo = _FakeUserRepository();
      final plainFake = _PlainReplyFakeService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiCopilotServiceProvider.overrideWithValue(plainFake),
            sessionRepositoryProvider
                .overrideWithValue(_FakeSessionRepository()),
            userRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(home: Scaffold(body: AiTab())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'How do I mix in key?');
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Harmonic mixing tip'), findsOneWidget);
      // No tracks rendered (no crate block)
      expect(find.textContaining('Burna Boy'), findsNothing);
    });
  });
}

class _PlainReplyFakeService extends AiCopilotService {
  @override
  Future<String> chat(
    List<Map<String, String>> history,
    String userMessage, {
    List<Map<String, String>>? trackContext,
    int? yearFrom,
    int? yearTo,
  }) async {
    return 'Harmonic mixing tip: use the Camelot wheel.';
  }
}
