import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_section.dart';
import '../widgets/source_badges.dart';
import '../widgets/track_action_menu.dart';
import '../../models/crate.dart';
import '../../models/session_state.dart';
import '../../models/track.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/repositories.dart';
import 'dart:async';
import 'dart:developer' as developer;
import '../../models/library_track.dart';
import '../../services/export_service.dart';
import '../../services/greatest_of_service.dart';
import '../../services/platform_search_service.dart';
import '../../services/playlist_aggregation_service.dart';
import '../../services/ingest_service.dart';
import '../widgets/command_palette.dart';
import '../widgets/drop_target_shell.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/track_detail_panel.dart';
import '../features/artists/artists_screen.dart';
import '../features/for_you/for_you_screen.dart';
import '../features/greatest_of/greatest_of_screen.dart';
import '../features/ai_copilot/ai_copilot_screen.dart';
import '../features/library/library_screen.dart';
import '../features/duplicates/duplicates_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/profile_screen.dart';
import '../features/community/upload_screen.dart';
import '../features/community/discover_djs_screen.dart';
import '../features/exports/exports_screen.dart';
import '../features/home/home_screen.dart';
import '../features/trending/trending_screen.dart';
import '../features/search/search_screen.dart';
import 'pair_phone_screen.dart';

part 'vibe_shell_cards.dart';
part 'vibe_shell_views.dart';
part 'vibe_shell_playlists.dart';
part 'vibe_shell_crates.dart';
part 'vibe_shell_setbuilder.dart';

class VibeShell extends ConsumerStatefulWidget {
  const VibeShell({
    super.key,
    required this.statusMessage,
    this.isDemoMode = false,
  });

  final String statusMessage;
  final bool isDemoMode;

  @override
  ConsumerState<VibeShell> createState() => _VibeShellState();
}

class _VibeShellState extends ConsumerState<VibeShell> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final FocusNode _filterFocusNode;
  Timer? _autoIngestTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _filterFocusNode = FocusNode();

    // Auto-ingest on app start (after a short delay to let UI settle)
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) _autoIngest();
    });

    // Auto-ingest every 60 minutes while app is running (cost-conscious)
    _autoIngestTimer = Timer.periodic(const Duration(minutes: 60), (_) {
      if (mounted) _autoIngest();
    });
  }

  Future<void> _autoIngest() async {
    final session = ref.read(sessionProvider).value;
    if (session?.isAuthenticated != true) return;

    try {
      await IngestService.triggerIngest();
      // After ingest writes new data, refresh the local cache
      await ref.read(trackRepositoryProvider).refresh();
    } catch (_) {
      // Silent — background ingest should not interrupt the user
    }
  }

  /// Opens the ⌘K / Ctrl+K global command palette.
  void _openCommandPalette() {
    showCommandPalette(
      context,
      onNavigate: (section) {
        ref.read(workspaceControllerProvider.notifier).setSection(section);
      },
      onOpenTrack: (libraryTrack) {
        // Navigate to Library and best-effort highlight if the online catalogue
        // has a matching id. LibraryTrack ids don't always line up with Track
        // ids, so this is a v1 heuristic — future: dedicated library detail.
        ref
            .read(workspaceControllerProvider.notifier)
            .setSection(AppSection.library);
        final allTracks =
            ref.read(trackStreamProvider).value ?? const <Track>[];
        final match = allTracks.firstWhereOrNull(
          (t) => t.id == libraryTrack.id,
        );
        if (match != null) {
          ref
              .read(workspaceControllerProvider.notifier)
              .activateTrack(match.id);
        }
      },
    );
  }

  @override
  void dispose() {
    _autoIngestTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _filterFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceControllerProvider);
    final tracksAsync = ref.watch(trackStreamProvider);
    final visibleTracks = ref.watch(visibleTracksProvider);
    final selectedTrack = ref.watch(selectedTrackProvider);
    final session =
        ref.watch(sessionProvider).value ?? const SessionState.demo();
    final userProfile =
        ref.watch(userProfileProvider).value ??
        UserProfile.empty(
          id: session.userId,
          displayName: session.displayName,
          preferredRegion: 'GH',
        );
    final genres = ref.watch(availableGenresProvider);
    final vibes = ref.watch(availableVibesProvider);
    final regions = ref.watch(availableRegionsProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    if (_searchController.text != workspace.searchQuery) {
      _searchController.value = TextEditingValue(
        text: workspace.searchQuery,
        selection: TextSelection.collapsed(
          offset: workspace.searchQuery.length,
        ),
      );
    }

    Widget mainPanel() => _buildMainPanel(
      context: context,
      workspace: workspace,
      allTracks: allTracks,
      visibleTracks: visibleTracks,
      tracksAsync: tracksAsync,
      session: session,
      userProfile: userProfile,
      genres: genres,
      vibes: vibes,
      regions: regions,
    );

    Widget sidebar({BuildContext? drawerContext}) => SidebarNav(
      selectedSection: workspace.section,
      statusMessage: widget.statusMessage,
      isDemoMode: widget.isDemoMode,
      onSelected: (section) {
        ref.read(workspaceControllerProvider.notifier).setSection(section);
        if (drawerContext != null) {
          Navigator.of(drawerContext).maybePop();
        }
      },
      onRefreshComplete: () => ref.read(trackRepositoryProvider).refresh(),
    );

    Widget detailPanel() => TrackDetailPanel(
      selectedTrack: selectedTrack,
      allTracks: allTracks,
      watchlist: userProfile.watchlist,
      expanded: workspace.detailExpanded,
      onToggleExpanded: () =>
          ref.read(workspaceControllerProvider.notifier).toggleDetailExpanded(),
      onToggleWatchlist: (trackId) => _toggleWatchlist(
        session: session,
        userProfile: userProfile,
        trackId: trackId,
      ),
    );

    return DropTargetShell(
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
              _openCommandPalette,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _openCommandPalette,
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = MediaQuery.sizeOf(context).width;
              final compact = viewportWidth < 960;
              final body = _showDetailPanel(workspace.section) && !compact
                  ? Row(
                      children: [
                        Expanded(child: mainPanel()),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: workspace.detailExpanded ? 420 : 360,
                          child: detailPanel(),
                        ),
                      ],
                    )
                  : mainPanel();

              if (compact) {
                final drawerWidth = viewportWidth < 360
                    ? viewportWidth * 0.88
                    : 300.0;

                return Scaffold(
                  backgroundColor: AppTheme.ink,
                  drawerScrimColor: Colors.black.withValues(alpha: 0.62),
                  drawer: Drawer(
                    width: drawerWidth,
                    backgroundColor: AppTheme.panel,
                    surfaceTintColor: Colors.transparent,
                    child: SafeArea(
                      child: Builder(
                        builder: (drawerContext) =>
                            sidebar(drawerContext: drawerContext),
                      ),
                    ),
                  ),
                  appBar: AppBar(
                    toolbarHeight: 56,
                    backgroundColor: AppTheme.panel,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    leading: Builder(
                      builder: (scaffoldContext) => IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu_rounded),
                        color: AppTheme.textPrimary,
                        onPressed: () =>
                            Scaffold.of(scaffoldContext).openDrawer(),
                      ),
                    ),
                    titleSpacing: 0,
                    title: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.violet, AppTheme.pink],
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.radio_button_checked,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            workspace.section.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        tooltip: 'Command palette',
                        icon: const Icon(Icons.manage_search_rounded),
                        color: AppTheme.textSecondary,
                        onPressed: _openCommandPalette,
                      ),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Divider(
                        height: 1,
                        color: AppTheme.edge.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  body: SafeArea(top: false, child: body),
                );
              }

              return Scaffold(
                backgroundColor: AppTheme.ink,
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        SizedBox(width: 262, child: sidebar()),
                        const SizedBox(width: 20),
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainPanel({
    required BuildContext context,
    required WorkspaceState workspace,
    required List<Track> allTracks,
    required List<Track> visibleTracks,
    required AsyncValue<List<Track>> tracksAsync,
    required SessionState session,
    required UserProfile userProfile,
    required List<String> genres,
    required List<String> vibes,
    required List<String> regions,
  }) {
    switch (workspace.section) {
      case AppSection.forYou:
        return ForYouScreen(
          onOpenArtist: (name) {
            ref
                .read(workspaceControllerProvider.notifier)
                .setSection(AppSection.artists);
          },
        );
      case AppSection.home:
        return HomeScreen(allTracks: allTracks, userProfile: userProfile);
      case AppSection.trending:
        return const TrendingScreen();
      case AppSection.search:
        return const SearchScreen();
      case AppSection.regions:
        return _RegionsView(
          tracks: allTracks,
          activeRegion: workspace.filters.region,
          ref: ref,
          onSelectRegion: (region) => ref
              .read(workspaceControllerProvider.notifier)
              .updateFilters(workspace.filters.copyWith(region: region)),
          onOpenRegionWorkbench: (region) {
            ref
                .read(workspaceControllerProvider.notifier)
                .updateFilters(workspace.filters.copyWith(region: region));
            ref
                .read(workspaceControllerProvider.notifier)
                .setSection(AppSection.trending);
          },
          onActivateTrack: (trackId) => ref
              .read(workspaceControllerProvider.notifier)
              .activateTrack(trackId),
        );
      case AppSection.genres:
        return _GenresView(
          tracks: allTracks,
          ref: ref,
          onSelectGenre: (genre) {
            ref
                .read(workspaceControllerProvider.notifier)
                .updateFilters(workspace.filters.copyWith(genre: genre));
            ref
                .read(workspaceControllerProvider.notifier)
                .setSection(AppSection.trending);
          },
        );
      case AppSection.setBuilder:
        return _SetBuilderView(
          allTracks: allTracks,
          genres: genres,
          vibes: vibes,
          session: session,
          userProfile: userProfile,
        );
      case AppSection.savedCrates:
        return _SavedCratesView(
          allTracks: allTracks,
          crates: userProfile.savedCrates,
        );
      case AppSection.watchlist:
        return _WatchlistView(
          tracks: allTracks
              .where((track) => userProfile.watchlist.contains(track.id))
              .toList(),
          onRemove: (trackId) => _toggleWatchlist(
            session: session,
            userProfile: userProfile,
            trackId: trackId,
          ),
        );
      case AppSection.artists:
        return const ArtistsScreen();
      case AppSection.greatestOf:
        return const GreatestOfScreen();
      case AppSection.aiCopilot:
        return const AiCopilotScreen();
      case AppSection.playlists:
        return const _PlaylistsView();
      case AppSection.community:
        return const CommunityScreen();
      case AppSection.myProfile:
        return const ProfileScreen();
      case AppSection.upload:
        return const UploadScreen();
      case AppSection.discoverDJs:
        return const DiscoverDJsScreen();
      case AppSection.library:
        return const LibraryScreen();
      case AppSection.duplicates:
        return const DuplicatesScreen();
      case AppSection.exports:
        return const ExportsScreen();
      case AppSection.settings:
        return _SettingsView(
          session: session,
          userProfile: userProfile,
          regions: regions.where((item) => item != 'Global').toList(),
        );
    }
  }

  /// Only show the right-side detail panel for table-based views.
  bool _showDetailPanel(AppSection section) {
    return false; // No detail panel for any section
  }

  Future<void> _toggleWatchlist({
    required SessionState session,
    required UserProfile userProfile,
    required String trackId,
  }) {
    return ref
        .read(userRepositoryProvider)
        .toggleWatchlist(
          userId: session.userId,
          fallbackName: session.displayName,
          trackId: trackId,
        );
  }
}
