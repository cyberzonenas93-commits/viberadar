import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/theme/app_theme.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/ui/widgets/pro_paywall.dart';

Widget _wrap(
  Widget child, {
  LiveCatalogAccess access = LiveCatalogAccess.freePreview,
}) {
  return ProviderScope(
    overrides: [liveCatalogAccessProvider.overrideWithValue(access)],
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: child),
    ),
  );
}

bool _hasAsset(WidgetTester tester, String assetName) {
  return tester.widgetList<Image>(find.byType(Image)).any((image) {
    final provider = image.image;
    return provider is AssetImage && provider.assetName == assetName;
  });
}

void main() {
  testWidgets('ProUpsellBanner renders Gemini banner artwork', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 640, child: ProUpsellBanner())),
    );

    expect(_hasAsset(tester, 'assets/paywall/pro_banner_live.png'), isTrue);
    expect(find.textContaining('MOCK SONGS ONLY'), findsOneWidget);
    expect(find.textContaining('not real live songs'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });

  testWidgets('ProLockedPanel renders Gemini hero artwork for free users', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 390,
          height: 500,
          child: ProLockedPanel(feature: 'Search'),
        ),
      ),
    );

    expect(_hasAsset(tester, 'assets/paywall/pro_locked_hero.png'), isTrue);
    expect(find.text('Unlock Search with Pro'), findsOneWidget);
    expect(find.textContaining('MOCK SONGS ONLY'), findsOneWidget);
  });

  testWidgets('ProLockedPanel renders Gemini badge artwork for sign-in gates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 390,
          height: 500,
          child: ProLockedPanel(feature: 'AI Copilot'),
        ),
        access: LiveCatalogAccess.signedOut,
      ),
    );

    expect(_hasAsset(tester, 'assets/paywall/pro_sheet_badge.png'), isTrue);
    expect(find.text('AI Copilot needs an account'), findsOneWidget);
  });
}
