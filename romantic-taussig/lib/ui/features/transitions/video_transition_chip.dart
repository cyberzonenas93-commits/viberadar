import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/video_playback_item.dart';
import '../../../models/video_transition_score.dart';

/// A compact chip showing a [VideoTransitionScore] with colour-coded badge,
/// source-type indicator, and optional compact mode for inline list use.
class VideoTransitionChip extends StatefulWidget {
  const VideoTransitionChip({
    super.key,
    required this.score,
    required this.fromItem,
    required this.toItem,
    this.compact = false,
  });

  final VideoTransitionScore score;
  final VideoPlaybackItem fromItem;
  final VideoPlaybackItem toItem;

  /// In compact mode only the numeric score is shown.
  final bool compact;

  @override
  State<VideoTransitionChip> createState() => _VideoTransitionChipState();
}

class _VideoTransitionChipState extends State<VideoTransitionChip> {
  bool _hovered = false;

  Color get _scoreColor {
    final s = widget.score.overallScore;
    if (s >= 0.75) return AppTheme.lime;
    if (s >= 0.55) return AppTheme.amber;
    return AppTheme.pink;
  }

  String get _scorePercent =>
      '${(widget.score.overallScore * 100).round()}%';

  IconData get _sourceIcon {
    // If both items have the same source, show that source's icon
    final from = widget.fromItem.sourceType;
    final to = widget.toItem.sourceType;
    if (from == to) {
      return from == VideoSourceType.youtube
          ? Icons.play_circle_outline_rounded
          : Icons.folder_open_rounded;
    }
    // Mixed sources
    return Icons.sync_alt_rounded;
  }

  Color get _sourceIconColor {
    final from = widget.fromItem.sourceType;
    final to = widget.toItem.sourceType;
    if (from != to) return AppTheme.amber;
    return from == VideoSourceType.youtube
        ? AppTheme.pink
        : AppTheme.cyan;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _CompactVideoBadge(
        scorePercent: _scorePercent,
        color: _scoreColor,
        sourceIcon: _sourceIcon,
        sourceIconColor: _sourceIconColor,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showDetailPopup(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? _scoreColor.withValues(alpha: 0.18)
                : _scoreColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _scoreColor.withValues(alpha: _hovered ? 0.7 : 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              _ScoreDot(color: _scoreColor, size: 8),
              // Source type icon
              Icon(_sourceIcon, size: 12, color: _sourceIconColor),
              Text(
                _scorePercent,
                style: TextStyle(
                  color: _scoreColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              if (_hovered) ...[
                Container(
                  width: 1,
                  height: 12,
                  color: _scoreColor.withValues(alpha: 0.4),
                ),
                Text(
                  widget.score.type.label,
                  style: TextStyle(
                    color: _scoreColor.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailPopup(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _VideoTransitionDetailDialog(
        score: widget.score,
        fromItem: widget.fromItem,
        toItem: widget.toItem,
      ),
    );
  }
}

// ── Compact Badge ─────────────────────────────────────────────────────────────

class _CompactVideoBadge extends StatelessWidget {
  const _CompactVideoBadge({
    required this.scorePercent,
    required this.color,
    required this.sourceIcon,
    required this.sourceIconColor,
  });

  final String scorePercent;
  final Color color;
  final IconData sourceIcon;
  final Color sourceIconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(sourceIcon, size: 10, color: sourceIconColor),
          Text(
            scorePercent,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Score Dot ─────────────────────────────────────────────────────────────────

class _ScoreDot extends StatelessWidget {
  const _ScoreDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ── Detail Dialog ─────────────────────────────────────────────────────────────

class _VideoTransitionDetailDialog extends StatelessWidget {
  const _VideoTransitionDetailDialog({
    required this.score,
    required this.fromItem,
    required this.toItem,
  });

  final VideoTransitionScore score;
  final VideoPlaybackItem fromItem;
  final VideoPlaybackItem toItem;

  Color get _scoreColor {
    final s = score.overallScore;
    if (s >= 0.75) return AppTheme.lime;
    if (s >= 0.55) return AppTheme.amber;
    return AppTheme.pink;
  }

  String _sourceLabel(VideoPlaybackItem item) {
    return item.sourceType == VideoSourceType.youtube ? 'YouTube' : 'Local';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  _ScoreDot(color: _scoreColor, size: 10),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      score.summary,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${(score.overallScore * 100).round()}%',
                    style: TextStyle(
                      color: _scoreColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Source type row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    const Icon(Icons.videocam_rounded,
                        size: 13, color: AppTheme.textSecondary),
                    Text(
                      '${_sourceLabel(fromItem)} → ${_sourceLabel(toItem)}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (score.sourceSwitchPenalty > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '-0.1 source switch',
                          style: TextStyle(
                            color: AppTheme.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Sub-scores
              const SizedBox(height: 10),
              Row(
                spacing: 8,
                children: [
                  _SubScoreBadge(
                    label: 'Audio',
                    score: score.audioScore,
                  ),
                  _SubScoreBadge(
                    label: 'Visual',
                    score: score.visualScore,
                  ),
                ],
              ),
              if (score.reasons.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Why this works',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                ...score.reasons.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppTheme.lime,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (score.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Watch out',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                ...score.warnings.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: AppTheme.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            w.label,
                            style: const TextStyle(
                              color: AppTheme.amber,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubScoreBadge extends StatelessWidget {
  const _SubScoreBadge({required this.label, required this.score});

  final String label;
  final double score;

  Color get _color {
    if (score >= 0.75) return AppTheme.lime;
    if (score >= 0.55) return AppTheme.amber;
    return AppTheme.pink;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          Text(
            '${(score * 100).round()}%',
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
