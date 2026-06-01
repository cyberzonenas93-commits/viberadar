import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:viberadar/models/app_section.dart";
import "package:viberadar/models/library_track.dart";
import "package:viberadar/providers/library_provider.dart";
import "package:viberadar/ui/widgets/command_palette.dart";

// ── Helpers ────────────────────────────────────────────────────────────────────

LibraryTrack _track({
  required String id,
  required String title,
  required String artist,
}) {
  return LibraryTrack(
    id: id,
    filePath: "/music/$title.mp3",
    fileName: "$title.mp3",
    title: title,
    artist: artist,
    album: "",
    genre: "House",
    bpm: 128,
    key: "8A",
    durationSeconds: 300,
    fileSizeBytes: 10000000,
    fileExtension: ".mp3",
    md5Hash: "hash-$id",
    bitrate: 320,
    sampleRate: 44100,
  );
}

class _FakeLibraryNotifier extends LibraryNotifier {
  _FakeLibraryNotifier(this._tracks);
  final List<LibraryTrack> _tracks;

  @override
  LibraryState build() => LibraryState(tracks: _tracks);
}

Widget _wrap({
  required List<LibraryTrack> tracks,
  required void Function(AppSection) onNavigate,
  required void Function(LibraryTrack) onOpenTrack,
  required VoidCallback onDismiss,
}) {
  return ProviderScope(
    overrides: [
      libraryProvider.overrideWith(() => _FakeLibraryNotifier(tracks)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: CommandPalette(
          onDismiss: onDismiss,
          onNavigate: onNavigate,
          onOpenTrack: onOpenTrack,
        ),
      ),
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  final sampleTracks = <LibraryTrack>[
    _track(id: "t1", title: "Midnight Groove", artist: "Kojo Beats"),
    _track(id: "t2", title: "Sunrise Anthem", artist: "Ama Serwaa"),
    _track(id: "t3", title: "Azonto Forever", artist: "Kojo Beats"),
  ];

  testWidgets("palette builds without error and shows search field",
      (tester) async {
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (_) {},
      onOpenTrack: (_) {},
      onDismiss: () {},
    ));
    await tester.pump();

    expect(find.byType(CommandPalette), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // Default view shows navigation entries
    expect(find.text("Home"), findsOneWidget);
    expect(find.text("My Library"), findsOneWidget);
  });

  testWidgets("typing filters results", (tester) async {
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (_) {},
      onOpenTrack: (_) {},
      onDismiss: () {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), "midnight");
    await tester.pump();

    // Track result visible
    expect(find.text("Midnight Groove"), findsOneWidget);
    // Unrelated nav entry hidden by filter
    expect(find.text("Home"), findsNothing);
    expect(find.text("Sunrise Anthem"), findsNothing);
  });

  testWidgets("selecting a navigation item calls onNavigate",
      (tester) async {
    AppSection? navigated;
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (s) => navigated = s,
      onOpenTrack: (_) {},
      onDismiss: () {},
    ));
    await tester.pump();

    // First item is Home — tap it.
    await tester.tap(find.text("Home"));
    await tester.pump();

    expect(navigated, AppSection.home);
  });

  testWidgets("arrow down changes highlighted item and enter activates it",
      (tester) async {
    AppSection? navigated;
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (s) => navigated = s,
      onOpenTrack: (_) {},
      onDismiss: () {},
    ));
    await tester.pump();

    // Default highlight is item 0 (Home). Arrow-down twice → Trending (index 2).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(navigated, AppSection.trending);
  });

  testWidgets("escape triggers onDismiss", (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (_) {},
      onOpenTrack: (_) {},
      onDismiss: () => dismissed = true,
    ));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(dismissed, isTrue);
  });

  testWidgets("selecting a track result calls onOpenTrack with that track",
      (tester) async {
    LibraryTrack? opened;
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (_) {},
      onOpenTrack: (t) => opened = t,
      onDismiss: () {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), "azonto");
    await tester.pump();

    await tester.tap(find.text("Azonto Forever"));
    await tester.pump();

    expect(opened, isNotNull);
    expect(opened!.id, "t3");
  });

  testWidgets("no-results state when query matches nothing",
      (tester) async {
    await tester.pumpWidget(_wrap(
      tracks: sampleTracks,
      onNavigate: (_) {},
      onOpenTrack: (_) {},
      onDismiss: () {},
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), "zzzzz-no-match");
    await tester.pump();

    expect(find.text("No results"), findsOneWidget);
  });
}
