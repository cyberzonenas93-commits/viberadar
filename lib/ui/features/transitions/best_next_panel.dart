import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../models/transition_score.dart';
import '../../../providers/transition_provider.dart';
import 'transition_score_chip.dart';

/// Panel showing the best next track recommendations for a given track.
class BestNextPanel extends ConsumerStatefulWidget {
  const BestNextPanel({
    super.key,
    required this.track,
    required this.pool,
    this.mode = TransitionMode.smooth,
    this.onAddToSet,
    this.maxResults = 5,
  });

  final Track track;
  final List<Track> pool;
  final TransitionMode mode;
  final void Function(Track track)? onAddToSet;
  final int maxResults;

  @override
  ConsumerState<BestNextPanel> createState() => _BestNextPanelState();
}

class _BestNextPanelState extends ConsumerState<BestNextPanel> {
  List<TransitionScore>? _scores;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  @override
  void didUpdateWidget(BestNextPanel old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id || old.mode != widget.mode) {
      _loadRecommendations();
    }
  }

  Future<void> _loadRecommendations() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Ensure provider is using the correct mode
      final notifier = ref.read(transitionProvider.notifier);
      if (ref.read(transitionProvider).mode != widget.mode) {
        notifier.setMode(widget.mode);
      }

      final scores = await notifier.getNextTracks(
        widget.track,
        widget.pool,
        maxResults: widget.maxResults,
      );

      if (!mounted) return;
      setState(() {
        _scores = scores;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Track? _trackForScore(TransitionScore score) {
    try {
      return widget.pool.firstWhere((t) => t.id == score.toTrackId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(track: widget.track, mode: widget.mode),
          const Divider(height: 1, color: AppTheme.edge),
          if (_loading)
            const _LoadingIndicator()
          else if (_error != null)
            _ErrorView(error: _error!, onRetry: _loadRecommendations)
          else if (_scores == null || _scores!.isEmpty)
            const _EmptyView()
          else
            ..._scores!.map((score) {
              final track = _trackForScore(score);
              if (track == null) return const SizedBox.shrink();
              return _TrackRow(
                track: track,
                score: score,
                onAddToSet: widget.onAddToSet != null
                    ? () => widget.onAddToSet!(track)
                    : null,
              );
            }),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.track, required this.mode});

  final Track track;
  final TransitionMode mode;

  String get _modeLabel {
    switch (mode) {
      case TransitionMode.smooth:
        return 'Smooth';
      case TransitionMode.clubFlow:
        return 'Club Flow';
      case TransitionMode.peakTime:
        return 'Peak Time';
      case TransitionMode.openFormat:
        return 'Open Format';
      case TransitionMode.warmUp:
        return 'Warm-Up';
      case TransitionMode.closing:
        return 'Closing';
      case TransitionMode.singalong:
        return 'Singalong';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.queue_music_rounded, size: 16, color: AppTheme.violet),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Best Next',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'After: ${track.title}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.violet.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.violet.withValues(alpha: 0.4)),
            ),
            child: Text(
              _modeLabel,
              style: const TextStyle(
                color: AppTheme.violet,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    required this.track,
    required this.score,
    this.onAddToSet,
  });

  final Track track;
  final TransitionScore score;
  final VoidCallback? onAddToSet;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                // Artwork placeholder
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
                  ),
                  child: widget.track.artworkUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            widget.track.artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.music_note_rounded,
                                    size: 16, color: AppTheme.textTertiary),
                          ),
                        )
                      : const Icon(Icons.music_note_rounded,
                          size: 16, color: AppTheme.textTertiary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.track.artist} · ${widget.track.bpm} BPM · ${widget.track.keySignature}',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TransitionScoreChip(score: widget.score, compact: true),
                const SizedBox(width: 6),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          _ExpandedDetails(
            score: widget.score,
            onAddToSet: widget.onAddToSet,
          ),
        const Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: AppTheme.edge,
        ),
      ],
    );
  }
}

class _ExpandedDetails extends StatelessWidget {
  const _ExpandedDetails({required this.score, this.onAddToSet});

  final TransitionScore score;
  final VoidCallback? onAddToSet;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full score chip
          TransitionScoreChip(score: score),
          if (score.recommendedTechnique != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.tune_rounded, size: 12, color: AppTheme.cyan),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    score.recommendedTechnique!,
                    style: const TextStyle(
                      color: AppTheme.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (score.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...score.reasons.take(3).map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _Dot(color: AppTheme.lime),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (score.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...score.warnings.take(2).map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _Dot(color: AppTheme.amber),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        w,
                        style: const TextStyle(
                          color: AppTheme.amber,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (onAddToSet != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: onAddToSet,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
                  foregroundColor: AppTheme.violet,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: AppTheme.violet.withValues(alpha: 0.4),
                    ),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 6,
                  children: [
                    Icon(Icons.add_rounded, size: 14),
                    Text('Add to Set'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.violet,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.pink, size: 24),
          const SizedBox(height: 8),
          Text(
            'Failed to load recommendations',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Text(
          'No compatible tracks found in pool.',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        ),
      ),
    );
  }
}

// ── Bottom Sheet Helper ───────────────────────────────────────────────────────

/// Show a bottom sheet with Best Next recommendations.
void showBestNextSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
  List<Track> pool, {
  TransitionMode mode = TransitionMode.smooth,
  void Function(Track)? onAddToSet,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: BestNextPanel(
                    track: track,
                    pool: pool,
                    mode: mode,
                    onAddToSet: (t) {
                      onAddToSet?.call(t);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
