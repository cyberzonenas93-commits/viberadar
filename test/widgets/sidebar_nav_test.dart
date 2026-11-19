import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/theme/app_theme.dart';
import 'package:viberadar/models/app_section.dart';
import 'package:viberadar/ui/widgets/sidebar_nav.dart';

void main() {
  testWidgets('SidebarNav does not show normal Firebase connection status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 760,
            child: SidebarNav(
              selectedSection: AppSection.home,
              onSelected: (_) {},
              statusMessage: 'Connected to Firebase project viberadar-462b8.',
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Connected to Firebase'), findsNothing);
  });

  testWidgets('SidebarNav keeps the mock-song warning in demo mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 760,
            child: SidebarNav(
              selectedSection: AppSection.home,
              onSelected: (_) {},
              statusMessage: '',
              isDemoMode: true,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('MOCK SONGS ONLY'), findsOneWidget);
    expect(find.textContaining('Not real live tracks'), findsOneWidget);
  });
}
