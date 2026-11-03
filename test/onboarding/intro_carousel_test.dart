import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/onboarding/intro_carousel.dart';

void main() {
  testWidgets('Skip fires onFinish; missing art shows fallback (no throw)', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: IntroCarousel(onFinish: () => finished = true)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(finished, true);
  });

  testWidgets('reaching the last slide shows Get Started which finishes', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(home: IntroCarousel(onFinish: () => finished = true)),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(finished, true);
  });
}
