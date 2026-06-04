import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/session_state.dart';
import '../../models/track.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state.dart';
import '../features/ai_copilot/ai_copilot_screen.dart';
import '../features/artists/artists_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/discover_djs_screen.dart';
import '../features/community/profile_screen.dart';
import '../features/community/upload_screen.dart';
import '../features/duplicates/duplicates_screen.dart';
import '../features/exports/exports_screen.dart';
import '../features/for_you/for_you_screen.dart';
import '../features/greatest_of/greatest_of_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/search/search_screen.dart';
import '../features/trending/trending_screen.dart';
import '../widgets/vibe_backdrop.dart';
import 'mobile_settings_sheet.dart';
import 'setlists_tab.dart';

/// Mobile-native shell — a bottom-tab navigation that mirrors the macOS app's
/// feature set and design language, reusing the same feature screens laid out
/// for touch. Primary destinations live in the bottom bar; the rest are reached
/// from the More tab.
class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _index = 0;
  final Set<int> _visited = {0};

  static const List<Widget> _tabs = [
    _HomeTab(),
    _MobilePage(title: 'Trending', child: TrendingScreen()),
    _MobilePage(title: 'AI Copilot', child: AiCopilotScreen()),
    _MobilePage(title: 'Library', child: LibraryScreen()),
    _MoreTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: VibeBackdrop(
        compact: true,
        child: SafeArea(
          bottom: false,
          // Lazily build tabs: a tab only renders once visited, so the shell
          // stays light (each macOS feature screen opens its own provider subs).
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.local_fire_department_rounded),
            label: 'Trending',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_rounded),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ── Shared chrome ────────────────────────────────────────────────────────────

/// Standard mobile app bar in the VibeRadar style.
PreferredSizeWidget _mobileAppBar(String title, [List<Widget>? actions]) {
  return AppBar(
    title: Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    backgroundColor: AppTheme.panel,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    actions: actions,
  );
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

// ── Home tab ─────────────────────────────────────────────────────────────────

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session =
        ref.watch(sessionProvider).value ?? const SessionState.demo();
    final userProfile = ref.watch(userProfileProvider).value ??
        UserProfile.empty(
          id: session.userId,
          displayName: session.displayName,
          preferredRegion: 'GH',
        );
    final allTracks = ref.watch(trackStreamProvider).value ?? const <Track>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _mobileAppBar('VibeRadar', [
        IconButton(
          icon: const Icon(Icons.search, color: AppTheme.textSecondary),
          tooltip: 'Search',
          onPressed: () => _push(
            context,
            const _MobilePage(title: 'Search', child: SearchScreen()),
          ),
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

class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, WidgetBuilder)>[
      (
        Icons.favorite_rounded,
        'For You',
        (ctx) => _MobilePage(
              title: 'For You',
              child: ForYouScreen(
                onOpenArtist: (_) => _push(
                  ctx,
                  const _MobilePage(title: 'Artists', child: ArtistsScreen()),
                ),
              ),
            ),
      ),
      (
        Icons.mic_external_on_rounded,
        'Artists',
        (_) => const _MobilePage(title: 'Artists', child: ArtistsScreen()),
      ),
      (
        Icons.queue_music_rounded,
        'Setlists',
        (_) => const SetlistsTab(),
      ),
      (
        Icons.star_rounded,
        'Greatest Of',
        (_) =>
            const _MobilePage(title: 'Greatest Of', child: GreatestOfScreen()),
      ),
      (
        Icons.groups_rounded,
        'Community',
        (_) => const _MobilePage(title: 'Community', child: CommunityScreen()),
      ),
      (
        Icons.person_rounded,
        'My Profile',
        (_) => const _MobilePage(title: 'My Profile', child: ProfileScreen()),
      ),
      (
        Icons.explore_rounded,
        'Discover DJs',
        (_) =>
            const _MobilePage(title: 'Discover DJs', child: DiscoverDJsScreen()),
      ),
      (
        Icons.cloud_upload_rounded,
        'Upload',
        (_) => const _MobilePage(title: 'Upload', child: UploadScreen()),
      ),
      (
        Icons.content_copy_rounded,
        'Duplicates',
        (_) => const _MobilePage(title: 'Duplicates', child: DuplicatesScreen()),
      ),
      (
        Icons.ios_share_rounded,
        'Exports',
        (_) => const _MobilePage(title: 'Exports', child: ExportsScreen()),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _mobileAppBar('More'),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: AppTheme.edge.withValues(alpha: 0.4),
          indent: 56,
          endIndent: 16,
        ),
        itemBuilder: (context, i) {
          if (i == items.length) {
            return ListTile(
              leading: const Icon(
                Icons.settings_rounded,
                color: AppTheme.textSecondary,
              ),
              title: const Text(
                'Settings',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppTheme.textTertiary,
                size: 20,
              ),
              onTap: () => _openAccountSheet(context),
            );
          }
          final (icon, label, builder) = items[i];
          return ListTile(
            leading: Icon(icon, color: AppTheme.textSecondary),
            title: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: 20,
            ),
            onTap: () => _push(context, builder(context)),
          );
        },
      ),
    );
  }
}
