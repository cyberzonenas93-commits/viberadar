import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../data/sources/mock_track_seed.dart';
import '../models/app_section.dart';
import '../models/crate.dart';
import '../models/crate_track.dart';
import '../models/entitlement.dart';
import '../models/session_state.dart';
import '../models/track.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../providers/billing_provider.dart';
import '../providers/onboarding_state.dart';
import '../providers/setlist_provider.dart';
import '../ui/auth/auth_gate.dart';
import '../ui/mobile/mobile_shell.dart';
import '../ui/shell/vibe_shell.dart';
import '../ui/widgets/subscription_section.dart';
import 'bootstrap.dart';

class VibeRadarApp extends ConsumerWidget {
  const VibeRadarApp({super.key, required this.bootstrap});

  final AppBootstrapResult bootstrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const screenshotSurface = String.fromEnvironment('ASC_SCREENSHOT_SURFACE');
    if (screenshotSurface == 'iap') {
      return ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(
            const AsyncData(
              SessionState(
                userId: 'asc-review-dj',
                displayName: 'VibeRadar Review',
                email: 'review@viberadar.app',
                providerLabel: 'Review account',
                isAuthenticated: true,
                isDemo: false,
              ),
            ),
          ),
          appEntitlementProvider.overrideWithValue(
            const AsyncData(AppEntitlement()),
          ),
          billingControllerProvider.overrideWith(
            _IapScreenshotBillingController.new,
          ),
        ],
        child: const _IapScreenshotApp(),
      );
    }
    if (screenshotSurface.startsWith('mobile-') ||
        screenshotSurface.startsWith('mac-')) {
      return _ProductScreenshotApp(surface: screenshotSurface);
    }

    ref.watch(billingControllerProvider);
    return MaterialApp(
      title: 'VibeRadar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: AuthGate(
        statusMessage: bootstrap.statusMessage,
        isDemoMode: bootstrap.isDemoMode,
      ),
    );
  }
}

class _ProductScreenshotApp extends StatelessWidget {
  const _ProductScreenshotApp({required this.surface});

  final String surface;

  @override
  Widget build(BuildContext context) {
    final tracks = buildMockTracks();
    final profile = _screenshotProfile(tracks);
    final desktopSection = _desktopSectionFor(surface);

    return ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(
          const AsyncData(
            SessionState(
              userId: 'asc-review-dj',
              displayName: 'VibeRadar Review',
              email: 'review@viberadar.app',
              providerLabel: 'Review account',
              isAuthenticated: true,
              isDemo: false,
            ),
          ),
        ),
        trackStreamProvider.overrideWithValue(AsyncData(tracks)),
        userProfileProvider.overrideWithValue(AsyncData(profile)),
        setlistsProvider.overrideWithValue(profile.savedCrates),
        appEntitlementProvider.overrideWithValue(
          const AsyncData(
            AppEntitlement(tier: 'pro', active: true, status: 'active'),
          ),
        ),
        onboardingStateProvider.overrideWithValue(_ScreenshotOnboardingState()),
        if (desktopSection != null)
          workspaceControllerProvider.overrideWith(
            () => _ScreenshotWorkspaceController(desktopSection),
          ),
      ],
      child: MaterialApp(
        title: 'VibeRadar',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: _homeFor(surface),
      ),
    );
  }

  Widget _homeFor(String surface) {
    switch (surface) {
      case 'mobile-home':
        return const MobileShell(initialIndex: 0);
      case 'mobile-trending':
        return const MobileShell(initialIndex: 1);
      case 'mobile-search':
        return const MobileShell(initialIndex: 2);
      case 'mobile-ai':
        return const MobileShell(initialIndex: 3);
      case 'mobile-setlists':
        return const MobileShell(initialIndex: 4);
      case 'mobile-more':
        return const MobileShell(initialIndex: 5);
    }

    final section = _desktopSectionFor(surface);
    if (section != null) {
      return const VibeShell(
        statusMessage: 'ASC screenshot mode',
        disableAutoIngest: true,
      );
    }

    return const MobileShell();
  }
}

AppSection? _desktopSectionFor(String surface) {
  return switch (surface) {
    'mac-home' => AppSection.home,
    'mac-trending' => AppSection.trending,
    'mac-setbuilder' => AppSection.setBuilder,
    'mac-crates' => AppSection.savedCrates,
    'mac-settings' => AppSection.settings,
    _ => null,
  };
}

UserProfile _screenshotProfile(List<Track> tracks) {
  final now = DateTime.now();
  CrateTrack entry(Track track) => CrateTrack(
    trackId: track.id,
    title: track.title,
    artist: track.artist,
    bpm: track.bpm,
    key: track.keySignature,
    spotifyUrl: track.platformLinks['spotify'],
    appleUrl: track.platformLinks['apple'],
    youtubeUrl: track.platformLinks['youtube'],
    artworkUrl: track.artworkUrl,
  );

  Crate crate(
    String id,
    String name,
    String context,
    List<Track> crateTracks,
    int ageHours,
  ) {
    return Crate(
      id: id,
      name: name,
      context: context,
      tracks: crateTracks.map(entry).toList(),
      createdAt: now.subtract(Duration(days: ageHours ~/ 24 + 1)),
      updatedAt: now.subtract(Duration(hours: ageHours)),
    );
  }

  return UserProfile(
    id: 'asc-review-dj',
    displayName: 'VibeRadar Review',
    preferredRegion: 'Global',
    watchlist: tracks.take(5).map((track) => track.id).toSet(),
    followedArtists: const ['Amaarae', 'Black Sherif', 'Rema', 'Tyla'],
    savedCrates: [
      crate(
        'crate-late-night',
        'Late Night Afro House',
        'Warm 122 BPM roof-bar openers',
        tracks.take(4).toList(),
        1,
      ),
      crate(
        'crate-peak-hour',
        'Peak Hour Momentum',
        'High-energy records trending in Accra and Lagos',
        tracks.skip(3).take(5).toList(),
        6,
      ),
      crate(
        'crate-afterglow',
        'Afterglow Cooldown',
        'Melodic closers with room to breathe',
        tracks.skip(6).take(4).toList(),
        20,
      ),
    ],
  );
}

class _ScreenshotWorkspaceController extends WorkspaceController {
  _ScreenshotWorkspaceController(this.section);

  final AppSection section;

  @override
  WorkspaceState build() {
    return WorkspaceState(section: section, primaryTrackId: 'vr-01');
  }
}

class _ScreenshotOnboardingState extends OnboardingState {
  @override
  Future<bool> isIntroSeen() async => true;

  @override
  Future<void> markIntroSeen() async {}

  @override
  Future<bool> isTutorialSeen(AppSection s) async => true;

  @override
  Future<void> markTutorialSeen(AppSection s) async {}
}

class _IapScreenshotBillingController extends BillingController {
  @override
  BillingState build() {
    return const BillingState(
      storeAvailable: true,
      loadingProducts: false,
      products: [],
      missingProductIds: {},
    );
  }
}

class _IapScreenshotApp extends StatelessWidget {
  const _IapScreenshotApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeRadar Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: const _IapScreenshotScreen(),
    );
  }
}

class _IapScreenshotScreen extends StatelessWidget {
  const _IapScreenshotScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [AppTheme.cyan, AppTheme.violet, AppTheme.lime],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'VibeRadar Pro',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'AI set building, cue analysis, export tools, and phone-to-Mac sync for working DJs.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const Spacer(flex: 1),
              const SubscriptionSection(),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
