import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viberadar/core/theme/app_theme.dart';
import 'package:viberadar/models/session_state.dart';
import 'package:viberadar/providers/app_state.dart';
import 'package:viberadar/ui/widgets/subscription_section.dart';

const _unauthSession = SessionState(
  userId: '',
  displayName: 'Guest DJ',
  email: '',
  providerLabel: '',
  isAuthenticated: false,
  isDemo: false,
);

void main() {
  testWidgets(
    'SubscriptionSection shows the 3.1.2 auto-renew disclosure, EULA, '
    'Privacy, and Restore at the point of purchase',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => Stream.value(_unauthSession)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SubscriptionSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('subscription_auto_renew_disclosure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('subscription_benefit_summary')),
        findsOneWidget,
      );
      expect(find.textContaining('live trend charts'), findsOneWidget);
      expect(find.textContaining('AI set building'), findsOneWidget);
      expect(find.textContaining('platform search'), findsOneWidget);
      expect(
        find.textContaining('auto-renewable subscription'),
        findsOneWidget,
      );
      expect(find.textContaining('renews automatically'), findsOneWidget);
      expect(find.text('Terms of Use (EULA)'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.byKey(const Key('restore_purchases_button')), findsOneWidget);
    },
  );
}
