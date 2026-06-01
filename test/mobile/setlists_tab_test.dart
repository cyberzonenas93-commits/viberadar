import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/models/crate.dart';
import 'package:viberadar/providers/setlist_provider.dart';
import 'package:viberadar/ui/mobile/setlists_tab.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Crate _crate({
  required String id,
  required String name,
  List<String> trackIds = const [],
}) =>
    Crate(
      id: id,
      name: name,
      context: 'Open format',
      trackIds: trackIds,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 6, 1, 12, 0),
    );

Widget _wrap(List<Crate> crates) {
  return ProviderScope(
    overrides: [
      setlistsProvider.overrideWithValue(crates),
    ],
    child: const MaterialApp(home: SetlistsTab()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SetlistsTab — populated list', () {
    testWidgets('renders both setlist names', (tester) async {
      final crates = [
        _crate(id: 'a', name: 'Friday Night', trackIds: ['t1', 't2', 't3']),
        _crate(id: 'b', name: 'Sunday Warm-Up'),
      ];

      await tester.pumpWidget(_wrap(crates));
      await tester.pumpAndSettle();

      expect(find.text('Friday Night'), findsOneWidget);
      expect(find.text('Sunday Warm-Up'), findsOneWidget);
    });

    testWidgets('shows correct track-count subtitles', (tester) async {
      final crates = [
        _crate(id: 'a', name: 'Main Stage', trackIds: ['t1', 't2']),
        _crate(id: 'b', name: 'Empty Set'),
      ];

      await tester.pumpWidget(_wrap(crates));
      await tester.pumpAndSettle();

      // Subtitle is combined text e.g. "2 tracks  ·  Jun 1, 12:00"
      expect(find.textContaining('2 tracks'), findsOneWidget);
      expect(find.textContaining('0 tracks'), findsOneWidget);
    });

    testWidgets('FloatingActionButton is present', (tester) async {
      await tester.pumpWidget(_wrap([
        _crate(id: 'x', name: 'Test Set'),
      ]));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('empty-state message is NOT shown when list is non-empty',
        (tester) async {
      await tester.pumpWidget(_wrap([_crate(id: 'z', name: 'A Set')]));
      await tester.pumpAndSettle();

      expect(
        find.text('No setlists yet — tap ＋ to create one.'),
        findsNothing,
      );
    });
  });

  group('SetlistsTab — empty state', () {
    testWidgets('shows empty-state message when list is empty', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      expect(
        find.text('No setlists yet — tap ＋ to create one.'),
        findsOneWidget,
      );
    });

    testWidgets('FloatingActionButton still present on empty state',
        (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('no list tiles visible when list is empty', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('SetlistsTab — header', () {
    testWidgets('shows "Setlists" heading', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      expect(find.text('Setlists'), findsOneWidget);
    });
  });

  group('SetlistsTab — create dialog', () {
    testWidgets('tapping FAB opens AlertDialog with TextField', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('dialog dismisses when Cancel is tapped', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
