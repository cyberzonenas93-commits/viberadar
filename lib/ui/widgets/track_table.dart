import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import 'source_badges.dart';

class TrackTable extends StatefulWidget {
  const TrackTable({
    super.key,
    required this.tracks,
    required this.selectedTrackIds,
    required this.primaryTrackId,
    required this.activeRegion,
    required this.watchlist,
    required this.sortColumn,
    required this.sortAscending,
    required this.onToggleSelection,
    required this.onActivateTrack,
    required this.onSort,
  });

  final List<Track> tracks;
  final Set<String> selectedTrackIds;
  final String? primaryTrackId;
  final String activeRegion;
  final Set<String> watchlist;
  final TrackSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onActivateTrack;
  final void Function(TrackSortColumn column, bool ascending) onSort;

  @override
  State<TrackTable> createState() => _TrackTableState();
}

class _TrackTableState extends State<TrackTable> {
  int _rowsPerPage = 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _TrackDataSource(
      tracks: widget.tracks,
      selectedTrackIds: widget.selectedTrackIds,
      primaryTrackId: widget.primaryTrackId,
      activeRegion: widget.activeRegion,
      watchlist: widget.watchlist,
      onActivateTrack: widget.onActivateTrack,
      onToggleSelection: widget.onToggleSelection,
    );

    final availableRowsPerPage = {
      8,
      16,
      25,
      50,
      if (widget.tracks.isNotEmpty && widget.tracks.length < 8)
        widget.tracks.length,
    }.toList()..sort();
    final rowsPerPage = widget.tracks.isEmpty
        ? availableRowsPerPage.first
        : availableRowsPerPage.contains(_rowsPerPage)
        ? _rowsPerPage
        : availableRowsPerPage.firstWhere(
            (value) => value >= widget.tracks.length,
            orElse: () => availableRowsPerPage.last,
          );

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.edge),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Theme(
                data: theme.copyWith(
                  cardTheme: const CardThemeData(margin: EdgeInsets.zero),
                  dividerColor: AppTheme.edge,
                ),
                child: PaginatedDataTable(
                  header: Text(
                    'Track intelligence table',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  rowsPerPage: rowsPerPage,
                  availableRowsPerPage: availableRowsPerPage,
                  onRowsPerPageChanged: (value) {
                    if (value != null) {
                      setState(() => _rowsPerPage = value);
                    }
                  },
                  sortColumnIndex: _columnIndexFor(widget.sortColumn),
                  sortAscending: widget.sortAscending,
                  checkboxHorizontalMargin: 14,
                  columnSpacing: 16,
                  showCheckboxColumn: true,
                  columns: [
                    DataColumn(
                      label: const Text('Track Name'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.title, ascending),
                    ),
                    DataColumn(
                      label: const Text('Artist'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.artist, ascending),
                    ),
                    DataColumn(
                      numeric: true,
                      label: const Text('BPM'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.bpm, ascending),
                    ),
                    DataColumn(
                      label: const Text('Key'),
                      onSort: (_, ascending) => widget.onSort(
                        TrackSortColumn.keySignature,
                        ascending,
                      ),
                    ),
                    DataColumn(
                      label: const Text('Genre'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.genre, ascending),
                    ),
                    DataColumn(
                      label: const Text('Vibe'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.vibe, ascending),
                    ),
                    DataColumn(
                      numeric: true,
                      label: const Text('Trend Score'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.trendScore, ascending),
                    ),
                    DataColumn(
                      label: const Text('Region'),
                      onSort: (_, ascending) =>
                          widget.onSort(TrackSortColumn.region, ascending),
                    ),
                    const DataColumn(label: Text('Sources')),
                  ],
                  source: source,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  int _columnIndexFor(TrackSortColumn column) {
    switch (column) {
      case TrackSortColumn.title:
        return 0;
      case TrackSortColumn.artist:
        return 1;
      case TrackSortColumn.bpm:
        return 2;
      case TrackSortColumn.keySignature:
        return 3;
      case TrackSortColumn.genre:
        return 4;
      case TrackSortColumn.vibe:
        return 5;
      case TrackSortColumn.trendScore:
        return 6;
      case TrackSortColumn.region:
        return 7;
    }
  }
}

class _TrackDataSource extends DataTableSource {
  _TrackDataSource({
    required this.tracks,
    required this.selectedTrackIds,
    required this.primaryTrackId,
    required this.activeRegion,
    required this.watchlist,
    required this.onToggleSelection,
    required this.onActivateTrack,
  });

  final List<Track> tracks;
  final Set<String> selectedTrackIds;
  final String? primaryTrackId;
  final String activeRegion;
  final Set<String> watchlist;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onActivateTrack;

  @override
  DataRow? getRow(int index) {
    if (index >= tracks.length) {
      return null;
    }
    final track = tracks[index];
    final isSelected = selectedTrackIds.contains(track.id);
    final isPrimary = primaryTrackId == track.id;

    Widget titleCell() {
      return Row(
        children: [
          if (watchlist.contains(track.id))
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(
                Icons.visibility_rounded,
                color: AppTheme.pink,
                size: 16,
              ),
            ),
          Flexible(
            child: Text(
              track.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isPrimary ? FontWeight.w700 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }

    return DataRow.byIndex(
      index: index,
      selected: isSelected,
      color: WidgetStateProperty.resolveWith(
        (_) => isPrimary
            ? AppTheme.cyan.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      onSelectChanged: (_) => onToggleSelection(track.id),
      cells: [
        DataCell(titleCell(), onTap: () => onActivateTrack(track.id)),
        DataCell(Text(track.artist), onTap: () => onActivateTrack(track.id)),
        DataCell(
          Text(track.bpm == 0 ? '--' : track.bpm.toString()),
          onTap: () => onActivateTrack(track.id),
        ),
        DataCell(
          Text(track.keySignature),
          onTap: () => onActivateTrack(track.id),
        ),
        DataCell(Text(track.genre), onTap: () => onActivateTrack(track.id)),
        DataCell(
          Text(track.vibe, style: const TextStyle(color: AppTheme.cyan)),
          onTap: () => onActivateTrack(track.id),
        ),
        DataCell(
          Text(
            formatTrendScore(track.trendScore),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: () => onActivateTrack(track.id),
        ),
        DataCell(
          Text(track.leadRegion),
          onTap: () => onActivateTrack(track.id),
        ),
        DataCell(
          SourceBadges(sources: track.platformLinks.keys, compact: true),
          onTap: () => onActivateTrack(track.id),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => tracks.length;

  @override
  int get selectedRowCount => selectedTrackIds.length;
}
