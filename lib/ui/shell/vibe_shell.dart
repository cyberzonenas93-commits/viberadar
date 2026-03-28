import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
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
import '../../models/track_filters.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/repositories.dart';
import '../../providers/streaming_provider.dart';
import 'dart:async';
import '../../models/library_track.dart';
import '../../services/export_service.dart';
import '../../services/greatest_of_service.dart';
import '../../services/platform_search_service.dart';
import '../../services/playlist_aggregation_service.dart';
import '../../services/ingest_service.dart';
import '../../services/set_builder_service.dart';
import '../widgets/dashboard_cards.dart';
import '../widgets/filter_bar.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/track_detail_panel.dart';
import '../widgets/track_table.dart';
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
import '../features/streaming/streaming_screen.dart';
import '../widgets/apple_music_player_bar.dart';
import '../widgets/dj_player_bar.dart';
import '../widgets/video_player_overlay.dart';
import '../../providers/dj_player_provider.dart';

class VibeShell extends ConsumerStatefulWidget {
  const VibeShell({super.key, required this.statusMessage});

  final String statusMessage;

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
    _autoIngestTimer = Timer.periodic(
      const Duration(minutes: 60),
      (_) { if (mounted) _autoIngest(); },
    );
  }

  Future<void> _autoIngest() async {
    try {
      await IngestService.triggerIngest();
      // After ingest writes new data, refresh the local cache
      await ref.read(trackRepositoryProvider).refresh();
    } catch (_) {
      // Silent — background ingest should not interrupt the user
    }
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

    final dj = ref.watch(djPlayerProvider);

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, dj.isVisible ? 210 : 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 262,
                    child: SidebarNav(
                      selectedSection: workspace.section,
                      statusMessage: widget.statusMessage,
                      onSelected: (section) => ref
                          .read(workspaceControllerProvider.notifier)
                          .setSection(section),
                      onRefreshComplete: () =>
                          ref.read(trackRepositoryProvider).refresh(),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _showDetailPanel(workspace.section)
                        ? Row(
                            children: [
                              Expanded(
                                child: _buildMainPanel(
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
                                ),
                              ),
                              const SizedBox(width: 20),
                              SizedBox(
                                width: workspace.detailExpanded ? 420 : 360,
                                child: TrackDetailPanel(
                                  selectedTrack: selectedTrack,
                                  allTracks: allTracks,
                                  watchlist: userProfile.watchlist,
                                  expanded: workspace.detailExpanded,
                                  onToggleExpanded: () => ref
                                      .read(workspaceControllerProvider.notifier)
                                      .toggleDetailExpanded(),
                                  onToggleWatchlist: (trackId) => _toggleWatchlist(
                                    session: session,
                                    userProfile: userProfile,
                                    trackId: trackId,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : _buildMainPanel(
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
                          ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                AppleMusicPlayerBar(),
                DjPlayerBar(),
              ],
            ),
          ),
          // Video player overlay (floating, draggable)
          const VideoPlayerOverlay(),
        ],
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
        return HomeScreen(
          allTracks: allTracks,
          userProfile: userProfile,
        );
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
      case AppSection.streaming:
        return const StreamingScreen();
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

class _WorkbenchView extends StatelessWidget {
  const _WorkbenchView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.showDashboard,
    required this.allTracks,
    required this.visibleTracks,
    required this.filters,
    required this.userProfile,
    required this.genres,
    required this.vibes,
    required this.regions,
    required this.searchController,
    required this.searchFocusNode,
    required this.filterFocusNode,
    required this.selectedTrackIds,
    required this.primaryTrackId,
    required this.activeSortColumn,
    required this.sortAscending,
    required this.isLoading,
    required this.onSearchChanged,
    required this.onFiltersChanged,
    required this.onRefresh,
    required this.onSort,
    required this.onToggleSelection,
    required this.onActivateTrack,
  });

  final String title;
  final String subtitle;
  final bool showDashboard;
  final List<Track> allTracks;
  final List<Track> visibleTracks;
  final TrackFilters filters;
  final UserProfile userProfile;
  final List<String> genres;
  final List<String> vibes;
  final List<String> regions;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final FocusNode filterFocusNode;
  final Set<String> selectedTrackIds;
  final String? primaryTrackId;
  final TrackSortColumn activeSortColumn;
  final bool sortAscending;
  final bool isLoading;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<TrackFilters> onFiltersChanged;
  final VoidCallback onRefresh;
  final void Function(TrackSortColumn column, bool ascending) onSort;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onActivateTrack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleBlock(title: title, subtitle: subtitle),
        const SizedBox(height: 18),
        if (showDashboard) ...[
          DashboardCards(
            tracks: allTracks,
            preferredRegion: userProfile.preferredRegion,
          ),
          const SizedBox(height: 18),
        ],
        FilterBar(
          searchController: searchController,
          searchFocusNode: searchFocusNode,
          filterFocusNode: filterFocusNode,
          filters: filters,
          genres: genres,
          vibes: vibes,
          regions: regions,
          onSearchChanged: onSearchChanged,
          onFiltersChanged: onFiltersChanged,
          onRefresh: onRefresh,
        ),
        const SizedBox(height: 18),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : TrackTable(
                  tracks: visibleTracks,
                  selectedTrackIds: selectedTrackIds,
                  primaryTrackId: primaryTrackId,
                  activeRegion: filters.region,
                  watchlist: userProfile.watchlist,
                  sortColumn: activeSortColumn,
                  sortAscending: sortAscending,
                  onSort: onSort,
                  onToggleSelection: onToggleSelection,
                  onActivateTrack: onActivateTrack,
                ),
        ),
      ],
    );
  }
}

class _RegionsView extends StatefulWidget {
  const _RegionsView({
    required this.tracks,
    required this.activeRegion,
    required this.ref,
    required this.onSelectRegion,
    required this.onOpenRegionWorkbench,
    required this.onActivateTrack,
  });

  final List<Track> tracks;
  final String activeRegion;
  final WidgetRef ref;
  final ValueChanged<String> onSelectRegion;
  final ValueChanged<String> onOpenRegionWorkbench;
  final ValueChanged<String> onActivateTrack;

  @override
  State<_RegionsView> createState() => _RegionsViewState();
}

class _RegionsViewState extends State<_RegionsView> {
  String _selectedGenre = 'All';

  @override
  Widget build(BuildContext context) {
    // Build genre list from tracks
    final genreSet = <String>{};
    for (final t in widget.tracks) {
      if (t.genre.isNotEmpty) genreSet.add(t.genre);
    }
    final genres = ['All', ...genreSet.toList()..sort()];

    // Apply genre filter
    final tracks = _selectedGenre == 'All'
        ? widget.tracks
        : widget.tracks.where((t) => t.genre == _selectedGenre).toList();

    final regionStats = <String, double>{};
    for (final track in tracks) {
      for (final entry in track.regionScores.entries) {
        regionStats.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    final regions = regionStats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fallbackRegion = regions.firstOrNull?.key ?? 'Global';
    final selectedRegion =
        widget.activeRegion == 'Global' ? fallbackRegion : widget.activeRegion;
    final focusedTracks = [...tracks]
      ..sort(
        (a, b) => regionScoreForTrack(b, selectedRegion)
            .compareTo(regionScoreForTrack(a, selectedRegion)),
      );
    final regionalLeaders = focusedTracks
        .where((track) => regionScoreForTrack(track, selectedRegion) > 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public_rounded,
                          color: AppTheme.pink, size: 24),
                      const SizedBox(width: 10),
                      Text('Regional Pulse',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${regionalLeaders.length} tracks in ${formatRegionLabel(selectedRegion)}${_selectedGenre != 'All' ? ' · $_selectedGenre' : ''}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              // Genre filter dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                ),
                child: DropdownButton<String>(
                  value: genres.contains(_selectedGenre) ? _selectedGenre : 'All',
                  dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  underline: const SizedBox(),
                  isDense: true,
                  items: genres.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (v) { if (v != null) setState(() => _selectedGenre = v); },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => widget.onOpenRegionWorkbench(selectedRegion),
                icon: const Icon(Icons.table_rows_rounded, size: 16),
                label: const Text('Open in table'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Region selector chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: regions.take(12).map((entry) {
                final selected = entry.key == selectedRegion;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: selected,
                    label: Text(entry.key),
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    backgroundColor: AppTheme.panel,
                    selectedColor: AppTheme.cyan.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: selected
                          ? AppTheme.cyan.withValues(alpha: 0.5)
                          : AppTheme.edge.withValues(alpha: 0.5),
                    ),
                    onSelected: (_) => widget.onSelectRegion(entry.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artwork grid
        Expanded(
          child: regionalLeaders.isEmpty
              ? const Center(
                  child: Text('No tracks match this region',
                      style: TextStyle(color: AppTheme.textTertiary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: regionalLeaders.length,
                  itemBuilder: (context, i) {
                    final track = regionalLeaders[i];
                    final score =
                        (regionScoreForTrack(track, selectedRegion) * 100)
                            .toInt();
                    return _ShellTrackCard(
                      track: track,
                      rank: i + 1,
                      score: score,
                      ref: widget.ref,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GenresView extends StatefulWidget {
  const _GenresView({required this.tracks, required this.ref, required this.onSelectGenre});

  final List<Track> tracks;
  final WidgetRef ref;
  final ValueChanged<String> onSelectGenre;

  @override
  State<_GenresView> createState() => _GenresViewState();
}

class _GenresViewState extends State<_GenresView> {
  String _selectedGenre = 'All';

  @override
  Widget build(BuildContext context) {
    final genreStats = <String, List<Track>>{};
    for (final track in widget.tracks) {
      if (track.genre.isNotEmpty) {
        genreStats.putIfAbsent(track.genre, () => []).add(track);
      }
    }
    final genreNames = genreStats.keys.toList()..sort();

    final displayTracks = _selectedGenre == 'All'
        ? ([...widget.tracks]
          ..sort((a, b) => b.trendScore.compareTo(a.trendScore)))
        : ([...(genreStats[_selectedGenre] ?? <Track>[])]
          ..sort((a, b) => b.trendScore.compareTo(a.trendScore)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.library_music_rounded,
                          color: AppTheme.violet, size: 24),
                      const SizedBox(width: 10),
                      Text('Genre Landscape',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${displayTracks.length} tracks${_selectedGenre != 'All' ? ' in $_selectedGenre' : ' across ${genreNames.length} genres'}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Genre selector chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: _selectedGenre == 'All',
                    label: const Text('All'),
                    labelStyle: TextStyle(
                      color: _selectedGenre == 'All'
                          ? Colors.white
                          : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    backgroundColor: AppTheme.panel,
                    selectedColor: AppTheme.violet.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _selectedGenre == 'All'
                          ? AppTheme.violet.withValues(alpha: 0.5)
                          : AppTheme.edge.withValues(alpha: 0.5),
                    ),
                    onSelected: (_) => setState(() => _selectedGenre = 'All'),
                  ),
                ),
                ...genreNames.map((genre) {
                  final selected = genre == _selectedGenre;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: selected,
                      label: Text('$genre (${genreStats[genre]!.length})'),
                      labelStyle: TextStyle(
                        color:
                            selected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                      backgroundColor: AppTheme.panel,
                      selectedColor: AppTheme.violet.withValues(alpha: 0.25),
                      side: BorderSide(
                        color: selected
                            ? AppTheme.violet.withValues(alpha: 0.5)
                            : AppTheme.edge.withValues(alpha: 0.5),
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedGenre = genre),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artwork grid
        Expanded(
          child: displayTracks.isEmpty
              ? const Center(
                  child: Text('No tracks in this genre',
                      style: TextStyle(color: AppTheme.textTertiary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: displayTracks.length,
                  itemBuilder: (context, i) {
                    final track = displayTracks[i];
                    final score = (track.trendScore * 100).toInt();
                    return _ShellTrackCard(
                      track: track,
                      rank: i + 1,
                      score: score,
                      ref: widget.ref,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Set slot model ────────────────────────────────────────────────────────────

enum _SortMode { all, trending, hottest, rising, greatestOf }

class _SetSlot {
  String genre;
  _SortMode mode;
  int count;
  String artist; // comma-separated artist names
  String region;
  int? yearFrom;
  int? yearTo;
  int minBpm;
  int maxBpm;

  _SetSlot({
    this.genre = 'Afrobeats',
    this.mode = _SortMode.trending,
    this.count = 20,
    this.artist = '',
    this.region = 'All',
    this.yearFrom,
    this.yearTo,
    this.minBpm = 60,
    this.maxBpm = 200,
  });

  String get modeLabel => switch (mode) {
    _SortMode.all => 'All Best',
    _SortMode.trending => 'Top Trending',
    _SortMode.hottest => 'Hottest',
    _SortMode.rising => 'Rising Fast',
    _SortMode.greatestOf => 'Greatest Of',
  };
}

// ── Set Builder View ──────────────────────────────────────────────────────────

class _SetBuilderView extends ConsumerStatefulWidget {
  const _SetBuilderView({
    required this.allTracks,
    required this.genres,
    required this.vibes,
    required this.session,
    required this.userProfile,
  });

  final List<Track> allTracks;
  final List<String> genres;
  final List<String> vibes;
  final SessionState session;
  final UserProfile userProfile;

  @override
  ConsumerState<_SetBuilderView> createState() => _SetBuilderViewState();
}

class _SetBuilderViewState extends ConsumerState<_SetBuilderView> {
  final _greatestOf = GreatestOfService();
  final _platformSearch = PlatformSearchService();
  final List<_SetSlot> _slots = [
    _SetSlot(genre: 'Afrobeats', mode: _SortMode.trending, count: 30),
    _SetSlot(genre: 'R&B', mode: _SortMode.hottest, count: 20),
    _SetSlot(genre: 'Hip-Hop', mode: _SortMode.trending, count: 20),
  ];
  List<Track> _generated = const [];
  List<AiCrateTrack> _platformTracks = const [];
  bool _searchingPlatforms = false;
  String _crateName = 'My Set';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  Widget build(BuildContext context) {
    final totalRequested = _slots.fold<int>(0, (sum, s) => sum + s.count);

    return CustomScrollView(
      slivers: [
        // ── Header ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Row(
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: AppTheme.amber, size: 24),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set Builder', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
                    Text(
                      '${_platformTracks.length} / $totalRequested tracks from Apple Music, Spotify & YouTube'
                      '${_searchingPlatforms ? ' · searching…' : ''}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 150, height: 36,
                  child: TextField(
                    onChanged: (v) => _crateName = v,
                    controller: TextEditingController(text: _crateName),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Crate name…',
                      hintStyle: const TextStyle(color: AppTheme.textTertiary),
                      filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _regenerate,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Build Set'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _platformTracks.isEmpty ? null : _saveCrate,
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Save Crate'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    // Build AI prompt from current slot config
                    final slotDesc = _slots.map((s) => '${s.count} ${s.modeLabel} ${s.genre}${s.artist.isNotEmpty ? ' by ${s.artist}' : ''}').join(', ');
                    ref.read(workspaceControllerProvider.notifier).setSection(AppSection.aiCopilot);
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('Ask AI'),
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.amber.withValues(alpha: 0.2), foregroundColor: AppTheme.amber),
                ),
              ],
            ),
          ),
        ),

        // ── Slot table ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
            child: Column(
              children: [
                // Column headers
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: const [
                      SizedBox(width: 32),
                      _ColHeader('MODE', 110),
                      _ColHeader('GENRE', 120),
                      _ColHeader('ARTIST', 0, flex: true),
                      _ColHeader('REGION', 70),
                      _ColHeader('YEARS', 110),
                      _ColHeader('BPM', 110),
                      _ColHeader('TRACKS', 100),
                      SizedBox(width: 32),
                    ],
                  ),
                ),
                // Slot rows
                for (var i = 0; i < _slots.length; i++)
                  _buildSlotRow(i),
                // Add slot button
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _slots.add(_SetSlot())),
                        icon: const Icon(Icons.add_circle_rounded, size: 18, color: AppTheme.cyan),
                        label: const Text('Add Slot', style: TextStyle(color: AppTheme.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const Spacer(),
                      Text('$totalRequested tracks total',
                          style: const TextStyle(color: AppTheme.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 20)),

        // ── Generated grid (from platforms) ──
        if (_platformTracks.isEmpty && !_searchingPlatforms)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.library_music_rounded, color: AppTheme.textTertiary.withValues(alpha: 0.4), size: 48),
                  const SizedBox(height: 12),
                  const Text('Configure your slots and hit Build Set', style: TextStyle(color: AppTheme.textTertiary)),
                ],
              ),
            ),
          )
        else if (_searchingPlatforms && _platformTracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2),
                  SizedBox(height: 16),
                  Text('Searching Apple Music, Spotify & YouTube…', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final t = _platformTracks[i];
                  return _PlatformResultCard(track: t, index: i);
                },
                childCount: _platformTracks.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSlotRow(int index) {
    final slot = _slots[index];
    final genreOptions = ['All', 'Afrobeats', 'Amapiano', 'Hip-Hop', 'R&B', 'House',
        'Dancehall', 'Pop', 'Latin', 'Drill', 'Dance', 'UK Garage',
        ...widget.genres.where((g) => g != 'All')].toSet().toList();
    final regionOptions = ['All', 'GH', 'NG', 'ZA', 'GB', 'US', 'DE'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Slot badge
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.cyan]),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Center(child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 6),
          // Mode
          SizedBox(
            width: 110,
            child: _pill(
              child: DropdownButton<_SortMode>(
                value: slot.mode, dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                underline: const SizedBox(), isDense: true, isExpanded: true,
                items: _SortMode.values.map((m) => DropdownMenuItem(value: m,
                  child: Text(switch (m) {
                    _SortMode.all => 'All Best',
                    _SortMode.trending => 'Trending',
                    _SortMode.hottest => 'Hottest',
                    _SortMode.rising => 'Rising',
                    _SortMode.greatestOf => 'Greatest',
                  }, style: const TextStyle(fontSize: 12)),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => slot.mode = v); },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Genre
          SizedBox(
            width: 120,
            child: _pill(
              child: DropdownButton<String>(
                value: genreOptions.contains(slot.genre) ? slot.genre : 'All',
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                underline: const SizedBox(), isDense: true, isExpanded: true,
                items: genreOptions.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { if (v != null) setState(() => slot.genre = v); },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Artist
          Expanded(
            child: SizedBox(
              height: 32,
              child: TextField(
                onChanged: (v) => slot.artist = v.trim(),
                controller: TextEditingController(text: slot.artist),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Drake, Wizkid…',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Region
          SizedBox(
            width: 70,
            child: _pill(
              child: DropdownButton<String>(
                value: regionOptions.contains(slot.region) ? slot.region : 'All',
                dropdownColor: AppTheme.panelRaised,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                underline: const SizedBox(), isDense: true, isExpanded: true,
                items: regionOptions.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) { if (v != null) setState(() => slot.region = v); },
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Year From-To
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.yearFrom = int.tryParse(v),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'From', hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                        filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('–', style: TextStyle(color: AppTheme.textTertiary, fontSize: 10))),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.yearTo = int.tryParse(v),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'To', hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                        filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // BPM range
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.minBpm = int.tryParse(v) ?? 60,
                      controller: TextEditingController(text: slot.minBpm == 60 ? '' : '${slot.minBpm}'),
                      style: const TextStyle(color: AppTheme.amber, fontSize: 12),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '60', hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                        filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('–', style: TextStyle(color: AppTheme.textTertiary, fontSize: 10))),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      onChanged: (v) => slot.maxBpm = int.tryParse(v) ?? 200,
                      controller: TextEditingController(text: slot.maxBpm == 200 ? '' : '${slot.maxBpm}'),
                      style: const TextStyle(color: AppTheme.amber, fontSize: 12),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '200', hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                        filled: true, fillColor: AppTheme.panelRaised, isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Track count
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Text('${slot.count}', style: const TextStyle(color: AppTheme.amber, fontSize: 13, fontWeight: FontWeight.w800)),
                Expanded(
                  child: Slider(
                    min: 5, max: 500, divisions: 99,
                    value: slot.count.toDouble(),
                    onChanged: (v) => setState(() => slot.count = v.round()),
                  ),
                ),
              ],
            ),
          ),
          // Remove
          if (_slots.length > 1)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textTertiary),
              onPressed: () => setState(() => _slots.removeAt(index)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            )
          else
            const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _pill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  void _regenerate() {
    // Go straight to platforms — don't use Firestore
    setState(() {
      _generated = [];
      _platformTracks = [];
      _searchingPlatforms = true;
    });
    _buildFromPlatforms();
  }

  Future<void> _buildFromPlatforms() async {
    final allFound = <AiCrateTrack>[];
    final seen = <String>{};

    for (final slot in _slots) {
      final genre = slot.genre == 'All' ? 'music' : slot.genre;
      final modeHint = switch (slot.mode) {
        _SortMode.all => 'best top popular',
        _SortMode.trending => 'trending',
        _SortMode.hottest => 'hot new',
        _SortMode.rising => 'new rising',
        _SortMode.greatestOf => 'best greatest',
      };
      // Build BPM hint for search query when range is narrowed
      final bpmHint = (slot.minBpm > 60 || slot.maxBpm < 200)
          ? '${slot.minBpm}-${slot.maxBpm} bpm'
          : '';

      try {
        List<PlatformTrackResult> results;
        final yearHint = slot.yearFrom != null ? '${slot.yearFrom}s' : null;

        if (slot.artist.isNotEmpty) {
          // For artist searches with high counts, run multiple query variations
          // to get maximum coverage (platforms typically cap at ~50-100 per call)
          final allResults = <PlatformTrackResult>[];
          final allSeen = <String>{};

          final artistQueries = [
            '${slot.artist} $bpmHint'.trim(),
            '${slot.artist} best songs',
            '${slot.artist} top tracks',
            '${slot.artist} hits',
            '${slot.artist} popular',
            '${slot.artist} essential',
            '${slot.artist} discography',
          ];

          for (final q in artistQueries) {
            final batch = await _platformSearch.searchByArtist(
              q,
              limit: 50,
            );
            for (final r in batch) {
              final k = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
              if (allSeen.add(k)) allResults.add(r);
            }
            // Stop querying once we have enough (or close to enough)
            if (allResults.length >= slot.count) break;
          }
          results = allResults;
        } else if (slot.mode == _SortMode.all) {
          // "All Best" mode: run multiple search strategies for maximum coverage
          final allResults = <PlatformTrackResult>[];
          final allSeen = <String>{};
          for (final hint in [
            'best top popular', 'trending hit', 'classic essential',
            'new hot', 'playlist', 'top 100', 'greatest', 'chart',
            'viral', 'dance party',
          ]) {
            final batch = await _platformSearch.searchByGenre(
              '$hint $genre $bpmHint'.trim(),
              limit: 50,
              era: yearHint,
            );
            for (final r in batch) {
              final k = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
              if (allSeen.add(k)) allResults.add(r);
            }
            if (allResults.length >= slot.count) break;
          }
          results = allResults;
        } else {
          // For other modes with high counts, also run varied queries
          final allResults = <PlatformTrackResult>[];
          final allSeen = <String>{};

          final queries = [
            '$modeHint $genre $bpmHint'.trim(),
            '$modeHint $genre top songs',
            '$genre best ${slot.mode == _SortMode.trending ? 'new' : 'popular'}',
            '$genre playlist ${slot.mode.name}',
          ];

          for (final q in queries) {
            final batch = await _platformSearch.searchByGenre(
              q,
              limit: 50,
              era: yearHint,
            );
            for (final r in batch) {
              final k = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
              if (allSeen.add(k)) allResults.add(r);
            }
            if (allResults.length >= slot.count) break;
          }
          results = allResults;
        }

        // Add all unique results up to slot.count.
        // If fewer results exist than requested, add whatever is available
        // (never return 0 when there ARE results).
        int added = 0;
        for (final r in results) {
          if (added >= slot.count) break;
          final key = '${r.title.toLowerCase()}::${r.artist.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          allFound.add(AiCrateTrack(
            title: r.title,
            artist: r.artist,
            artworkUrl: r.artworkUrl,
            spotifyUrl: r.spotifyUrl,
            appleUrl: r.appleUrl,
            resolved: r.hasUrl,
          ));
          added++;
        }
      } catch (_) {}

      // Update UI after each slot completes
      if (mounted) {
        setState(() => _platformTracks = [...allFound]);
      }
    }

    if (mounted) {
      setState(() => _searchingPlatforms = false);
    }
  }

  Future<void> _saveCrate() async {
    if (_platformTracks.isEmpty) return;
    final name = _crateName.trim().isEmpty ? 'My Set' : _crateName.trim();

    // Save as AI crate (with play URLs)
    ref.read(aiCrateProvider.notifier).setCrate(name, _platformTracks);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crate saved to your workspace.')),
      );
    }
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, this.width, {this.flex = false});
  final String label;
  final double width;
  final bool flex;

  @override
  Widget build(BuildContext context) {
    final child = Text(label, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2));
    if (flex) return Expanded(child: child);
    return SizedBox(width: width, child: child);
  }
}

class _SlotFilter extends StatelessWidget {
  const _SlotFilter({required this.icon, required this.label, required this.child});
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textTertiary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        child,
      ],
    );
  }
}

class _SetBuilderDropdown extends StatelessWidget {
  const _SetBuilderDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.firstOrNull,
              isDense: true,
              dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 12),
              items: options
                  .map((o) =>
                      DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedCratesView extends ConsumerWidget {
  const _SavedCratesView({required this.allTracks, required this.crates});

  final List<Track> allTracks;
  final List<Crate> crates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiCrates = ref.watch(aiCrateProvider).crates;
    // Combine: AI crates + regular crates
    final allCrateNames = <String>{
      ...aiCrates.keys,
      ...crates.map((c) => c.name),
    };
    final hasCrates = allCrateNames.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Saved Crates',
          subtitle:
              'Your curated sets from AI Copilot and Set Builder — ready to play and export.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: !hasCrates
              ? Center(
                  child: Text(
                    'No crates yet. Use AI Copilot or Set Builder to create one.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                  children: [
                    // AI Crates (with playable links)
                    for (final entry in aiCrates.entries) ...[
                      _AiCrateCard(name: entry.key, tracks: entry.value),
                      const SizedBox(height: 12),
                    ],
                    // Regular crates (Firestore ID-based)
                    for (final crate in crates) ...[
                      _RegularCrateCard(crate: crate, allTracks: allTracks),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AiCrateCard extends ConsumerWidget {
  const _AiCrateCard({required this.name, required this.tracks});
  final String name;
  final List<AiCrateTrack> tracks;

  Future<void> _export(BuildContext context, String format) async {
    try {
      final svc = ExportService();
      String path;
      switch (format) {
        case 'm3u':
          path = await svc.exportAiCrateM3u(name, tracks);
        case 'csv':
          path = await svc.exportAiCrateCsv(name, tracks);
        case 'rekordbox':
          path = await svc.exportAiCrateRekordbox(name, tracks);
        case 'virtualdj':
          path = await svc.exportAiCrateVirtualDj(name, tracks);
        case 'traktor':
          path = await svc.exportAiCrateTraktor(name, tracks);
        case 'manifest':
          path = await svc.exportAiCrateManifest(name, tracks);
        default:
          return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $path'),
            backgroundColor: AppTheme.lime,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Show in Finder',
              textColor: Colors.white,
              onPressed: () => ExportService.revealInFinder(path),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete "$name"?', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('This will permanently remove this AI crate and its ${tracks.length} tracks.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(aiCrateProvider.notifier).deleteCrate(name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$name"'), backgroundColor: AppTheme.pink, duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = tracks.where((t) => t.resolved).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.violet.withValues(alpha: 0.06), AppTheme.panel],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.pink]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 10),
                    SizedBox(width: 4),
                    Text('AI', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text('$resolved/${tracks.length} playable',
                  style: TextStyle(color: resolved == tracks.length ? AppTheme.lime : AppTheme.amber, fontSize: 11)),
              const SizedBox(width: 8),
              // ── Delete button ──
              Tooltip(
                message: 'Delete crate',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _confirmDelete(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded, color: Colors.red.withValues(alpha: 0.6), size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Export buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ExportBtn(label: 'M3U', icon: Icons.queue_music_rounded, onTap: () => _export(context, 'm3u')),
                const SizedBox(width: 6),
                _ExportBtn(label: 'CSV', icon: Icons.table_chart_rounded, onTap: () => _export(context, 'csv')),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Rekordbox', icon: Icons.album_rounded, onTap: () => _export(context, 'rekordbox')),
                const SizedBox(width: 6),
                _ExportBtn(label: 'VirtualDJ', icon: Icons.surround_sound_rounded, onTap: () => _export(context, 'virtualdj')),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Traktor', icon: Icons.speaker_rounded, onTap: () => _export(context, 'traktor')),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Manifest', icon: Icons.description_rounded, onTap: () => _export(context, 'manifest')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < tracks.length; i++) ...[
            _AiTrackRow(track: tracks[i], index: i, crateName: name),
            if (i < tracks.length - 1) Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
        ],
      ),
    );
  }
}

class _AiTrackRow extends ConsumerWidget {
  const _AiTrackRow({required this.track, required this.index, required this.crateName});
  final AiCrateTrack track;
  final int index;
  final String crateName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text('${index + 1}', textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          // Artwork
          if (track.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(imageUrl: track.artworkUrl!, width: 36, height: 36, fit: BoxFit.cover),
            )
          else
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16),
            ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(track.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // BPM + Key
          if (track.bpm > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('${track.bpm}', style: const TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          if (track.key.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
              child: Text(track.key, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          // Play buttons
          if (track.spotifyUrl != null)
            _PlatformPlayBtn(icon: Icons.graphic_eq_rounded, color: const Color(0xFF1ED760), url: track.spotifyUrl!, tooltip: 'Play',
              onTap: () => ref.read(appleMusicProvider.notifier).playByQuery(track.title, track.artist)),
          if (track.appleUrl != null)
            _PlatformPlayBtn(icon: Icons.music_note_rounded, color: const Color(0xFFFF7AB5), url: track.appleUrl!, tooltip: 'Play',
              onTap: () => ref.read(appleMusicProvider.notifier).playByQuery(track.title, track.artist)),
          if (!track.resolved)
            const Tooltip(
              message: 'Not found on platforms',
              child: Icon(Icons.cloud_off_rounded, color: AppTheme.textTertiary, size: 16),
            ),
          // ── Remove track button ──
          const SizedBox(width: 4),
          Tooltip(
            message: 'Remove from crate',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  ref.read(aiCrateProvider.notifier).removeTrackFromCrate(crateName, index);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed "${track.title}" from $crateName'),
                      backgroundColor: AppTheme.pink,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, color: AppTheme.textTertiary.withValues(alpha: 0.5), size: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformPlayBtn extends StatelessWidget {
  const _PlatformPlayBtn({required this.icon, required this.color, required this.url, required this.tooltip, this.onTap});
  final IconData icon;
  final Color color;
  final String url;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap ?? () {
            final uri = Uri.tryParse(url);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  const _ExportBtn({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppTheme.cyan, size: 14),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegularCrateCard extends ConsumerWidget {
  const _RegularCrateCard({required this.crate, required this.allTracks});
  final Crate crate;
  final List<Track> allTracks;

  Future<void> _export(BuildContext context, String format, List<Track> tracks) async {
    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporting $format...'), backgroundColor: AppTheme.cyan, duration: const Duration(seconds: 1)),
    );

    final svc = ExportService();
    final name = crate.name;
    final libTracks = tracks.map((t) => LibraryTrack(
      id: t.id, filePath: '', fileName: '${t.artist} - ${t.title}',
      title: t.title, artist: t.artist, album: '', genre: t.genre,
      bpm: t.bpm.toDouble(), key: t.keySignature, durationSeconds: 0,
      fileSizeBytes: 0, fileExtension: '.mp3', md5Hash: '', bitrate: 320, sampleRate: 44100,
    )).toList();
    final exportCrate = ExportCrate(name: name, tracks: libTracks);

    String path;
    switch (format) {
      case 'm3u':
        path = await svc.exportM3u(exportCrate);
      case 'csv':
        path = await svc.exportSeratoCsv(exportCrate);
      case 'rekordbox':
        path = await svc.exportRekordboxXml(exportCrate);
      case 'virtualdj':
        path = await svc.exportVirtualDjXml(exportCrate);
      case 'traktor':
        path = await svc.exportTraktorNml(exportCrate);
      case 'manifest':
        path = await svc.exportAiCrateManifest(name, tracks.map((t) {
          // Wrap as dynamic with required fields
          return _TrackExportProxy(t);
        }).toList());
      default:
        return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported to $path'),
          backgroundColor: AppTheme.lime,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Show in Finder',
            textColor: Colors.white,
            onPressed: () => ExportService.revealInFinder(path),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete "${crate.name}"?', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: Text('This will permanently remove this crate and its ${crate.trackIds.length} tracks.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(crateProvider.notifier).deleteCrate(crate.name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${crate.name}"'), backgroundColor: AppTheme.pink, duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = crate.trackIds
        .map((id) => allTracks.firstWhereOrNull((t) => t.id == id))
        .whereType<Track>()
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_fix_high_rounded, color: AppTheme.amber, size: 10),
                    SizedBox(width: 4),
                    Text('SET', style: TextStyle(color: AppTheme.amber, fontSize: 9, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(crate.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text('${tracks.length} tracks',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(width: 8),
              // ── Delete button ──
              Tooltip(
                message: 'Delete crate',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _confirmDelete(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded, color: Colors.red.withValues(alpha: 0.6), size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (crate.context.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(crate.context, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          // Export buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ExportBtn(label: 'M3U', icon: Icons.queue_music_rounded, onTap: () => _export(context, 'm3u', tracks)),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Serato', icon: Icons.table_chart_rounded, onTap: () => _export(context, 'csv', tracks)),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Rekordbox', icon: Icons.album_rounded, onTap: () => _export(context, 'rekordbox', tracks)),
                const SizedBox(width: 6),
                _ExportBtn(label: 'VirtualDJ', icon: Icons.surround_sound_rounded, onTap: () => _export(context, 'virtualdj', tracks)),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Traktor', icon: Icons.speaker_rounded, onTap: () => _export(context, 'traktor', tracks)),
                const SizedBox(width: 6),
                _ExportBtn(label: 'Manifest', icon: Icons.description_rounded, onTap: () => _export(context, 'manifest', tracks)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < tracks.length; i++) ...[
            _CrateTrackRow(track: tracks[i], index: i),
            if (i < tracks.length - 1) Divider(color: AppTheme.edge.withValues(alpha: 0.3), height: 1),
          ],
        ],
      ),
    );
  }
}

class _CrateTrackRow extends ConsumerWidget {
  const _CrateTrackRow({required this.track, required this.index});
  final Track track;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 24,
            child: Text('${index + 1}', textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          ),
          const SizedBox(width: 10),
          // Artwork
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: track.artworkUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: track.artworkUrl, width: 36, height: 36, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _trackArtPlaceholder())
                : _trackArtPlaceholder(),
          ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(track.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // BPM
          if (track.bpm > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text('${track.bpm}', style: const TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          // Key
          if (track.keySignature.isNotEmpty && track.keySignature != '--')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4)),
              child: Text(track.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          // Genre
          Text(track.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.6), fontSize: 10)),
          const SizedBox(width: 8),
          // Play button — routes through Apple Music
          if (track.platformLinks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _PlatformPlayBtn(
                icon: Icons.play_arrow_rounded,
                color: const Color(0xFFFC3C44),
                url: track.platformLinks.values.first,
                tooltip: 'Play',
                onTap: () => ref.read(appleMusicProvider.notifier).playByQuery(track.title, track.artist),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _trackArtPlaceholder() => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(6)),
    child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16),
  );

  static IconData _platformIcon(String p) => switch (p.toLowerCase()) {
    'spotify' => Icons.graphic_eq_rounded,
    'apple' => Icons.music_note_rounded,
    'youtube' => Icons.play_circle_fill_rounded,
    'deezer' => Icons.headphones_rounded,
    'soundcloud' => Icons.cloud_rounded,
    _ => Icons.open_in_new_rounded,
  };

  static Color _platformColor(String p) => switch (p.toLowerCase()) {
    'spotify' => const Color(0xFF1ED760),
    'apple' => const Color(0xFFFF7AB5),
    'youtube' => const Color(0xFFFF4B4B),
    'deezer' => const Color(0xFFA238FF),
    'soundcloud' => const Color(0xFFFFA237),
    _ => AppTheme.cyan,
  };
}

// ── Playlists View ────────────────────────────────────────────────────────────

class _PlaylistsView extends StatefulWidget {
  const _PlaylistsView();

  @override
  State<_PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<_PlaylistsView> {
  final _service = PlaylistAggregationService();
  String _genre = 'All';
  String _region = 'All';
  List<AggregatedPlaylist> _playlists = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await _service.fetchPlaylists(genre: _genre, region: _region, limit: 100);
      if (mounted) setState(() { _playlists = results; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genreOptions = ['All', 'Afrobeats', 'Amapiano', 'Hip-Hop', 'R&B', 'House', 'Dancehall', 'Pop', 'Latin', 'Drill'];
    final regionOptions = ['All', 'GH', 'NG', 'ZA', 'GB', 'US', 'DE'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              const Icon(Icons.playlist_play_rounded, color: AppTheme.cyan, size: 24),
              const SizedBox(width: 10),
              Text('Top Playlists', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
              const SizedBox(width: 12),
              Text('${_playlists.length} playlists from Apple Music, Spotify & YouTube',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const Spacer(),
              // Genre filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                ),
                child: DropdownButton<String>(
                  value: _genre, dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  underline: const SizedBox(), isDense: true,
                  items: genreOptions.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) { if (v != null) { setState(() => _genre = v); _load(); } },
                ),
              ),
              const SizedBox(width: 8),
              // Region filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                ),
                child: DropdownButton<String>(
                  value: _region, dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  underline: const SizedBox(), isDense: true,
                  items: regionOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) { if (v != null) { setState(() => _region = v); _load(); } },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2))
              : _playlists.isEmpty
                  ? const Center(child: Text('No playlists found. Try a different genre.', style: TextStyle(color: AppTheme.textTertiary)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                      itemCount: _playlists.length,
                      itemBuilder: (ctx, i) => _PlaylistCard(playlist: _playlists[i]),
                    ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});
  final AggregatedPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (playlist.artworkUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(imageUrl: playlist.artworkUrl!, width: 48, height: 48, fit: BoxFit.cover),
                  )
                else
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppTheme.panelRaised, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.playlist_play_rounded, color: AppTheme.cyan, size: 24),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(playlist.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${playlist.tracks.length} tracks from ${playlist.sourceLabel}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Track grid
          if (playlist.tracks.isNotEmpty)
            SizedBox(
              height: 200,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 150,
                ),
                itemCount: playlist.tracks.length,
                itemBuilder: (ctx, i) => _PlaylistTrackCard(track: playlist.tracks[i]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Platform result card (for set builder) ──────────────────────────────────

class _PlatformResultCard extends ConsumerStatefulWidget {
  const _PlatformResultCard({required this.track, required this.index});
  final AiCrateTrack track;
  final int index;

  @override
  ConsumerState<_PlatformResultCard> createState() => _PlatformResultCardState();
}

class _PlatformResultCardState extends ConsumerState<_PlatformResultCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist);
          if (!played && t.bestUrl.isNotEmpty) {
            final uri = Uri.tryParse(t.bestUrl);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl != null
                            ? CachedNetworkImage(imageUrl: t.artworkUrl!, fit: BoxFit.cover)
                            : Container(color: AppTheme.panelRaised,
                                child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32))),
                      ),
                    ),
                    Positioned(top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                        child: Text('#${widget.index + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
                      ),
                    ),
                    // Source badges
                    Positioned(top: 8, right: 8,
                      child: Row(
                        children: [
                          if (t.spotifyUrl != null) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF1ED760), shape: BoxShape.circle)),
                          if (t.spotifyUrl != null && t.appleUrl != null) const SizedBox(width: 3),
                          if (t.appleUrl != null) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFF7AB5), shape: BoxShape.circle)),
                        ],
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(color: AppTheme.cyan, shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)]),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (t.bpm > 0 || t.key.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (t.bpm > 0) Text('${t.bpm}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                          if (t.bpm > 0 && t.key.isNotEmpty) const SizedBox(width: 4),
                          if (t.key.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                              child: Text(t.key, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTrackCard extends ConsumerStatefulWidget {
  const _PlaylistTrackCard({required this.track});
  final PlatformTrackResult track;

  @override
  ConsumerState<_PlaylistTrackCard> createState() => _PlaylistTrackCardState();
}

class _PlaylistTrackCardState extends ConsumerState<_PlaylistTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist);
          if (!played && t.bestUrl.isNotEmpty) {
            final uri = Uri.tryParse(t.bestUrl);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      child: SizedBox.expand(
                        child: t.artworkUrl != null
                            ? CachedNetworkImage(imageUrl: t.artworkUrl!, fit: BoxFit.cover)
                            : Container(color: AppTheme.panelRaised, child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary)),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          ),
                          child: Center(
                            child: Container(
                              width: 36, height: 36,
                              decoration: const BoxDecoration(color: AppTheme.cyan, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ),
                    // Source badges
                    Positioned(
                      top: 6, left: 6,
                      child: Row(
                        children: [
                          if (t.spotifyUrl != null) _miniSourceBadge(const Color(0xFF1ED760)),
                          if (t.spotifyUrl != null && t.appleUrl != null) const SizedBox(width: 3),
                          if (t.appleUrl != null) _miniSourceBadge(const Color(0xFFFF7AB5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniSourceBadge(Color color) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _WatchlistView extends StatelessWidget {
  const _WatchlistView({required this.tracks, required this.onRemove});

  final List<Track> tracks;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Watchlist',
          subtitle:
              'Keep an eye on records with breakout potential and react before they peak in your market.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Text(
                    'No watched tracks yet. Hit Watch in the detail panel to track movement.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final delta =
                        ((track.trendHistory.last.score -
                                    track.trendHistory.first.score) *
                                100)
                            .round();
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppTheme.panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.edge),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${track.artist} · ${track.genre} · ${track.bpm} BPM',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            delta >= 0 ? '+$delta' : '$delta',
                            style: const TextStyle(
                              color: AppTheme.pink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: () => onRemove(track.id),
                            icon: const Icon(Icons.visibility_off_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SettingsView extends ConsumerStatefulWidget {
  const _SettingsView({
    required this.session,
    required this.userProfile,
    required this.regions,
  });

  final SessionState session;
  final UserProfile userProfile;
  final List<String> regions;

  @override
  ConsumerState<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<_SettingsView> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.session.email);
    _passwordController = TextEditingController();
    _displayNameController = TextEditingController(
      text: widget.session.displayName,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Settings & Auth',
          subtitle:
              'Configure your preferred market and switch between demo mode, email auth, or Google login once Firebase keys are wired in.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView(
            children: [
              _settingsCard(
                context,
                title: 'Account',
                child: Column(
                  children: [
                    TextField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => _runAuthAction(() async {
                            await ref
                                .read(sessionRepositoryProvider)
                                .signInWithEmail(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text,
                                );
                          }),
                          child: const Text('Sign in with Email'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _runAuthAction(() async {
                            await ref
                                .read(sessionRepositoryProvider)
                                .createAccount(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text,
                                  displayName: _displayNameController.text
                                      .trim(),
                                );
                          }),
                          child: const Text('Create Account'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _runAuthAction(
                            () => ref.read(sessionRepositoryProvider).signOut(),
                          ),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.session.isDemo
                          ? 'You are in demo mode right now. Email and Google actions will work once Firebase and platform keys are present.'
                          : 'Signed in as ${widget.session.displayName} via ${widget.session.providerLabel}.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _settingsCard(
                context,
                title: 'DJ defaults',
                child: DropdownButtonFormField<String>(
                  initialValue:
                      widget.regions.contains(
                        widget.userProfile.preferredRegion,
                      )
                      ? widget.userProfile.preferredRegion
                      : widget.regions.firstOrNull,
                  decoration: const InputDecoration(
                    labelText: 'Preferred region',
                  ),
                  items: widget.regions
                      .map(
                        (region) => DropdownMenuItem(
                          value: region,
                          child: Text(region),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    ref
                        .read(userRepositoryProvider)
                        .updatePreferredRegion(
                          userId: widget.session.userId,
                          fallbackName: widget.session.displayName,
                          region: value,
                        );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _settingsCard(
                context,
                title: 'Runtime config',
                child: Text(
                  'Use dart-defines for FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID, FIREBASE_PROJECT_ID, FIREBASE_STORAGE_BUCKET, GOOGLE_CLIENT_ID, and GOOGLE_SERVER_CLIENT_ID when running the macOS app.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication request completed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Auth request failed: $error')));
      }
    }
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

/// Shared artwork grid card used by _RegionsView, _GenresView, _SetBuilderView.
class _ShellTrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final int score;
  final VoidCallback? onTap;
  final WidgetRef? ref;
  const _ShellTrackCard({
    required this.track,
    required this.rank,
    required this.score,
    this.onTap,
    this.ref,
  });

  @override
  State<_ShellTrackCard> createState() => _ShellTrackCardState();
}

class _ShellTrackCardState extends State<_ShellTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final isTop3 = widget.rank <= 3;
    final rankColor = widget.rank == 1
        ? AppTheme.amber
        : widget.rank == 2
            ? const Color(0xFFC0C0C0)
            : widget.rank == 3
                ? const Color(0xFFCD7F32)
                : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            // Direct play via Apple Music, fall back to best platform URL
            if (widget.ref != null) {
              widget.ref!.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist).then((played) {
                if (!played) _openShellTrack(t);
              });
              widget.ref!.read(workspaceControllerProvider.notifier).activateTrack(t.id);
            } else {
              _openShellTrack(t);
            }
          }
        },
        onSecondaryTapDown: (details) {
          // Right-click shows the full action menu
          if (widget.ref != null) {
            showTrackActionMenu(context, widget.ref!, t, position: details.globalPosition);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isTop3
                  ? rankColor!.withValues(alpha: _hovered ? 0.5 : 0.3)
                  : AppTheme.edge
                      .withValues(alpha: _hovered ? 0.6 : 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _ShellArtPlaceholder(),
                              )
                            : _ShellArtPlaceholder(),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isTop3
                              ? rankColor!.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.rank}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight:
                                isTop3 ? FontWeight.w800 : FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Score badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${widget.score}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Play hover overlay
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.cyan
                                        .withValues(alpha: 0.5),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.artist,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${t.bpm}',
                          style: const TextStyle(
                              color: AppTheme.textTertiary, fontSize: 10),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.edge.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            t.keySignature,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        SourceBadges(sources: t.effectiveSources, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.edge, AppTheme.panelRaised],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note_rounded,
            color: AppTheme.textTertiary, size: 32),
      ),
    );
  }
}

Future<void> _openShellTrack(Track track) async {
  const priority = [
    'spotify',
    'apple',
    'youtube',
    'deezer',
    'soundcloud',
    'audius',
  ];
  String? url;
  for (final key in priority) {
    final u = track.platformLinks[key];
    if (u != null && u.isNotEmpty) {
      url = u;
      break;
    }
  }
  url ??= track.platformLinks.values.firstOrNull;
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Proxy to make Track fields accessible as dynamic properties for export manifest.
class _TrackExportProxy {
  final Track t;
  _TrackExportProxy(this.t);
  String get title => t.title;
  String get artist => t.artist;
  int get bpm => t.bpm;
  String get key => t.keySignature;
  String? get spotifyUrl => t.platformLinks['spotify'];
  String? get appleUrl => t.platformLinks['apple'];
  bool get resolved => t.platformLinks.isNotEmpty;
}

