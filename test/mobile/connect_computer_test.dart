import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/models/track.dart';
import 'package:viberadar/models/user_profile.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/repositories.dart';
import 'package:viberadar/data/repositories/user_repository.dart';
import 'package:viberadar/services/pairing_service.dart';
import 'package:viberadar/ui/mobile/connect_computer_sheet.dart';
import 'package:viberadar/ui/mobile/setlist_editor.dart';

// ---------------------------------------------------------------------------
// Fake PairingService
// ---------------------------------------------------------------------------

/// Records calls to [pushSetlist] and controls [claimPairing] return values.
class _FakePairingService extends PairingService {
  _FakePairingService() : super.testOnly();

  /// The code that triggers a successful pairing.
  static const _validCode = 'ABC234';

  // Captured calls
  final List<({String pairingId, Crate crate, String editorUid})>
      pushSetlistCalls = [];

  @override
  Future<({String pairingId, String desktopName})> claimPairing(
    String code,
  ) async {
    if (code == _validCode) {
      return (pairingId: 'p1', desktopName: 'Studio Mac');
    }
    throw Exception('Invalid or expired code');
  }

  @override
  Future<void> pushSetlist(
    String pairingId,
    Crate crate, {
    required String editorUid,
  }) async {
    pushSetlistCalls.add((
      pairingId: pairingId,
      crate: crate,
      editorUid: editorUid,
    ));
  }
}

// ---------------------------------------------------------------------------
// Pre-seeded PairedComputerController — used to override the provider
// with an initial non-null value without touching state after build.
// ---------------------------------------------------------------------------

class _PreseededPairedComputerController extends PairedComputerController {
  _PreseededPairedComputerController(this._initial);
  final PairedComputer _initial;

  @override
  PairedComputer? build() => _initial;
}

// ---------------------------------------------------------------------------
// Fake UserRepository (needed by SetlistEditor)
// ---------------------------------------------------------------------------

class _FakeUserRepository implements UserRepository {
  @override
  Future<void> saveCrate({
    required String userId,
    required String fallbackName,
    required Crate crate,
  }) async {}

  @override
  Stream<UserProfile> watchUser({
    required String userId,
    required String fallbackName,
  }) =>
      Stream.value(UserProfile.empty(id: userId, displayName: fallbackName));

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
// Helpers
// ---------------------------------------------------------------------------

const _session = SessionState(
  userId: 'user-test',
  displayName: 'Test DJ',
  email: 'dj@test.com',
  providerLabel: 'Google',
  isAuthenticated: true,
  isDemo: false,
);

Track _track(String id) => Track(
      id: id,
      title: 'Track $id',
      artist: 'Artist $id',
      artworkUrl: '',
      bpm: 128,
      keySignature: '8A',
      genre: 'House',
      vibe: 'energetic',
      trendScore: 0.75,
      regionScores: const {},
      platformLinks: const {},
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
      energyLevel: 0.8,
      trendHistory: const [],
    );

Crate _crate({List<String> trackIds = const [], String id = 'crate-1'}) =>
    Crate(
      id: id,
      name: 'Test Setlist',
      context: 'Open format',
      trackIds: trackIds,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

/// Pumps [ConnectComputerSheet] directly as the Scaffold body and returns the
/// ProviderContainer for assertions.
///
/// Using [pump] with explicit durations instead of [pumpAndSettle] avoids the
/// "pumpAndSettle timed out" caused by the indeterminate progress indicator
/// that is shown while the async claimPairing call is in flight.
Future<ProviderContainer> _pumpSheet(
  WidgetTester tester,
  _FakePairingService fake,
) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pairingServiceProvider.overrideWithValue(fake),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const MaterialApp(home: Scaffold(body: ConnectComputerSheet()));
        },
      ),
    ),
  );
  // One frame to let the widget tree settle (no autofocus → no endless anim).
  await tester.pump();
  return container;
}

/// Pumps several frames sufficient for the async claimPairing Future to
/// complete and for Riverpod state changes to propagate.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(); // schedule
  await tester.pump(const Duration(milliseconds: 100)); // let Future complete
  await tester.pump(); // rebuild
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConnectComputerSheet — successful pairing', () {
    testWidgets(
      'entering ABC234 and tapping Connect sets pairedComputerProvider',
      (tester) async {
        final fake = _FakePairingService();
        final container = await _pumpSheet(tester, fake);

        // Enter the valid code.
        await tester.enterText(
          find.byKey(const Key('pairing_code_field')),
          'ABC234',
        );
        await tester.pump();

        // Tap Connect.
        await tester.tap(find.byKey(const Key('connect_button')));
        await _settle(tester);

        // pairedComputerProvider should now hold 'Studio Mac'.
        expect(
          container.read(pairedComputerProvider)?.desktopName,
          equals('Studio Mac'),
        );
        expect(
          container.read(pairedComputerProvider)?.pairingId,
          equals('p1'),
        );
      },
    );

    testWidgets(
      'successful connect shows SnackBar "Connected to Studio Mac"',
      (tester) async {
        final fake = _FakePairingService();
        await _pumpSheet(tester, fake);

        await tester.enterText(
          find.byKey(const Key('pairing_code_field')),
          'ABC234',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('connect_button')));
        await _settle(tester);

        expect(
          find.textContaining('Connected to Studio Mac'),
          findsOneWidget,
        );
      },
    );
  });

  group('ConnectComputerSheet — invalid code', () {
    testWidgets(
      'bad code shows error message inline and keeps provider null',
      (tester) async {
        final fake = _FakePairingService();
        final container = await _pumpSheet(tester, fake);

        // Enter a bad code.
        await tester.enterText(
          find.byKey(const Key('pairing_code_field')),
          'BADCOD',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('connect_button')));
        await _settle(tester);

        // Inline error message should appear.
        expect(
          find.textContaining('Invalid or expired code'),
          findsOneWidget,
        );

        // Provider must still be null.
        expect(container.read(pairedComputerProvider), isNull);
      },
    );
  });

  group('SetlistEditor — Send to computer', () {
    testWidgets(
      'Send button calls pushSetlist with correct pairingId, crate id, '
      'and editorUid',
      (tester) async {
        final fake = _FakePairingService();
        const pairedComputer = PairedComputer('p1', 'Studio Mac');
        final crate = _crate(trackIds: ['a', 'b'], id: 'crate-send');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pairingServiceProvider.overrideWithValue(fake),
              // Pre-set the pairedComputerProvider via a subclass that
              // returns the desired initial state from build().
              pairedComputerProvider.overrideWith(
                () =>
                    _PreseededPairedComputerController(pairedComputer),
              ),
              trackStreamProvider.overrideWith(
                (ref) => Stream.value([_track('a'), _track('b')]),
              ),
              sessionProvider.overrideWithValue(const AsyncData(_session)),
              userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
            ],
            child: MaterialApp(home: SetlistEditor(crate: crate)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        // The "Send to" button should be visible.
        expect(find.textContaining('Send to'), findsOneWidget);

        // Tap it.
        await tester.tap(find.textContaining('Send to'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        // pushSetlist should have been called once with correct args.
        expect(fake.pushSetlistCalls.length, equals(1));
        final call = fake.pushSetlistCalls.first;
        expect(call.pairingId, equals('p1'));
        expect(call.crate.id, equals('crate-send'));
        expect(call.editorUid, equals('user-test'));
      },
    );

    testWidgets(
      'Send button shows SnackBar with desktopName after push',
      (tester) async {
        final fake = _FakePairingService();
        const pairedComputer = PairedComputer('p1', 'Studio Mac');
        final crate = _crate(trackIds: ['a'], id: 'crate-snack');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pairingServiceProvider.overrideWithValue(fake),
              pairedComputerProvider.overrideWith(
                () =>
                    _PreseededPairedComputerController(pairedComputer),
              ),
              trackStreamProvider.overrideWith(
                (ref) => Stream.value([_track('a')]),
              ),
              sessionProvider.overrideWithValue(const AsyncData(_session)),
              userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
            ],
            child: MaterialApp(home: SetlistEditor(crate: crate)),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('Send to'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(
          find.textContaining('Sent to Studio Mac'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Send button is NOT shown when pairedComputerProvider is null',
      (tester) async {
        final fake = _FakePairingService();
        final crate = _crate(trackIds: ['a'], id: 'crate-no-send');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pairingServiceProvider.overrideWithValue(fake),
              // pairedComputerProvider left at default (null).
              trackStreamProvider.overrideWith(
                (ref) => Stream.value([_track('a')]),
              ),
              sessionProvider.overrideWithValue(const AsyncData(_session)),
              userRepositoryProvider.overrideWithValue(_FakeUserRepository()),
            ],
            child: MaterialApp(home: SetlistEditor(crate: crate)),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.textContaining('Send to'), findsNothing);
      },
    );
  });
}
