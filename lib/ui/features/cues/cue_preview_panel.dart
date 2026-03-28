// ── CuePreviewPanel ───────────────────────────────────────────────────────────
//
// Shows suggested hot cues for a single LibraryTrack.
//
// Usage:
//   CuePreviewPanel(track: myTrack)   — in a detail panel
//   showCuePreviewSheet(context, ref, track)  — as a bottom sheet

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/hot_cue.dart';
import '../../../models/library_track.dart';
import '../../../providers/cue_provider.dart';

// ── Inline embedded panel ─────────────────────────────────────────────────────

class CuePreviewPanel extends ConsumerStatefulWidget {
  const CuePreviewPanel({
    super.key,
    required this.track,
    this.showWriteToVdjButton = false,
  });

  final LibraryTrack track;

  /// Shows the "Write to VirtualDJ" button (Phase B).
  final bool showWriteToVdjButton;

  @override
  ConsumerState<CuePreviewPanel> createState() => _CuePreviewPanelState();
}

class _CuePreviewPanelState extends ConsumerState<CuePreviewPanel> {
  @override
  void initState() {
    super.initState();
    // Try to load pre-saved cues on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cueProvider.notifier).loadCuesForTrack(widget.track.id);
    });
  }

  Future<void> _generate() async {
    await ref.read(cueProvider.notifier).generateForTrack(widget.track);
  }

  Future<void> _acceptAll() async {
    await ref.read(cueProvider.notifier).acceptAllCues(widget.track.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All cues accepted'),
        backgroundColor: AppTheme.lime,
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _writeToVdj() async {
    final result = await ref
        .read(cueProvider.notifier)
        .writeToVirtualDj(widget.track);
    if (!mounted) return;
    final msg = result?.summary ?? 'Write failed';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          result?.isSuccess == true ? AppTheme.lime : AppTheme.pink,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cueProvider);
    final cues = state.cuesForTrack(widget.track.id);
    final isLoading = state.isGenerating &&
        state.generatingTrackId == widget.track.id;
    final error = state.error;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppTheme.violet, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Hot Cues',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (cues.isNotEmpty) ...[
                if (cues.any((c) => c.isSuggested))
                  _SmallChip(
                    label: 'Accept All',
                    color: AppTheme.lime,
                    onTap: isLoading ? null : _acceptAll,
                  ),
                const SizedBox(width: 6),
                if (widget.showWriteToVdjButton &&
                    cues.any((c) => !c.isSuggested && !c.isWritten))
                  _SmallChip(
                    label: '→ VirtualDJ',
                    color: AppTheme.cyan,
                    onTap: isLoading ? null : _writeToVdj,
                  ),
                const SizedBox(width: 6),
              ],
              _SmallChip(
                label: isLoading
                    ? 'Generating…'
                    : cues.isEmpty
                        ? 'Generate'
                        : 'Regenerate',
                color: AppTheme.violet,
                onTap: isLoading ? null : _generate,
              ),
            ],
          ),

          // ── Error banner ───────────────────────────────────────────────
          if (error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.pink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppTheme.pink.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.pink, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(error,
                        style: const TextStyle(
                            color: AppTheme.pink, fontSize: 11)),
                  ),
                  GestureDetector(
                    onTap: () =>
                        ref.read(cueProvider.notifier).clearError(),
                    child: const Icon(Icons.close_rounded,
                        color: AppTheme.textSecondary, size: 14),
                  ),
                ],
              ),
            ),
          ],

          // ── Loading indicator ──────────────────────────────────────────
          if (isLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              backgroundColor: AppTheme.edge,
              color: AppTheme.violet,
              minHeight: 2,
            ),
          ],

          // ── Cue list ───────────────────────────────────────────────────
          if (cues.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...cues.asMap().entries.map((entry) {
              final i = entry.key;
              final cue = entry.value;
              return _CueRow(
                cue: cue,
                showDivider: i < cues.length - 1,
                onAccept: cue.isSuggested
                    ? () => ref
                        .read(cueProvider.notifier)
                        .acceptCue(widget.track.id, cue)
                    : null,
              );
            }),
          ] else if (!isLoading) ...[
            const SizedBox(height: 12),
            const Text(
              'No cues yet. Tap Generate to analyse this track.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],

          // ── BPM / metadata info footer ─────────────────────────────────
          if (cues.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Based on ${widget.track.bpm.toStringAsFixed(1)} BPM'
              '${widget.track.genre.isNotEmpty ? ' · ${widget.track.genre}' : ''}',
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

// ── CueRow ────────────────────────────────────────────────────────────────────

class _CueRow extends StatelessWidget {
  const _CueRow({
    required this.cue,
    required this.showDivider,
    this.onAccept,
  });

  final HotCue cue;
  final bool showDivider;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final suggestedOpacity = cue.isSuggested ? 0.65 : 1.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              // Cue index badge
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _parseColor(cue.cueType.vdjColor)
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: _parseColor(cue.cueType.vdjColor)
                          .withValues(alpha: 0.7)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${cue.cueIndex + 1}',
                  style: TextStyle(
                      color: _parseColor(cue.cueType.vdjColor),
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // Emoji indicator
              Text(cue.cueType.emoji,
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              // Label + type
              Expanded(
                child: Opacity(
                  opacity: suggestedOpacity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cue.label,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      Text(
                        cue.cueType.label,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              // Timestamp
              Text(
                cue.formattedTime,
                style: const TextStyle(
                    color: AppTheme.cyan,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
              const SizedBox(width: 8),
              // Confidence badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _confidenceColor(cue.confidence)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cue.confidenceLabel,
                  style: TextStyle(
                      color: _confidenceColor(cue.confidence),
                      fontSize: 9,
                      fontWeight: FontWeight.w600),
                ),
              ),
              // Accept button (only for suggestions)
              if (onAccept != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onAccept,
                  child: const Icon(Icons.check_circle_outline_rounded,
                      color: AppTheme.lime, size: 16),
                ),
              ] else if (cue.isWritten) ...[
                const SizedBox(width: 6),
                const Icon(Icons.save_rounded,
                    color: AppTheme.textTertiary, size: 14),
              ],
            ],
          ),
        ),
        if (showDivider)
          const Divider(
              height: 1,
              thickness: 0.5,
              color: Color(0xFF2A2A3A)),
      ],
    );
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.75) return AppTheme.lime;
    if (confidence >= 0.5) return AppTheme.amber;
    return AppTheme.pink;
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppTheme.violet;
    }
  }
}

// ── SmallChip ─────────────────────────────────────────────────────────────────

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet helper ───────────────────────────────────────────────────────

/// Shows a [CuePreviewPanel] in a modal bottom sheet.
void showCuePreviewSheet(
  BuildContext context,
  WidgetRef ref,
  LibraryTrack track, {
  bool showWriteToVdjButton = false,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Track header
          Text(
            track.title,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          Text(
            track.artist,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          CuePreviewPanel(
            track: track,
            showWriteToVdjButton: showWriteToVdjButton,
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
