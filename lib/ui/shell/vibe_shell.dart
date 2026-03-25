import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_section.dart';
import '../widgets/track_action_menu.dart';
import '../../models/crate.dart';
import '../../models/session_state.dart';
import '../../models/track.dart';
import '../../models/track_filters.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state.dart';
import '../../providers/repositories.dart';
import '../../services/set_builder_service.dart';
import '../widgets/dashboard_cards.dart';
import '../widgets/filter_bar.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/track_detail_panel.dart';
import '../widgets/track_table.dart';
import '../features/artists/artists_screen.dart';
import '../features/greatest_of/greatest_of_screen.dart';
import '../features/ai_copilot/ai_copilot_screen.dart';
import '../features/library/library_screen.dart';
import '../features/duplicates/duplicates_screen.dart';
import '../features/exports/exports_screen.dart';
import '../features/home/home_screen.dart';
import '../features/trending/trending_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _filterFocusNode = FocusNode();
  }

  @override
  void dispose() {
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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
      case AppSection.home:
        return HomeScreen(
          allTracks: allTracks,
          userProfile: userProfile,
        );
      case AppSection.trending:
        return const TrendingScreen();
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
    return section == AppSection.trending ||
        section == AppSection.regions ||
        section == AppSection.setBuilder ||
        section == AppSection.savedCrates ||
        section == AppSection.watchlist;
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

class _RegionsView extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
        activeRegion == 'Global' ? fallbackRegion : activeRegion;
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
                    '${regionalLeaders.length} tracks in ${formatRegionLabel(selectedRegion)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: () => onOpenRegionWorkbench(selectedRegion),
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
                    onSelected: (_) => onSelectRegion(entry.key),
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
                      ref: ref,
                      onTap: () => onActivateTrack(track.id),
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
                      onTap: () => widget.onSelectGenre(track.genre),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

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
  final SetBuilderService _service = SetBuilderService();
  int _duration = 60;
  String _genre = 'All';
  String _vibe = 'All';
  RangeValues _bpmRange = const RangeValues(60, 200);
  List<Track> _generated = const [];
  int _lastTrackCount = 0;

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  @override
  void didUpdateWidget(covariant _SetBuilderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allTracks.length != _lastTrackCount && _generated.isEmpty) {
      _regenerate();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      const Icon(Icons.auto_fix_high_rounded,
                          color: AppTheme.amber, size: 24),
                      const SizedBox(width: 10),
                      Text('Set Builder',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_generated.length} tracks in generated set',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _regenerate,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Generate'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _generated.isEmpty ? null : _saveCrate,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save Crate'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Build parameter controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                // Genre dropdown
                _SetBuilderDropdown(
                  label: 'Genre',
                  value: _genre,
                  options: widget.genres,
                  onChanged: (v) => setState(() => _genre = v),
                ),
                const SizedBox(width: 12),
                // Vibe dropdown
                _SetBuilderDropdown(
                  label: 'Vibe',
                  value: _vibe,
                  options: widget.vibes,
                  onChanged: (v) => setState(() => _vibe = v),
                ),
                const SizedBox(width: 16),
                // Duration
                Text('${_duration}m',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 12)),
                SizedBox(
                  width: 100,
                  child: Slider(
                    min: 30,
                    max: 180,
                    divisions: 10,
                    value: _duration.toDouble(),
                    onChanged: (v) =>
                        setState(() => _duration = v.round()),
                  ),
                ),
                const SizedBox(width: 12),
                // BPM range
                Text(
                    '${_bpmRange.start.round()}-${_bpmRange.end.round()} BPM',
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 12)),
                SizedBox(
                  width: 120,
                  child: RangeSlider(
                    min: 60,
                    max: 200,
                    divisions: 20,
                    values: _bpmRange,
                    onChanged: (v) => setState(() => _bpmRange = v),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Artwork grid
        Expanded(
          child: _generated.isEmpty
              ? const Center(
                  child: Text(
                      'No matching tracks. Adjust parameters and regenerate.',
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
                  itemCount: _generated.length,
                  itemBuilder: (context, i) {
                    final track = _generated[i];
                    final score = (track.trendScore * 100).toInt();
                    return _ShellTrackCard(
                      track: track,
                      rank: i + 1,
                      score: score,
                      ref: ref,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _regenerate() {
    setState(() {
      _lastTrackCount = widget.allTracks.length;
      _generated = _service.buildSet(
        tracks: widget.allTracks,
        durationMinutes: _duration,
        genre: _genre,
        vibe: _vibe,
        minBpm: _bpmRange.start,
        maxBpm: _bpmRange.end,
      );
    });
  }

  Future<void> _saveCrate() async {
    final crate = Crate(
      id: 'crate-${DateTime.now().millisecondsSinceEpoch}',
      name: '$_genre / $_vibe / ${_duration}m',
      context: 'Generated set',
      trackIds: _generated.map((track) => track.id).toList(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref
        .read(userRepositoryProvider)
        .saveCrate(
          userId: widget.session.userId,
          fallbackName: widget.session.displayName,
          crate: crate,
        );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crate saved to your workspace.')),
      );
    }
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

class _SavedCratesView extends StatelessWidget {
  const _SavedCratesView({required this.allTracks, required this.crates});

  final List<Track> allTracks;
  final List<Crate> crates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Saved Crates',
          subtitle:
              'Organize winning records by event, mood, or genre and keep your prep flow one click away.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: crates.isEmpty
              ? Center(
                  child: Text(
                    'No crates yet. Save one from Set Builder to start organizing your prep.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                )
              : ListView.separated(
                  itemCount: crates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final crate = crates[index];
                    final tracks = crate.trackIds
                        .map(
                          (id) => allTracks.firstWhereOrNull(
                            (track) => track.id == id,
                          ),
                        )
                        .whereType<Track>()
                        .toList();

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
                          Text(
                            crate.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${crate.context} · ${tracks.length} tracks',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.white60),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tracks
                                .map(
                                  (track) => Chip(
                                    label: Text(
                                      '${track.title} · ${track.bpm}',
                                    ),
                                  ),
                                )
                                .toList(),
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
          } else if (widget.ref != null) {
            showTrackActionMenu(context, widget.ref!, t, position: details.globalPosition);
          } else {
            _openShellTrack(t);
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
                        Text(
                          t.genre,
                          style: TextStyle(
                            color: AppTheme.violet.withValues(alpha: 0.7),
                            fontSize: 9,
                          ),
                        ),
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

