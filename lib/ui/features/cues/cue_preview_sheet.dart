import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/hot_cue.dart';
import '../../../models/library_track.dart';
import '../../../models/track.dart';
import '../../../providers/cue_provider.dart';
import '../../../services/dj_root_detection_service.dart';
import '../../../services/virtual_dj_cue_writer.dart';

// ── Entry points ───────────────────────────────────────────────────────────────

/// Show the cue preview sheet for a single track.
Future<void> showCuePreviewSheet({
  required BuildContext context,
  required WidgetRef ref,
  required LibraryTrack track,
  Track? cloudTrack,
  bool useAi = true,
}) async {
  // Reset previous results, then open sheet immediately so user sees progress.
  ref.read(cueProvider.notifier).reset();
  // Fire analysis in background — the sheet observes state via Riverpod.
  unawaited(
    ref
        .read(cueProvider.notifier)
        .generateForTrack(track, cloudTrack: cloudTrack, useAi: useAi),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CuePreviewSheet(singleTrack: track),
  );
}

/// Show the cue preview sheet for a crate (batch analysis).
Future<void> showCueCrateSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<LibraryTrack> tracks,
  List<Track> cloudTracks = const [],
  String? crateName,
  bool useAi = true,
}) async {
  ref.read(cueProvider.notifier).reset();
  unawaited(
    ref
        .read(cueProvider.notifier)
        .generateForCrate(tracks, cloudTracks: cloudTracks, useAi: useAi),
  );
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CuePreviewSheet(
      singleTrack: tracks.length == 1 ? tracks.first : null,
      crateName: crateName,
    ),
  );
}

// ── Sheet widget ───────────────────────────────────────────────────────────────

class _CuePreviewSheet extends ConsumerStatefulWidget {
  const _CuePreviewSheet({this.singleTrack, this.crateName});
  final LibraryTrack? singleTrack;
  final String? crateName;

  @override
  ConsumerState<_CuePreviewSheet> createState() => _CuePreviewSheetState();
}

class _CuePreviewSheetState extends ConsumerState<_CuePreviewSheet> {
  final DjRootDetectionService _detection = DjRootDetectionService();
  String? _vdjRoot;
  bool _vdjRootLoading = false;
  bool _showVdjConfirm = false;
  int? _expandedResultIdx;

  @override
  void initState() {
    super.initState();
    _detectVdjRoot();
  }

  Future<void> _detectVdjRoot() async {
    setState(() => _vdjRootLoading = true);
    final root = await _detection.resolveVirtualDjRoot();
    if (mounted) {
      setState(() {
        _vdjRoot = root;
        _vdjRootLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cue = ref.watch(cueProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.edge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Icon(
                    Icons.piano_rounded,
                    color: AppTheme.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _headerTitle(cue),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.edge, height: 18),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  // Progress / status
                  if (cue.isAnalyzing)
                    _AnalyzingBanner(done: cue.progress, total: cue.total),
                  if (cue.status == CueGenStatus.error)
                    _ErrorBanner(message: cue.errorMessage ?? 'Unknown error'),
                  // Results
                  if (cue.isDone) const _EstimateNote(),
                  if (cue.isDone) ...[
                    ...cue.results.asMap().entries.map(
                      (e) => _ResultCard(
                        result: e.value,
                        expanded: _expandedResultIdx == e.key,
                        onToggle: () => setState(
                          () => _expandedResultIdx = _expandedResultIdx == e.key
                              ? null
                              : e.key,
                        ),
                        onRemoveCue: (cueId) => ref
                            .read(cueProvider.notifier)
                            .removeCue(e.value.trackId, cueId),
                        onRenameLabel: (cueId, label) => ref
                            .read(cueProvider.notifier)
                            .updateCueLabel(e.value.trackId, cueId, label),
                        ref: ref,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Actions
                  if (cue.isDone)
                    _ActionsRow(
                      cue: cue,
                      vdjRoot: _vdjRoot,
                      vdjRootLoading: _vdjRootLoading,
                      showVdjConfirm: _showVdjConfirm,
                      onShowVdjConfirm: () =>
                          setState(() => _showVdjConfirm = true),
                      onCancelVdjConfirm: () =>
                          setState(() => _showVdjConfirm = false),
                      onWriteVdj: _writeToVdj,
                      ref: ref,
                    ),
                  // VDJ write status
                  if (cue.vdjWriteStatus == VdjWriteStatus.done)
                    _VdjSuccessBanner(results: cue.vdjWriteResults),
                  if (cue.vdjWriteStatus == VdjWriteStatus.error)
                    _ErrorBanner(
                      message: cue.vdjWriteError ?? 'VirtualDJ write failed',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _headerTitle(CueState cue) {
    if (widget.crateName != null) return 'Cues — ${widget.crateName}';
    if (widget.singleTrack != null) {
      return '${widget.singleTrack!.title} — ${widget.singleTrack!.artist}';
    }
    return 'Hot Cue Preview';
  }

  Future<void> _writeToVdj() async {
    setState(() => _showVdjConfirm = false);
    if (_vdjRoot == null) return;
    final cue = ref.read(cueProvider);
    if (cue.results.length == 1) {
      await ref
          .read(cueProvider.notifier)
          .writeResultToVirtualDj(cue.results.first, _vdjRoot!);
    } else {
      await ref.read(cueProvider.notifier).writeBatchToVirtualDj(_vdjRoot!);
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _AnalyzingBanner extends StatelessWidget {
  const _AnalyzingBanner({required this.done, required this.total});
  final int done, total;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.cyan,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                total > 1
                    ? 'Estimating cues for $done of $total tracks…'
                    : 'Estimating cues…',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (total > 1) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? done / total : null,
                backgroundColor: AppTheme.edge,
                color: AppTheme.cyan,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Result card ────────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.expanded,
    required this.onToggle,
    required this.onRemoveCue,
    required this.onRenameLabel,
    required this.ref,
  });
  final CueGenerationResult result;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(String cueId) onRemoveCue;
  final void Function(String cueId, String label) onRenameLabel;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        children: [
          // Track header
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.trackTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        result.trackArtist,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _CueCountBadge(count: result.cues.length),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (result.warning != null) _WarningBanner(message: result.warning!),
          if (expanded) ...[
            const Divider(color: AppTheme.edge, height: 1),
            ...result.cues.map(
              (c) => _CueRow(
                cue: c,
                onRemove: () => onRemoveCue(c.id),
                onRename: (label) => onRenameLabel(c.id, label),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ── Cue row ─────────────────────────────────────────────────────────────────────
class _CueRow extends StatefulWidget {
  const _CueRow({
    required this.cue,
    required this.onRemove,
    required this.onRename,
  });
  final HotCue cue;
  final VoidCallback onRemove;
  final void Function(String) onRename;

  @override
  State<_CueRow> createState() => _CueRowState();
}

class _CueRowState extends State<_CueRow> {
  bool _editing = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.cue.label);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cue;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Slot chip
          _SlotChip(index: c.cueIndex),
          const SizedBox(width: 10),
          // Emoji
          Text(c.cueType.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          // Label (editable)
          Expanded(
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    autofocus: true,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      border: UnderlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      widget.onRename(v.trim().isEmpty ? c.label : v.trim());
                      setState(() => _editing = false);
                    },
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editing = true),
                    child: Text(
                      c.label,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Timestamp
          Text(
            c.timestampFormatted,
            style: const TextStyle(
              color: AppTheme.cyan,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Confidence
          _ConfidenceChip(confidence: c.confidence),
          const SizedBox(width: 4),
          // Remove
          GestureDetector(
            onTap: widget.onRemove,
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actions row ────────────────────────────────────────────────────────────────
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.cue,
    required this.vdjRoot,
    required this.vdjRootLoading,
    required this.showVdjConfirm,
    required this.onShowVdjConfirm,
    required this.onCancelVdjConfirm,
    required this.onWriteVdj,
    required this.ref,
  });
  final CueState cue;
  final String? vdjRoot;
  final bool vdjRootLoading;
  final bool showVdjConfirm;
  final VoidCallback onShowVdjConfirm;
  final VoidCallback onCancelVdjConfirm;
  final VoidCallback onWriteVdj;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Save to VibeRadar (already done silently, just confirm)
        _ActionBtn(
          icon: Icons.bookmark_added_rounded,
          label: 'Saved to VibeRadar',
          color: AppTheme.cyan,
          onTap: null, // Already saved
          isComplete: true,
        ),
        const SizedBox(height: 8),
        // Write to VirtualDJ
        if (vdjRootLoading)
          const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.cyan,
              ),
            ),
          )
        else if (vdjRoot != null && !showVdjConfirm)
          _ActionBtn(
            icon: Icons.queue_music_rounded,
            label: 'Write to VirtualDJ',
            color: AppTheme.violet,
            onTap: onShowVdjConfirm,
            isComplete: cue.vdjWriteStatus == VdjWriteStatus.done,
            loading: cue.isWritingVdj,
          )
        else if (vdjRoot == null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VirtualDJ not detected. Cues are saved in VibeRadar.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        // VDJ confirmation
        if (showVdjConfirm && vdjRoot != null)
          _VdjConfirmCard(
            vdjRoot: vdjRoot!,
            trackCount: cue.results.length,
            cueCount: cue.results.fold(0, (s, r) => s + r.cues.length),
            loading: cue.isWritingVdj,
            onConfirm: onWriteVdj,
            onCancel: onCancelVdjConfirm,
          ),
        const SizedBox(height: 8),
        // Serato — intentionally blocked pending fixture validation
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.edge),
          ),
          child: Row(
            children: const [
              Icon(
                Icons.album_rounded,
                color: AppTheme.textSecondary,
                size: 16,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Serato cue writing — coming soon (fixture validation required).',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── VDJ confirm card ────────────────────────────────────────────────────────────
class _VdjConfirmCard extends StatelessWidget {
  const _VdjConfirmCard({
    required this.vdjRoot,
    required this.trackCount,
    required this.cueCount,
    required this.loading,
    required this.onConfirm,
    required this.onCancel,
  });
  final String vdjRoot;
  final int trackCount, cueCount;
  final bool loading;
  final VoidCallback onConfirm, onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.violet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Write cues to VirtualDJ?',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Will write $cueCount cue point${cueCount != 1 ? "s" : ""} for '
            '$trackCount track${trackCount != 1 ? "s" : ""} into database.xml.\n'
            'A backup will be created automatically.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Root: $vdjRoot',
            style: const TextStyle(
              color: AppTheme.cyan,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: loading ? null : onCancel,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: loading ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.violet,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirm Write'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small widgets ──────────────────────────────────────────────────────────────

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: AppTheme.cyan.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5)),
    ),
    alignment: Alignment.center,
    child: Text(
      '${index + 1}',
      style: const TextStyle(
        color: AppTheme.cyan,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final double confidence;
  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).round();
    final color = confidence >= 0.7
        ? Colors.greenAccent
        : confidence >= 0.5
        ? Colors.orange
        : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CueCountBadge extends StatelessWidget {
  const _CueCountBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.panelRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.edge),
    ),
    child: Text(
      '$count cue${count != 1 ? "s" : ""}',
      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isComplete = false,
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isComplete, loading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isComplete ? null : (loading ? null : onTap),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(isComplete ? Icons.check_circle_rounded : icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isComplete
            ? Colors.green.withValues(alpha: 0.2)
            : color,
        foregroundColor: isComplete ? Colors.greenAccent : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// Always-on honesty note: cues are derived from BPM + typical song structure,
/// not detected from the audio waveform. Keeps the feature from implying real
/// audio analysis.
class _EstimateNote extends StatelessWidget {
  const _EstimateNote();
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.cyan.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: const [
        Icon(Icons.info_outline_rounded, color: AppTheme.cyan, size: 16),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Estimated from BPM & typical track structure — not detected from the '
            'audio. Preview and adjust before writing to your DJ software.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.orange, fontSize: 11),
          ),
        ),
      ],
    ),
  );
}

class _VdjSuccessBanner extends StatelessWidget {
  const _VdjSuccessBanner({required this.results});
  final List<VdjCueWriteResult> results;
  @override
  Widget build(BuildContext context) {
    final ok = results.where((r) => r.success).length;
    final written = results.fold<int>(0, (s, r) => s + r.cuesWritten);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$written cue${written != 1 ? "s" : ""} written for $ok track${ok != 1 ? "s" : ""}. '
              'Restart VirtualDJ to see them.',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
