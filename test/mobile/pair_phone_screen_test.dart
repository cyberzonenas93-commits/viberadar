import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/models/crate_track.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/providers/library_provider.dart';
import 'package:viberadar/services/pairing_service.dart';
import 'package:viberadar/ui/shell/pair_phone_screen.dart';

// ---------------------------------------------------------------------------
// Fake PairingService implementations
// ---------------------------------------------------------------------------

/// A [PairingService] subclass that returns a fixed pairing and a single crate.
class _FakePairingService extends PairingService {
  _FakePairingService() : super.testOnly();

  @override
  Future<({String pairingId, String code})> createPairing({
    String desktopName = 'Desktop',
  }) async => (pairingId: 'p1', code: 'ABC234');

  @override
  Stream<List<Crate>> watchSharedSetlists(String pairingId) => Stream.value([
    Crate(
      id: 'c1',
      name: 'From Phone',
      context: 'Open format',
      tracks: const [CrateTrack(title: 'Phone Song', artist: 'Phone Artist')],
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 6, 1),
    ),
  ]);
}

/// A [PairingService] subclass whose [createPairing] always throws.
class _ErrorPairingService extends PairingService {
  _ErrorPairingService() : super.testOnly();

  @override
  Future<({String pairingId, String code})> createPairing({
    String desktopName = 'Desktop',
  }) async => throw Exception('CONFIGURATION_NOT_FOUND');

  @override
  Stream<List<Crate>> watchSharedSetlists(String pairingId) =>
      const Stream.empty();
}

// ---------------------------------------------------------------------------
// Widget wrapper helpers
// ---------------------------------------------------------------------------

Widget _wrapWith(PairingService service) {
  return ProviderScope(
    overrides: [pairingServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(home: PairPhoneScreen()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // The pairing is now persisted via SharedPreferences (durable across app
  // restarts), so the desktop provider reads it on resolve. Start each test
  // with empty prefs so it falls through to createPairing.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('PairPhoneScreen — happy path', () {
    testWidgets('shows code ABC234 after pairing resolves', (tester) async {
      await tester.pumpWidget(_wrapWith(_FakePairingService()));
      await tester.pumpAndSettle();

      expect(find.text('ABC234'), findsOneWidget);
    });

    testWidgets('renders a QrImageView widget', (tester) async {
      await tester.pumpWidget(_wrapWith(_FakePairingService()));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('shows received setlist name "From Phone"', (tester) async {
      await tester.pumpWidget(_wrapWith(_FakePairingService()));
      await tester.pumpAndSettle();

      expect(find.text('From Phone'), findsOneWidget);
    });

    testWidgets('Import seeds received setlist into local Export Studio', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pairingServiceProvider.overrideWithValue(_FakePairingService()),
            sessionProvider.overrideWithValue(
              const AsyncData(SessionState.demo()),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: PairPhoneScreen());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      final exportSetlist = container.read(crateProvider).crates['From Phone'];
      expect(exportSetlist, isNotNull);
      expect(exportSetlist, contains('vibe:Phone Song:Phone Artist'));
    });

    testWidgets('shows setlist count badge "1 setlist received"', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWith(_FakePairingService()));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 setlist received'), findsOneWidget);
    });

    testWidgets('Done button is present', (tester) async {
      await tester.pumpWidget(_wrapWith(_FakePairingService()));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('PairPhoneScreen — loading state', () {
    testWidgets('shows spinner before pairing resolves', (tester) async {
      // Use a Completer-backed service so we can observe the in-flight state.
      final completer = Completer<({String pairingId, String code})>();

      final slowService = _SlowPairingService(completer.future);

      await tester.pumpWidget(_wrapWith(slowService));
      // Do NOT pumpAndSettle — pump one frame to trigger initState.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve so teardown is clean.
      completer.complete((pairingId: 'p1', code: 'ABC234'));
      await tester.pumpAndSettle();
    });
  });

  group('PairPhoneScreen — error state', () {
    testWidgets('shows friendly error message when createPairing throws', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapWith(_ErrorPairingService()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Pairing is unavailable'), findsOneWidget);
      expect(find.textContaining('signing in'), findsOneWidget);
    });

    testWidgets('does NOT show QrImageView on error', (tester) async {
      await tester.pumpWidget(_wrapWith(_ErrorPairingService()));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsNothing);
    });
  });
}

// ---------------------------------------------------------------------------
// Slow fake for loading-state test
// ---------------------------------------------------------------------------

class _SlowPairingService extends PairingService {
  _SlowPairingService(this._future) : super.testOnly();

  final Future<({String pairingId, String code})> _future;

  @override
  Future<({String pairingId, String code})> createPairing({
    String desktopName = 'Desktop',
  }) => _future;

  @override
  Stream<List<Crate>> watchSharedSetlists(String pairingId) =>
      const Stream.empty();
}
