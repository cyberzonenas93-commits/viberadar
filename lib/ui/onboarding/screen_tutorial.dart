import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/app_section.dart';
import '../../providers/onboarding_state.dart';

typedef TutorialEntry = ({String asset, String title, String body});

String _art(AppSection s) => 'assets/onboarding/screen_${s.name}.png';

/// First-run explainer copy + illustration for each key screen.
final Map<AppSection, TutorialEntry> tutorialRegistry = {
  AppSection.home: (
    asset: _art(AppSection.home),
    title: 'Your Dashboard',
    body: "At-a-glance metrics and today's movers, tuned to your region.",
  ),
  AppSection.trending: (
    asset: _art(AppSection.trending),
    title: 'Trending Radar',
    body:
        'The freshest charting tracks across Spotify, Apple, Deezer & more — ranked by real momentum.',
  ),
  AppSection.search: (
    asset: _art(AppSection.search),
    title: 'Find Anything',
    body: 'Search any track, artist or genre across every source at once.',
  ),
  AppSection.aiCopilot: (
    asset: _art(AppSection.aiCopilot),
    title: 'AI Set Builder',
    body:
        'Describe a vibe; the AI drafts a set you can resolve to playable links and save as a setlist.',
  ),
  AppSection.setlists: (
    asset: _art(AppSection.setlists),
    title: 'Your Setlists',
    body:
        'Build, reorder and sync setlists — send them to your Mac with a tap.',
  ),
  AppSection.community: (
    asset: _art(AppSection.community),
    title: 'DJ Community',
    body: 'Share mixes, follow DJs, and see what the scene is playing.',
  ),
  AppSection.forYou: (
    asset: _art(AppSection.forYou),
    title: 'For You',
    body:
        'A personalised feed of tracks and artists picked for your taste and region.',
  ),
  AppSection.artists: (
    asset: _art(AppSection.artists),
    title: 'Artists',
    body: 'Track artist momentum and dive into their rising records.',
  ),
  AppSection.setBuilder: (
    asset: _art(AppSection.setBuilder),
    title: 'Set Builder',
    body: 'Craft harmonically-mixed sets with BPM/key-aware transitions.',
  ),
  AppSection.library: (
    asset: _art(AppSection.library),
    title: 'My Library',
    body: "Everything you've saved, watch-listed and built — in one place.",
  ),
  AppSection.exports: (
    asset: _art(AppSection.exports),
    title: 'Exports',
    body: 'Export your setlists to Serato, Rekordbox and more.',
  ),
};

/// Shows a screen's tutorial bottom sheet exactly once. Marks it seen *before*
/// showing so dismissing any way (Got it / swipe / tap-outside) never re-shows.
Future<void> maybeShowTutorial(
  WidgetRef ref,
  BuildContext context,
  AppSection section,
) async {
  final entry = tutorialRegistry[section];
  if (entry == null) return;
  final state = ref.read(onboardingStateProvider);
  if (await state.isTutorialSeen(section)) return;
  await state.markTutorialSeen(section);
  if (!context.mounted) return;
  await showScreenTutorial(context, entry);
}

Future<void> showScreenTutorial(BuildContext context, TutorialEntry entry) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.asset(
                  entry.asset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.cyan, AppTheme.violet],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              entry.title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.body,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cyan,
                  foregroundColor: AppTheme.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  'Got it',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Wrap any screen to fire its tutorial once on first mount.
class TutorialHost extends ConsumerStatefulWidget {
  const TutorialHost({super.key, required this.section, required this.child});
  final AppSection section;
  final Widget child;
  @override
  ConsumerState<TutorialHost> createState() => _TutorialHostState();
}

class _TutorialHostState extends ConsumerState<TutorialHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowTutorial(ref, context, widget.section);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
