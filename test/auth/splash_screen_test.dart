import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/ui/auth/splash_screen.dart';

void main() {
  testWidgets('splash uses a solid background behind the animated mark', (
    tester,
  ) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(home: SplashScreen(onFinished: () => finished = true)),
    );

    expect(find.byType(Image), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xFF0C1015),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 3600));
    expect(finished, isTrue);
  });
}
