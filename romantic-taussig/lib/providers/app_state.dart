import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/session_repository.dart';
import '../models/app_section.dart';
import '../models/session_state.dart';
import '../models/track.dart';
import '../models/track_filters.dart';
import '../models/user_profile.dart';
import 'repositories.dart';

enum TrackSortColumn {
  title,
  artist,
  bpm,
  keySignature,
  genre,
  vibe,
  trendScore,
  region,
}

class WorkspaceState {
  const WorkspaceState({
    this.section = AppSection.home,
    this.searchQuery = '',
    this.filters = const TrackFilters(),
    this.selectedTrackIds = const <String>{},
    this.primaryTrackId,
    this.sortColumn = TrackSortColumn.trendScore,
    this.sortAscending = false,
    this.detailExpanded = false,
  });

  final AppSection section;
  final String searchQuery;
  final TrackFilters filters;
  final Set<String> selectedTrackIds;
  final String? primaryTrackId;
  final TrackSortColumn sortColumn;
  final bool sortAscending;
  final bool detailExpanded;

  WorkspaceState copyWith({
    AppSection? section,
    String? searchQuery,
    TrackFilters? filters,
    Set<String>? selectedTrackIds,
    Object? primaryTrackId = _sentinel,
    TrackSortColumn? sortColumn,
    bool? sortAscending,
    bool? detailExpanded,
  }) {
    return WorkspaceState(
      section: section ?? this.section,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
      selectedTrackIds: selectedTrackIds ?? this.selectedTrackIds,
      primaryTrackId: identical(primaryTrackId, _sentinel)
          ? this.primaryTrackId
          : primaryTrackId as String?,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
      detailExpanded: detailExpanded ?? this.detailExpanded,
    );
  }
}

const _sentinel = Object();

class WorkspaceController extends Notifier<WorkspaceState> {
  @override
  WorkspaceState build() => const WorkspaceState();

  void setSection(AppSection section) {
    state = state.copyWith(section: section);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void updateFilters(TrackFilters filters) {
    state = state.copyWith(filters: filters);
  }

  void toggleSelection(String trackId) {
    final next = state.selectedTrackIds.toSet();
    if (!next.add(trackId)) {
      next.remove(trackId);
    }

    state = state.copyWith(
      selectedTrackIds: next,
      primaryTrackId: next.isEmpty ? null : trackId,
    );
  }

  void activateTrack(String trackId, {bool append = false}) {
    state = state.copyWith(
      selectedTrackIds: append
          ? {...state.selectedTrackIds, trackId}
          : {trackId},
      primaryTrackId: trackId,
    );
  }

  void sortBy(TrackSortColumn column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
  }

  void toggleDetailExpanded() {
    state = state.copyWith(detailExpanded: !state.detailExpanded);
  }

  void selectRelativeTrack(List<Track> tracks, int delta) {
    if (tracks.isEmpty) {
      return;
    }

    final currentIndex = tracks.indexWhere(
      (track) => track.id == state.primaryTrackId,
    );
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (safeIndex + delta).clamp(0, tracks.length - 1);
    activateTrack(tracks[nextIndex].id);
  }
}

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      WorkspaceController.new,
    );

final sessionProvider = StreamProvider<SessionState>((ref) {
  return ref.watch(sessionRepositoryProvider).sessionChanges();
});

final trackStreamProvider = StreamProvider<List<Track>>((ref) {
  return ref.watch(trackRepositoryProvider).watchTracks();
});

final userProfileProvider = StreamProvider<UserProfile>((ref) {
  final session = ref.watch(sessionProvider).value ?? const SessionState.demo();
  return ref
      .watch(userRepositoryProvider)
      .watchUser(userId: session.userId, fallbackName: session.displayName);
});

final visibleTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(trackStreamProvider).value ?? const <Track>[];
  final workspace = ref.watch(workspaceControllerProvider);
  final search = workspace.searchQuery.trim().toLowerCase();

  final filtered = tracks.where((track) {
    if (!workspace.filters.matches(track)) {
      return false;
    }

    if (search.isEmpty) {
      return true;
    }

    return track.title.toLowerCase().contains(search) ||
        track.artist.toLowerCase().contains(search) ||
        track.genre.toLowerCase().contains(search) ||
        track.vibe.toLowerCase().contains(search);
  }).toList();

  int compare(Track left, Track right) {
    switch (workspace.sortColumn) {
      case TrackSortColumn.title:
        return left.title.compareTo(right.title);
      case TrackSortColumn.artist:
        return left.artist.compareTo(right.artist);
      case TrackSortColumn.bpm:
        return left.bpm.compareTo(right.bpm);
      case TrackSortColumn.keySignature:
        return left.keySignature.compareTo(right.keySignature);
      case TrackSortColumn.genre:
        return left.genre.compareTo(right.genre);
      case TrackSortColumn.vibe:
        return left.vibe.compareTo(right.vibe);
      case TrackSortColumn.region:
        return left.leadRegion.compareTo(right.leadRegion);
      case TrackSortColumn.trendScore:
        return left.trendScore.compareTo(right.trendScore);
    }
  }

  filtered.sort(compare);
  if (!workspace.sortAscending) {
    return filtered.reversed.toList();
  }
  return filtered;
});

final selectedTrackProvider = Provider<Track?>((ref) {
  final tracks = ref.watch(visibleTracksProvider);
  final selectedId = ref.watch(workspaceControllerProvider).primaryTrackId;
  return tracks.firstWhereOrNull((track) => track.id == selectedId) ??
      tracks.firstOrNull;
});

final availableGenresProvider = Provider<List<String>>((ref) {
  final genres =
      ref.watch(trackStreamProvider).value?.map((track) => track.genre) ?? [];
  return ['All', ...genres.toSet().toList()..sort()];
});

final availableVibesProvider = Provider<List<String>>((ref) {
  final vibes =
      ref.watch(trackStreamProvider).value?.map((track) => track.vibe) ?? [];
  return ['All', ...vibes.toSet().toList()..sort()];
});

final availableRegionsProvider = Provider<List<String>>((ref) {
  final regionSet = <String>{'Global'};
  for (final track in ref.watch(trackStreamProvider).value ?? const <Track>[]) {
    regionSet.addAll(track.regionScores.keys);
  }
  final regions = regionSet.toList()..sort();
  regions.remove('Global');
  return ['Global', ...regions];
});

final sessionRepositoryActionsProvider = Provider<SessionRepository>(
  (ref) => ref.watch(sessionRepositoryProvider),
);
