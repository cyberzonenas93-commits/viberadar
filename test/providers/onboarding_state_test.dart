import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:viberadar/models/app_section.dart';
import 'package:viberadar/providers/onboarding_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('intro defaults unseen, then marks seen', () async {
    final s = OnboardingState();
    expect(await s.isIntroSeen(), false);
    await s.markIntroSeen();
    expect(await s.isIntroSeen(), true);
  });

  test('per-section tutorial seen is independent', () async {
    final s = OnboardingState();
    expect(await s.isTutorialSeen(AppSection.home), false);
    await s.markTutorialSeen(AppSection.home);
    expect(await s.isTutorialSeen(AppSection.home), true);
    expect(await s.isTutorialSeen(AppSection.trending), false);
  });
}
