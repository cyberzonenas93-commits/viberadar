import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../providers/library_provider.dart';

// Track-level action for a single track within a group.
enum _TrackAction { keep, discard, undecided }

class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  // Groups the user has dismissed (ignored).
  final Set<int> _dismissedGroupIndexes = {};

  // Groups in manual-selection mode. Maps groupIndex → trackId → action.
  final Map<int, Map<String, _TrackAction>> _manualSelections = {};

  // Groups currently being moved to review folder.
  final Set<int> _movingGroupIndexes = {};

  // ── batch actions ────────────────────────────────────────────────────────

  void _keepBestInAllGroups() {
    final lib = ref.read(libraryProvider);
    for (var i = 0; i < lib.duplicateGroups.length; i++) {
      if (_dismissedGroupIndexes.contains(i)) continue;
      final group = lib.duplicateGroups[i];
      final rec = group.recommended;
      if (rec != null) _keepTrack(group, rec.id);
    }
  }

  Future<void> _reviewAll() async {
    final lib = ref.read(libraryProvider);
    for (var i = 0; i < lib.duplicateGroups.length; i++) {
      if (_dismissedGroupIndexes.contains(i)) continue;
      await _moveGroupToReview(i, lib.duplicateGroups[i]);
    }
  }

  void _clearDismissed() {
    setState(() => _dismissedGroupIndexes.clear());
  }

  // ── per-group actions ────────────────────────────────────────────────────

  void _keepBestInGroup(int groupIndex, DuplicateGroup group) {
    final rec = group.recommended;
    if (rec != null) _keepTrack(group, rec.id);
    setState(() => _dismissedGroupIndexes.add(groupIndex));
  }

  Future<void> _moveGroupToReview(
      int groupIndex, DuplicateGroup group) async {
    setState(() => _movingGroupIndexes.add(groupIndex));

    try {
      final docs = await getApplicationDocumentsDirectory();
      final reviewDir = Directory(
          p.join(docs.path, 'VibeRadar', 'DupeReview'));
      await reviewDir.create(recursive: true);

      final rec = group.recommended;
      for (final t in group.tracks) {
        if (t.id == rec?.id) continue; // keep the recommended one
        final src = File(t.filePath);
        if (!src.existsSync()) continue;
        final dest = p.join(reviewDir.path, t.fileName);
        try {
          await src.copy(dest);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${group.tracks.length - 1} file(s) copied to DupeReview folder'),
          backgroundColor: AppTheme.cyan,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Move failed: $e'),
          backgroundColor: AppTheme.pink,
        ));
      }
    } finally {
      if (mounted) setState(() => _movingGroupIndexes.remove(groupIndex));
    }
  }

  void _ignoreGroup(int groupIndex) {
    setState(() => _dismissedGroupIndexes.add(groupIndex));
  }

  void _enterManualMode(int groupIndex, DuplicateGroup group) {
    setState(() {
      _manualSelections[groupIndex] = {
        for (final t in group.tracks) t.id: _TrackAction.undecided,
      };
    });
  }

  void _applyManualSelections(int groupIndex, DuplicateGroup group) {
    final selections = _manualSelections[groupIndex] ?? {};
    final keepIds = selections.entries
        .where((e) => e.value == _TrackAction.keep)
        .map((e) => e.key)
        .toSet();
    if (keepIds.isEmpty) return;

    for (final t in group.tracks) {
      if (!keepIds.contains(t.id)) {
        ref.read(libraryProvider.notifier).removeTrack(t.id);
      }
    }
    setState(() {
      _manualSelections.remove(groupIndex);
      _dismissedGroupIndexes.add(groupIndex);
    });
  }

  void _keepTrack(DuplicateGroup group, String keepId) {
    for (final t in group.tracks) {
      if (t.id != keepId) {
        ref.read(libraryProvider.notifier).removeTrack(t.id);
      }
    }
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    final allGroups = lib.duplicateGroups;
    final visibleGroups = [
      for (var i = 0; i < allGroups.length; i++)
        if (!_dismissedGroupIndexes.contains(i)) (i, allGroups[i]),
    ];

    final dismissedCount = _dismissedGroupIndexes
        .where((i) => i < allGroups.length)
        .length;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Duplicates',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    lib.hasLibrary
                        ? '${allGroups.length} duplicate groups  •  '
                            '${lib.duplicateCount} extra files'
                            '${dismissedCount > 0 ? "  •  $dismissedCount dismissed" : ""}'
                        : 'Scan your library in My Library first',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (allGroups.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.pink.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.pink, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${lib.duplicateCount} duplicates found',
                    style: const TextStyle(
                        color: AppTheme.pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
          ]),

          // Batch toolbar
          if (allGroups.isNotEmpty) ...[
            const SizedBox(height: 16),
            _BatchToolbar(
              onKeepBestAll: visibleGroups.isNotEmpty
                  ? _keepBestInAllGroups
                  : null,
              onReviewAll: visibleGroups.isNotEmpty ? _reviewAll : null,
              onClearDismissed:
                  dismissedCount > 0 ? _clearDismissed : null,
              dismissedCount: dismissedCount,
            ),
          ],

          const SizedBox(height: 16),

          if (!lib.hasLibrary)
            const Expanded(child: _NeedScanState())
          else if (visibleGroups.isEmpty && allGroups.isEmpty)
            const Expanded(child: _NoDuplicatesState())
          else if (visibleGroups.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.done_all_rounded,
                      color: AppTheme.lime, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'All ${allGroups.length} groups reviewed',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _clearDismissed,
                    child: const Text('Show dismissed groups',
                        style: TextStyle(color: AppTheme.cyan)),
                  ),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: visibleGroups.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (ctx, listIdx) {
                  final (groupIndex, group) = visibleGroups[listIdx];
                  final isManual =
                      _manualSelections.containsKey(groupIndex);
                  final isMoving =
                      _movingGroupIndexes.contains(groupIndex);

                  return _DuplicateGroupCard(
                    group: group,
                    groupIndex: groupIndex,
                    isManualMode: isManual,
                    isMoving: isMoving,
                    manualSelections: _manualSelections[groupIndex] ?? {},
                    onKeepBest: () =>
                        _keepBestInGroup(groupIndex, group),
                    onMoveToReview: () =>
                        _moveGroupToReview(groupIndex, group),
                    onIgnore: () => _ignoreGroup(groupIndex),
                    onEnterManual: () =>
                        _enterManualMode(groupIndex, group),
                    onApplyManual: () =>
                        _applyManualSelections(groupIndex, group),
                    onManualToggle: (trackId, action) {
                      setState(() {
                        _manualSelections[groupIndex]![trackId] = action;
                      });
                    },
                    onKeep: (id) => _keepTrack(group, id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Batch toolbar ─────────────────────────────────────────────────────────────

class _BatchToolbar extends StatelessWidget {
  final VoidCallback? onKeepBestAll;
  final VoidCallback? onReviewAll;
  final VoidCallback? onClearDismissed;
  final int dismissedCount;

  const _BatchToolbar({
    required this.onKeepBestAll,
    required this.onReviewAll,
    required this.onClearDismissed,
    required this.dismissedCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Row(children: [
        const Icon(Icons.checklist_rounded,
            color: AppTheme.textSecondary, size: 14),
        const SizedBox(width: 8),
        const Text('Batch:',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        _BatchBtn(
          label: 'Keep Best in All',
          color: AppTheme.lime,
          onTap: onKeepBestAll,
        ),
        const SizedBox(width: 8),
        _BatchBtn(
          label: 'Review All',
          color: AppTheme.cyan,
          onTap: onReviewAll,
        ),
        if (dismissedCount > 0) ...[
          const SizedBox(width: 8),
          _BatchBtn(
            label: 'Clear Dismissed ($dismissedCount)',
            color: AppTheme.textSecondary,
            onTap: onClearDismissed,
          ),
        ],
        const Spacer(),
        const Text(
          'Changes take effect immediately. NEVER auto-deletes files.',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontStyle: FontStyle.italic),
        ),
      ]),
    );
  }
}

class _BatchBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _BatchBtn(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withValues(alpha: 0.12)
              : AppTheme.edge.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: onTap != null
                  ? color.withValues(alpha: 0.35)
                  : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                color: onTap != null ? color : AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Duplicate group card ──────────────────────────────────────────────────────

class _DuplicateGroupCard extends StatelessWidget {
  final DuplicateGroup group;
  final int groupIndex;
  final bool isManualMode;
  final bool isMoving;
  final Map<String, _TrackAction> manualSelections;
  final VoidCallback onKeepBest;
  final VoidCallback onMoveToReview;
  final VoidCallback onIgnore;
  final VoidCallback onEnterManual;
  final VoidCallback onApplyManual;
  final void Function(String trackId, _TrackAction action) onManualToggle;
  final void Function(String keepId) onKeep;

  const _DuplicateGroupCard({
    required this.group,
    required this.groupIndex,
    required this.isManualMode,
    required this.isMoving,
    required this.manualSelections,
    required this.onKeepBest,
    required this.onMoveToReview,
    required this.onIgnore,
    required this.onEnterManual,
    required this.onApplyManual,
    required this.onManualToggle,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    final rec = group.recommended;
    final confidence = group.confidence;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              // Reason badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(group.reasonLabel,
                    style: const TextStyle(
                        color: AppTheme.pink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text('${group.tracks.length} copies',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(width: 8),
              // Confidence badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.violet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                    '${(confidence * 100).toInt()}% confidence',
                    style: const TextStyle(
                        color: AppTheme.violet,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ),
              const Spacer(),
              // Action buttons
              if (!isManualMode) ...[
                if (rec != null)
                  _GroupActionBtn(
                    label: 'Keep Best',
                    icon: Icons.star_rounded,
                    color: AppTheme.lime,
                    onTap: onKeepBest,
                  ),
                const SizedBox(width: 6),
                _GroupActionBtn(
                  label: isMoving ? 'Moving…' : 'Review Folder',
                  icon: Icons.drive_file_move_rounded,
                  color: AppTheme.cyan,
                  onTap: isMoving ? null : onMoveToReview,
                ),
                const SizedBox(width: 6),
                _GroupActionBtn(
                  label: 'Manual',
                  icon: Icons.tune_rounded,
                  color: AppTheme.amber,
                  onTap: onEnterManual,
                ),
                const SizedBox(width: 6),
                _GroupActionBtn(
                  label: 'Ignore',
                  icon: Icons.visibility_off_rounded,
                  color: AppTheme.textSecondary,
                  onTap: onIgnore,
                ),
              ] else ...[
                _GroupActionBtn(
                  label: 'Apply Selections',
                  icon: Icons.check_circle_rounded,
                  color: AppTheme.lime,
                  onTap: onApplyManual,
                ),
                const SizedBox(width: 6),
                _GroupActionBtn(
                  label: 'Cancel',
                  icon: Icons.cancel_rounded,
                  color: AppTheme.textSecondary,
                  onTap: onIgnore,
                ),
              ],
            ]),
          ),

          // Recommended hint
          if (rec != null && !isManualMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded,
                    color: AppTheme.amber, size: 11),
                const SizedBox(width: 4),
                Text(
                  'Recommended to keep: ${rec.title.isNotEmpty ? rec.title : rec.fileName}  '
                  '(${rec.bitrate} kbps  ·  ${rec.fileSizeFormatted})',
                  style: const TextStyle(
                      color: AppTheme.amber, fontSize: 10),
                ),
              ]),
            ),

          // Preview of what will happen
          if (isManualMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppTheme.cyan, size: 11),
                const SizedBox(width: 4),
                const Text(
                  'Mark each track as Keep or Discard, then tap Apply.',
                  style:
                      TextStyle(color: AppTheme.cyan, fontSize: 10),
                ),
              ]),
            ),

          const Divider(color: AppTheme.edge, height: 1),

          ...group.tracks.map((t) {
            final isRec = rec?.id == t.id;
            if (isManualMode) {
              final action = manualSelections[t.id] ?? _TrackAction.undecided;
              return _ManualTrackRow(
                track: t,
                isRecommended: isRec,
                action: action,
                onKeep: () => onManualToggle(t.id, _TrackAction.keep),
                onDiscard: () =>
                    onManualToggle(t.id, _TrackAction.discard),
              );
            }
            return _DupeTrackRow(
              track: t,
              isRecommended: isRec,
              onKeep: () => onKeep(t.id),
            );
          }),
        ],
      ),
    );
  }
}

class _GroupActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _GroupActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: onTap != null
              ? color.withValues(alpha: 0.1)
              : AppTheme.edge.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: onTap != null
                  ? color.withValues(alpha: 0.3)
                  : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: onTap != null ? color : AppTheme.textTertiary, size: 11),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: onTap != null ? color : AppTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ── Track rows ────────────────────────────────────────────────────────────────

class _DupeTrackRow extends StatelessWidget {
  final LibraryTrack track;
  final bool isRecommended;
  final VoidCallback onKeep;
  const _DupeTrackRow(
      {required this.track,
      required this.isRecommended,
      required this.onKeep});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isRecommended
          ? AppTheme.lime.withValues(alpha: 0.04)
          : Colors.transparent,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.violet.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            track.fileExtension.replaceFirst('.', '').toUpperCase(),
            style: const TextStyle(
                color: AppTheme.violet,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(track.title,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded,
                      color: AppTheme.lime, size: 12),
                ],
              ]),
              Text(track.filePath,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${track.bitrate} kbps',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10)),
          Text(track.fileSizeFormatted,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 10)),
        ]),
        const SizedBox(width: 12),
        TextButton(
          onPressed: onKeep,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.lime,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            side: const BorderSide(color: AppTheme.lime),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text('Keep This',
              style: TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }
}

class _ManualTrackRow extends StatelessWidget {
  final LibraryTrack track;
  final bool isRecommended;
  final _TrackAction action;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;

  const _ManualTrackRow({
    required this.track,
    required this.isRecommended,
    required this.action,
    required this.onKeep,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    Color rowTint;
    switch (action) {
      case _TrackAction.keep:
        rowTint = AppTheme.lime.withValues(alpha: 0.06);
      case _TrackAction.discard:
        rowTint = AppTheme.pink.withValues(alpha: 0.06);
      case _TrackAction.undecided:
        rowTint = Colors.transparent;
    }

    return Container(
      color: rowTint,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.violet.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            track.fileExtension.replaceFirst('.', '').toUpperCase(),
            style: const TextStyle(
                color: AppTheme.violet,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(track.title,
                      style: TextStyle(
                          color: action == _TrackAction.discard
                              ? AppTheme.textTertiary
                              : AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          decoration: action == _TrackAction.discard
                              ? TextDecoration.lineThrough
                              : null),
                      overflow: TextOverflow.ellipsis),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star_rounded,
                      color: AppTheme.amber, size: 12),
                ],
              ]),
              Text('${track.bitrate} kbps  ·  ${track.fileSizeFormatted}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Keep / Discard toggle buttons
        Row(children: [
          _ManualBtn(
            label: 'Keep',
            selected: action == _TrackAction.keep,
            color: AppTheme.lime,
            onTap: onKeep,
          ),
          const SizedBox(width: 6),
          _ManualBtn(
            label: 'Discard',
            selected: action == _TrackAction.discard,
            color: AppTheme.pink,
            onTap: onDiscard,
          ),
        ]),
      ]),
    );
  }
}

class _ManualBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _ManualBtn(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: selected ? color : AppTheme.edge),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? color : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.normal)),
      ),
    );
  }
}

// ── Empty / need-scan states ──────────────────────────────────────────────────

class _NeedScanState extends StatelessWidget {
  const _NeedScanState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.content_copy_rounded,
              size: 48, color: AppTheme.cyan),
        ),
        const SizedBox(height: 24),
        const Text('Scan library first',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Go to My Library and select a music folder.',
            style:
                TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ]),
    );
  }
}

class _NoDuplicatesState extends StatelessWidget {
  const _NoDuplicatesState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.lime.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.lime.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              size: 48, color: AppTheme.lime),
        ),
        const SizedBox(height: 24),
        const Text('No duplicates found',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Your library is clean.',
            style:
                TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      ]),
    );
  }
}
