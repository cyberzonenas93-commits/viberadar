import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/models/app_section.dart';
import 'package:viberadar/ui/onboarding/screen_tutorial.dart';

const covered = [
  AppSection.home,
  AppSection.trending,
  AppSection.search,
  AppSection.aiCopilot,
  AppSection.setlists,
  AppSection.community,
  AppSection.forYou,
  AppSection.artists,
  AppSection.setBuilder,
  AppSection.library,
  AppSection.exports,
];

void main() {
  test(
    'every covered section has complete tutorial copy + onboarding asset',
    () {
      for (final s in covered) {
        final e = tutorialRegistry[s];
        expect(e, isNotNull, reason: 'missing ${s.name}');
        expect(e!.title.isNotEmpty, true, reason: '${s.name} title');
        expect(e.body.isNotEmpty, true, reason: '${s.name} body');
        expect(
          e.asset.startsWith('assets/onboarding/'),
          true,
          reason: '${s.name} asset',
        );
      }
    },
  );

  testWidgets('TutorialHost shows the sheet once, then never again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    Widget app() => const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: TutorialHost(section: AppSection.home, child: Text('SCREEN')),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Your Dashboard'), findsOneWidget); // sheet shown
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Your Dashboard'), findsNothing);

    // Remount: already seen → no sheet.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Your Dashboard'), findsNothing);
  });
}
