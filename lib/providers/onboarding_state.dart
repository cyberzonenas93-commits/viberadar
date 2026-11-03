import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_section.dart';

/// First-run flags: whether the intro carousel has played, and which per-screen
/// tutorials have been shown. Versioned keys so a future revamp can re-show.
class OnboardingState {
  static const _introKey = 'onboarding_intro_v1';
  String _tutKey(AppSection s) => 'tutorial_${s.name}_v1';

  Future<bool> isIntroSeen() async =>
      (await SharedPreferences.getInstance()).getBool(_introKey) ?? false;

  Future<void> markIntroSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_introKey, true);

  Future<bool> isTutorialSeen(AppSection s) async =>
      (await SharedPreferences.getInstance()).getBool(_tutKey(s)) ?? false;

  Future<void> markTutorialSeen(AppSection s) async =>
      (await SharedPreferences.getInstance()).setBool(_tutKey(s), true);
}

final onboardingStateProvider = Provider<OnboardingState>(
  (_) => OnboardingState(),
);
