import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/transition_score.dart';

/// A compact chip showing a transition score with color-coded badge.
///
/// In [compact] mode only the numeric score is shown.
/// In full mode a tap/hover reveals the transition type label and reasons.
class TransitionScoreChip extends StatefulWidget {
  const TransitionScoreChip({
    super.key,
    required this.score,
    this.compact = false,
  });

  final TransitionScore score;

  /// If true, only shows the score percentage. No label or tooltip.
  final bool compact;

  @override
  State<TransitionScoreChip> createState() => _TransitionScoreChipState();
}

class _TransitionScoreChipState extends State<TransitionScoreChip> {
  bool _hovered = false;

  Color get _scoreColor {
    final s = widget.score.overallScore;
    if (s >= 0.75) return AppTheme.lime;
    if (s >= 0.55) return AppTheme.amber;
    return AppTheme.pink;
  }

  String get _scorePercent {
    return '${(widget.score.overallScore * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _CompactBadge(
        scorePercent: _scorePercent,
        color: _scoreColor,
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
      builder: (_) => _TransitionDetailDialog(score: widget.score),
    );
  }
}

class _CompactBadge extends StatelessWidget {
  const _CompactBadge({required this.scorePercent, required this.color});

  final String scorePercent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        scorePercent,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

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

class _TransitionDetailDialog extends StatelessWidget {
  const _TransitionDetailDialog({required this.score});

  final TransitionScore score;

  Color get _scoreColor {
    final s = score.overallScore;
    if (s >= 0.75) return AppTheme.lime;
    if (s >= 0.55) return AppTheme.amber;
    return AppTheme.pink;
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
        constraints: const BoxConstraints(maxWidth: 360),
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
                  Text(
                    score.summary,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
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
              if (score.recommendedTechnique != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: AppTheme.violet,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          score.recommendedTechnique!,
                          style: const TextStyle(
                            color: AppTheme.violet,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                            w,
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
