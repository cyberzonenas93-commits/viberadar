part of 'exports_screen.dart';

// ──────────────────────────────────────────────────────────────────────────────
// _MatchPanel — shows VibeRadar → local library match results
// ──────────────────────────────────────────────────────────────────────────────

class _MatchPanel extends StatelessWidget {
  final List<TrackMatch> results;
  final bool exportMatchedOnly;
  final String? expandedId;
  final ValueChanged<bool> onToggleExportFilter;
  final ValueChanged<String> onToggleExpand;
  final VoidCallback onClear;

  const _MatchPanel({
    required this.results,
    required this.exportMatchedOnly,
    required this.expandedId,
    required this.onToggleExportFilter,
    required this.onToggleExpand,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final found = results.where((r) => r.isFound).length;
    final fuzzy = results.where((r) => r.isFuzzy).length;
    final missing = results.where((r) => r.isMissing).length;

    final displayed = exportMatchedOnly
        ? results.where((r) => r.isFound || r.isFuzzy).toList()
        : results;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.edge)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Library Match',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary, size: 14),
                ),
              ]),
              const SizedBox(height: 8),
              // Summary pills
              Row(children: [
                _StatusPill(icon: Icons.check_circle_rounded,
                    color: AppTheme.lime, label: '$found found'),
                const SizedBox(width: 6),
                _StatusPill(icon: Icons.change_circle_rounded,
                    color: AppTheme.amber, label: '$fuzzy fuzzy'),
                const SizedBox(width: 6),
                _StatusPill(icon: Icons.cancel_rounded,
                    color: AppTheme.pink, label: '$missing missing'),
              ]),
              const SizedBox(height: 8),
              // Export matched only toggle
              GestureDetector(
                onTap: () => onToggleExportFilter(!exportMatchedOnly),
                child: Row(children: [
                  Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: exportMatchedOnly
                          ? AppTheme.violet
                          : AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: exportMatchedOnly
                              ? AppTheme.violet
                              : AppTheme.edge),
                    ),
                    child: exportMatchedOnly
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 11)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  const Text('Export matched only',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ]),
              ),
            ],
          ),
        ),
        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            itemCount: displayed.length,
            itemBuilder: (context, i) {
              final r = displayed[i];
              final isExpanded = expandedId == r.vibeTrack.id;
              return _MatchRow(
                result: r,
                isExpanded: isExpanded,
                onTap: () => onToggleExpand(r.vibeTrack.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  final TrackMatch result;
  final bool isExpanded;
  final VoidCallback onTap;

  const _MatchRow({
    required this.result,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final (icon, color) = switch (r.status) {
      MatchStatus.found => (Icons.check_circle_rounded, AppTheme.lime),
      MatchStatus.fuzzyMatch => (Icons.change_circle_rounded, AppTheme.amber),
      MatchStatus.duplicateVersions => (Icons.copy_rounded, AppTheme.cyan),
      MatchStatus.uncertain => (Icons.help_outline_rounded, AppTheme.orange),
      MatchStatus.missing => (Icons.cancel_rounded, AppTheme.pink),
    };

    return GestureDetector(
      onTap: r.candidates.isNotEmpty || r.localFilePath != null ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isExpanded
              ? AppTheme.panelRaised
              : AppTheme.panel.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: isExpanded
                  ? color.withValues(alpha: 0.3)
                  : AppTheme.edge.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.vibeTrack.title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        r.vibeTrack.artist,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (r.matchScore > 0)
                  Text(
                    '${(r.matchScore * 100).toInt()}%',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                if (r.candidates.isNotEmpty || r.localFilePath != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textTertiary,
                    size: 14,
                  ),
                ],
              ]),
            ),
            // Expanded: show file candidates
            if (isExpanded) ...[
              const Divider(color: AppTheme.edge, height: 1, indent: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final path in r.candidates.isNotEmpty
                        ? r.candidates
                        : [if (r.localFilePath != null) r.localFilePath!])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.insert_drive_file_rounded,
                              color: AppTheme.textTertiary, size: 11),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              path.split('/').last,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 9,
                                  fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusPill(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
