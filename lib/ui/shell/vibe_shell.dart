import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_section.dart';
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
    final trackRepository = ref.read(trackRepositoryProvider);

    switch (workspace.section) {
      case AppSection.home:
        return HomeScreen(
          allTracks: allTracks,
          userProfile: userProfile,
        );
      case AppSection.trending:
        return _WorkbenchView(
          key: ValueKey(workspace.section),
          title: 'Trending tracks',
          subtitle: 'Sort, multi-select, and filter the freshest records without leaving the table.',
          showDashboard: false,
          allTracks: allTracks,
          visibleTracks: visibleTracks,
          filters: workspace.filters,
          userProfile: userProfile,
          genres: genres,
          vibes: vibes,
          regions: regions,
          searchController: _searchController,
          searchFocusNode: _searchFocusNode,
          filterFocusNode: _filterFocusNode,
          selectedTrackIds: workspace.selectedTrackIds,
          primaryTrackId: workspace.primaryTrackId,
          activeSortColumn: workspace.sortColumn,
          sortAscending: workspace.sortAscending,
          isLoading: tracksAsync.isLoading,
          onSearchChanged: (value) => ref
              .read(workspaceControllerProvider.notifier)
              .setSearchQuery(value),
          onFiltersChanged: (filters) => ref
              .read(workspaceControllerProvider.notifier)
              .updateFilters(filters),
          onRefresh: trackRepository.refresh,
          onSort: (column, ascending) => ref
              .read(workspaceControllerProvider.notifier)
              .sortBy(column, ascending),
          onToggleSelection: (trackId) => ref
              .read(workspaceControllerProvider.notifier)
              .toggleSelection(trackId),
          onActivateTrack: (trackId) => ref
              .read(workspaceControllerProvider.notifier)
              .activateTrack(trackId),
        );
      case AppSection.regions:
        return _RegionsView(
          tracks: allTracks,
          activeRegion: workspace.filters.region,
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
    required this.onSelectRegion,
    required this.onOpenRegionWorkbench,
    required this.onActivateTrack,
  });

  final List<Track> tracks;
  final String activeRegion;
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
    final selectedRegion = activeRegion == 'Global'
        ? fallbackRegion
        : activeRegion;
    final focusedTracks = [...tracks]
      ..sort(
        (a, b) => regionScoreForTrack(
          b,
          selectedRegion,
        ).compareTo(regionScoreForTrack(a, selectedRegion)),
      );
    final regionalLeaders = focusedTracks
        .where((track) => regionScoreForTrack(track, selectedRegion) > 0)
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Regional pulse',
          subtitle:
              'Compare regional heat, then pivot the global table around any market where a record starts breaking.',
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: regions.take(8).map((entry) {
            final selected = entry.key == selectedRegion;
            return InkWell(
              onTap: () => onSelectRegion(entry.key),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 180,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.cyan.withValues(alpha: 0.14)
                      : AppTheme.panel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected
                        ? AppTheme.cyan.withValues(alpha: 0.45)
                        : AppTheme.edge,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${entry.value.toStringAsFixed(2)} aggregate heat',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${formatRegionLabel(selectedRegion)} breakout board',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  regionalLeaders.isEmpty
                                      ? 'No live tracks are mapped to this region yet.'
                                      : 'Top records currently heating up in this market.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                onOpenRegionWorkbench(selectedRegion),
                            icon: const Icon(Icons.table_rows_rounded),
                            label: const Text('Open in table'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _RegionStatChip(
                            label: 'Tracks mapped',
                            value: '${regionalLeaders.length}',
                          ),
                          _RegionStatChip(
                            label: 'Heat total',
                            value:
                                regionStats[selectedRegion]?.toStringAsFixed(
                                  2,
                                ) ??
                                '0.00',
                          ),
                          _RegionStatChip(
                            label: 'Lead record',
                            value: regionalLeaders.firstOrNull?.title ?? 'None',
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: regionalLeaders.isEmpty
                            ? Center(
                                child: Text(
                                  'Select a different region or ingest more data to populate this board.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(color: Colors.white54),
                                ),
                              )
                            : ListView.separated(
                                itemCount: regionalLeaders.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final track = regionalLeaders[index];
                                  final regionHeat = regionScoreForTrack(
                                    track,
                                    selectedRegion,
                                  );
                                  return InkWell(
                                    onTap: () => onActivateTrack(track.id),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppTheme.panelRaised,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppTheme.edge,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: AppTheme.cyan.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              '${index + 1}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: AppTheme.textPrimary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  track.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${track.artist} · ${track.genre}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: AppTheme.textSecondary,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '${(regionHeat * 100).round()}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      color: AppTheme.cyan,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                              Text(
                                                'heat',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium
                                                    ?.copyWith(
                                                      color: Colors.white54,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 3,
                child: Container(
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
                        'How to use this',
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Pick a market, review the breakout board, then open that region in the main table to crate, sort, and build a set.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 18),
                      ...[
                        'Tap a region card to focus the market.',
                        'Tap any track row to load it in the detail panel.',
                        'Use "Open in table" to jump back into the full workstation with that region filter applied.',
                      ].map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: AppTheme.pink,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RegionStatChip extends StatelessWidget {
  const _RegionStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenresView extends StatelessWidget {
  const _GenresView({required this.tracks, required this.onSelectGenre});

  final List<Track> tracks;
  final ValueChanged<String> onSelectGenre;

  @override
  Widget build(BuildContext context) {
    final genreStats = <String, List<Track>>{};
    for (final track in tracks) {
      genreStats.putIfAbsent(track.genre, () => []).add(track);
    }
    final entries = genreStats.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Genre landscape',
          subtitle:
              'See where momentum is clustering across your ingestion pipeline and jump straight into a focused crate strategy.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final averageTrend = entry.value
                  .map((track) => track.trendScore)
                  .average;
              return InkWell(
                onTap: () => onSelectGenre(entry.key),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.violet.withValues(alpha: 0.8),
                              AppTheme.cyan.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.library_music_rounded,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${entry.value.length} tracked records · avg trend ${(averageTrend * 100).round()}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
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
    // Auto-regenerate when more tracks load in
    if (widget.allTracks.length != _lastTrackCount && _generated.isEmpty) {
      _regenerate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitleBlock(
          title: 'Set Builder',
          subtitle:
              'Generate a mixing-friendly run order with gradual BPM progression, energy shaping, and fewer key clashes.',
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Container(
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
                          'Build parameters',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: widget.genres.contains(_genre)
                                    ? _genre
                                    : widget.genres.firstOrNull,
                                decoration: const InputDecoration(
                                  labelText: 'Genre',
                                ),
                                items: widget.genres
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _genre = value ?? 'All'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: widget.vibes.contains(_vibe)
                                    ? _vibe
                                    : widget.vibes.firstOrNull,
                                decoration: const InputDecoration(
                                  labelText: 'Vibe',
                                ),
                                items: widget.vibes
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item,
                                        child: Text(item),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) =>
                                    setState(() => _vibe = value ?? 'All'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Duration: $_duration mins'),
                        Slider(
                          min: 30,
                          max: 180,
                          divisions: 10,
                          value: _duration.toDouble(),
                          onChanged: (value) =>
                              setState(() => _duration = value.round()),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'BPM lane: ${_bpmRange.start.round()} - ${_bpmRange.end.round()}',
                        ),
                        RangeSlider(
                          min: 60,
                          max: 200,
                          divisions: 20,
                          values: _bpmRange,
                          onChanged: (value) =>
                              setState(() => _bpmRange = value),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: _regenerate,
                              icon: const Icon(Icons.auto_fix_high_rounded),
                              label: const Text('Generate Set'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed:
                                  _generated.isEmpty ? null : _saveCrate,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Save as Crate'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 4,
                child: Container(
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
                        'Generated run order',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _generated.isEmpty
                            ? Center(
                                child: Text(
                                  'No matching tracks yet. Adjust your lane and regenerate.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(color: Colors.white70),
                                ),
                              )
                            : ReorderableListView.builder(
                                itemCount: _generated.length,
                                onReorder: (oldIndex, newIndex) {
                                  setState(() {
                                    final adjusted = newIndex > oldIndex
                                        ? newIndex - 1
                                        : newIndex;
                                    final track =
                                        _generated.removeAt(oldIndex);
                                    _generated.insert(adjusted, track);
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final track = _generated[index];
                                  return Container(
                                    key: ValueKey(track.id),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppTheme.panelRaised,
                                      borderRadius: BorderRadius.circular(18),
                                      border:
                                          Border.all(color: AppTheme.edge),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          '${index + 1}'.padLeft(2, '0'),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                track.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${track.artist} · ${track.bpm} BPM · ${track.keySignature}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppTheme.textTertiary,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          formatTrendScore(track.trendScore),
                                          style: const TextStyle(
                                            color: AppTheme.cyan,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

