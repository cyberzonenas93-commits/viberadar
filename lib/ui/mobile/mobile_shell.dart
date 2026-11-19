import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/session_state.dart';
import '../../models/track.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state.dart';
import '../features/artists/artists_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/discover_djs_screen.dart';
import '../features/community/profile_screen.dart';
import '../features/community/upload_screen.dart';
import '../features/for_you/for_you_screen.dart';
import '../features/greatest_of/greatest_of_screen.dart';
import '../features/home/home_screen.dart';
import '../features/trending/trending_screen.dart';
import '../widgets/guest_mode_banner.dart';
import '../widgets/pro_paywall.dart';
import '../widgets/vibe_backdrop.dart';
import '../../models/app_section.dart';
import '../onboarding/screen_tutorial.dart';
import 'ai_tab.dart';
import 'connect_computer_sheet.dart';
import 'mobile_settings_sheet.dart';
import 'mobile_set_builder_tab.dart';
import 'search_tab.dart';
import 'setlists_tab.dart';

/// Mobile-native shell for the iOS/Android app.
///
/// It mirrors the macOS product where the workflows make sense on a phone:
/// discovery, search, AI set building, social/profile/upload, setlists, and
/// phone↔desktop pairing. Local folder scanning, duplicate-file cleanup, and
/// DJ-library export tooling stay desktop-only because iOS does not provide the
/// same durable filesystem/DJ app access those flows require.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  static const int _tabCount = 6;

  late int _index;
  late final Set<int> _visited;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _tabCount - 1);
    _visited = {0, _index};
  }

  void _selectTab(int index) {
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Widget _tabFor(
    int index, {
    required bool isGuestMode,
    required LiveCatalogAccess liveAccess,
  }) {
    if (isGuestMode && _mobileTabRequiresLiveServices(index)) {
      return _MobilePage(
        title: _mobileTabTitle(index),
        child: GuestLockedPanel(feature: _mobileTabTitle(index)),
      );
    }
    if (liveAccess.requiresUpgrade && _mobileTabRequiresPro(index)) {
      return _MobilePage(
        title: _mobileTabTitle(index),
        child: ProLockedPanel(feature: _mobileTabTitle(index)),
      );
    }

    return switch (index) {
      0 => TutorialHost(
        section: AppSection.home,
        child: _HomeTab(onOpenSearch: () => _selectTab(2)),
      ),
      1 => const TutorialHost(
        section: AppSection.trending,
        child: _MobilePage(title: 'Trending', child: TrendingScreen()),
      ),
      2 => const TutorialHost(
        section: AppSection.search,
        child: _MobilePage(title: 'Search', child: SearchTab()),
      ),
      3 => const TutorialHost(section: AppSection.aiCopilot, child: AiTab()),
      4 => const TutorialHost(
        section: AppSection.setlists,
        child: SetlistsTab(),
      ),
      5 => const _MoreTab(),
      _ => const SizedBox.shrink(),
    };
  }

  bool _mobileTabRequiresLiveServices(int index) => index == 2 || index == 3;

  bool _mobileTabRequiresPro(int index) => index == 2 || index == 3;

  String _mobileTabTitle(int index) {
    return switch (index) {
      2 => 'Search',
      3 => 'AI',
      _ => 'Feature',
    };
  }

  @override
  Widget build(BuildContext context) {
    final session =
        ref.watch(sessionProvider).value ?? const SessionState.demo();
    final isGuestMode = session.isDemo;
    final liveAccess = ref.watch(liveCatalogAccessProvider);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: VibeBackdrop(
        compact: true,
        child: SafeArea(
          bottom: false,
          // Lazily build tabs: a tab only renders once visited, so the shell
          // stays light (each macOS feature screen opens its own provider subs).
          child: Column(
            children: [
              if (isGuestMode)
                const GuestModeBanner(
                  compact: true,
                  margin: EdgeInsets.fromLTRB(12, 8, 12, 8),
                ),
              if (!isGuestMode)
                const ProUpsellBanner(
                  compact: true,
                  margin: EdgeInsets.fromLTRB(12, 8, 12, 8),
                ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    for (var i = 0; i < _tabCount; i++)
                      _visited.contains(i)
                          ? _tabFor(
                              i,
                              isGuestMode: isGuestMode,
                              liveAccess: liveAccess,
                            )
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _MobileBottomNavigation(
        selectedIndex: _index,
        onSelected: _selectTab,
      ),
    );
  }
}

// ── Shared chrome ────────────────────────────────────────────────────────────

/// Standard mobile app bar in the VibeRadar style.
PreferredSizeWidget _mobileAppBar(String title, [List<Widget>? actions]) {
  return AppBar(
    toolbarHeight: 56,
    centerTitle: false,
    titleSpacing: 4,
    title: Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    backgroundColor: Colors.transparent,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    iconTheme: const IconThemeData(color: AppTheme.textSecondary),
    actions: actions,
  );
}

class _MobileBottomNavigation extends StatelessWidget {
  const _MobileBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.78),
                border: Border.all(color: AppTheme.hairlineStrong),
                borderRadius: BorderRadius.circular(AppTheme.rLg),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: NavigationBar(
                height: 60,
                backgroundColor: Colors.transparent,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.local_fire_department_rounded),
                    label: 'Trending',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.search_rounded),
                    label: 'Search',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: 'AI',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.queue_music_rounded),
                    label: 'Setlists',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.more_horiz_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a bare feature screen (most live without their own Scaffold) in a
/// transparent mobile scaffold so the shell's gradient backdrop shows through.
class _MobilePage extends StatelessWidget {
  const _MobilePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _mobileAppBar(title),
      body: child,
    );
  }
}

/// Pushes [page] as a full route, keeping the gradient backdrop behind it.
void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VibeBackdrop(compact: true, child: page),
    ),
  );
}

/// Opens the account / settings sheet — profile, region, OpenAI key, sign out,
/// and (required by the App Store) account deletion.
void _openAccountSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const MobileSettingsSheet(),
  );
}

void _openConnectComputerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const ConnectComputerSheet(),
  );
}

// ── Home tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab({required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(sessionProvider).value ?? const SessionState.demo();
    final userProfile =
        ref.watch(userProfileProvider).value ??
        UserProfile.empty(
          id: session.userId,
          displayName: session.displayName,
          preferredRegion: 'Global',
        );
    final allTracks = ref.watch(trackStreamProvider).value ?? const <Track>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _mobileAppBar('VibeRadar', [
        IconButton(
          icon: const Icon(Icons.search, color: AppTheme.textSecondary),
          tooltip: 'Search',
          onPressed: onOpenSearch,
        ),
        IconButton(
          icon: const Icon(Icons.account_circle, color: AppTheme.textSecondary),
          tooltip: 'Account & settings',
          onPressed: () => _openAccountSheet(context),
        ),
      ]),
      body: HomeScreen(allTracks: allTracks, userProfile: userProfile),
    );
  }
}

// ── More tab ─────────────────────────────────────────────────────────────────

class _MoreTab extends ConsumerWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(sessionProvider).value ?? const SessionState.demo();
    final isGuestMode = session.isDemo;
    final liveAccess = ref.watch(liveCatalogAccessProvider);
    void liveOnly(BuildContext ctx, String title, Widget page) {
      _push(
        ctx,
        _MobilePage(
          title: title,
          child: isGuestMode
              ? GuestLockedPanel(feature: title)
              : liveAccess.requiresUpgrade && _moreRouteRequiresPro(title)
              ? ProLockedPanel(feature: title)
              : page,
        ),
      );
    }

    final groups = <_MoreGroupData>[
      _MoreGroupData('Discover', [
        _MoreItem(
          icon: Icons.favorite_rounded,
          label: 'For You',
          action: (ctx) => liveOnly(
            ctx,
            'For You',
            ForYouScreen(
              onOpenArtist: (_) =>
                  liveOnly(ctx, 'Artists', const ArtistsScreen()),
            ),
          ),
        ),
        _MoreItem(
          icon: Icons.mic_external_on_rounded,
          label: 'Artists',
          action: (ctx) => liveOnly(ctx, 'Artists', const ArtistsScreen()),
        ),
        _MoreItem(
          icon: Icons.star_rounded,
          label: 'Greatest Of',
          action: (ctx) =>
              liveOnly(ctx, 'Greatest Of', const GreatestOfScreen()),
        ),
        _MoreItem(
          icon: Icons.auto_fix_high_rounded,
          label: 'Set Builder',
          action: (ctx) =>
              liveOnly(ctx, 'Set Builder', const MobileSetBuilderTab()),
        ),
      ]),
      _MoreGroupData('Connect', [
        _MoreItem(
          icon: Icons.computer_rounded,
          label: 'Connect Computer',
          action: (ctx) {
            if (isGuestMode) {
              liveOnly(ctx, 'Connect Computer', const SizedBox.shrink());
              return;
            }
            _openConnectComputerSheet(ctx);
          },
        ),
      ]),
      _MoreGroupData('Community', [
        _MoreItem(
          icon: Icons.groups_rounded,
          label: 'Community',
          action: (ctx) => liveOnly(
            ctx,
            'Community',
            TutorialHost(
              section: AppSection.community,
              child: CommunityScreen(
                onUploadPressed: () => _push(
                  ctx,
                  const _MobilePage(title: 'Upload', child: UploadScreen()),
                ),
              ),
            ),
          ),
        ),
        _MoreItem(
          icon: Icons.person_rounded,
          label: 'My Profile',
          action: (ctx) => liveOnly(ctx, 'My Profile', const ProfileScreen()),
        ),
        _MoreItem(
          icon: Icons.explore_rounded,
          label: 'Discover DJs',
          action: (ctx) =>
              liveOnly(ctx, 'Discover DJs', const DiscoverDJsScreen()),
        ),
        _MoreItem(
          icon: Icons.cloud_upload_rounded,
          label: 'Upload',
          action: (ctx) => liveOnly(ctx, 'Upload', const UploadScreen()),
        ),
      ]),
      _MoreGroupData('Account', [
        _MoreItem(
          icon: Icons.settings_rounded,
          label: 'Settings',
          action: _openAccountSheet,
        ),
      ]),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _mobileAppBar('More'),
      body: ListView.separated(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (context, index) => _MoreGroup(group: groups[index]),
      ),
    );
  }

  bool _moreRouteRequiresPro(String title) {
    return switch (title) {
      'For You' || 'Artists' || 'Greatest Of' || 'Set Builder' => true,
      _ => false,
    };
  }
}

class _MoreGroupData {
  const _MoreGroupData(this.title, this.items);

  final String title;
  final List<_MoreItem> items;
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.label,
    required this.action,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext) action;
}

class _MoreGroup extends StatelessWidget {
  const _MoreGroup({required this.group});

  final _MoreGroupData group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
          child: Text(
            group.title,
            style: const TextStyle(
              color: AppTheme.sectionHeader,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.panel.withValues(alpha: 0.72),
              border: Border.all(color: AppTheme.hairline),
              borderRadius: BorderRadius.circular(AppTheme.rMd),
            ),
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  _MoreRow(item: group.items[i]),
                  if (i != group.items.length - 1)
                    Divider(
                      height: 1,
                      indent: 62,
                      color: AppTheme.edge.withValues(alpha: 0.34),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.item});

  final _MoreItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => item.action(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.cyan.withValues(alpha: 0.14),
                  ),
                ),
                child: Icon(item.icon, color: AppTheme.cyan, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
