import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global multi-select state for tracks across all screens.
class TrackSelectionState {
  const TrackSelectionState({
    this.selectedIds = const {},
    this.isSelecting = false,
  });

  final Set<String> selectedIds;
  final bool isSelecting;

  int get count => selectedIds.length;
  bool isSelected(String id) => selectedIds.contains(id);

  TrackSelectionState copyWith({Set<String>? selectedIds, bool? isSelecting}) =>
      TrackSelectionState(
        selectedIds: selectedIds ?? this.selectedIds,
        isSelecting: isSelecting ?? this.isSelecting,
      );
}

class TrackSelectionNotifier extends Notifier<TrackSelectionState> {
  @override
  TrackSelectionState build() => const TrackSelectionState();

  /// Enter multi-select mode (optionally with a first track already selected).
  void startSelecting([String? firstId]) {
    final ids = <String>{};
    if (firstId != null) ids.add(firstId);
    state = TrackSelectionState(selectedIds: ids, isSelecting: true);
  }

  /// Toggle a track's selection. If not in select mode, enters it.
  void toggle(String id) {
    if (!state.isSelecting) {
      startSelecting(id);
      return;
    }
    final ids = Set<String>.from(state.selectedIds);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    // Auto-exit select mode if nothing is selected
    if (ids.isEmpty) {
      state = const TrackSelectionState();
    } else {
      state = state.copyWith(selectedIds: ids);
    }
  }

  /// Select all from a list of IDs.
  void selectAll(List<String> ids) {
    final merged = Set<String>.from(state.selectedIds)..addAll(ids);
    state = TrackSelectionState(selectedIds: merged, isSelecting: true);
  }

  /// Clear selection and exit multi-select mode.
  void clear() {
    state = const TrackSelectionState();
  }
}

final trackSelectionProvider =
    NotifierProvider<TrackSelectionNotifier, TrackSelectionState>(
        TrackSelectionNotifier.new);
