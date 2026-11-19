import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class VibeBackdrop extends StatelessWidget {
  const VibeBackdrop({super.key, required this.child, this.compact = false});

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.ink,
            Color(0xFF0C1115),
            Color(0xFF101820),
            AppTheme.ink,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _VibeBackdropPainter(compact)),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.04),
                    Colors.transparent,
                    AppTheme.ink.withValues(alpha: compact ? 0.42 : 0.34),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _VibeBackdropPainter extends CustomPainter {
  const _VibeBackdropPainter(this.compact);

  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final longSide = size.longestSide;
    final gridPaint = Paint()
      ..color = AppTheme.edge.withValues(alpha: compact ? 0.07 : 0.10)
      ..strokeWidth = 1;
    final spacing = compact ? 56.0 : 72.0;

    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final beamTop = size.height * (compact ? 0.08 : 0.06);
    final beamPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.cyan.withValues(alpha: 0),
          AppTheme.cyan.withValues(alpha: compact ? 0.20 : 0.26),
          AppTheme.lime.withValues(alpha: compact ? 0.12 : 0.18),
          AppTheme.cyan.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, beamTop - 44, size.width, 88))
      ..strokeWidth = compact ? 1.0 : 1.2;
    canvas.drawLine(Offset(0, beamTop), Offset(size.width, beamTop), beamPaint);

    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = compact ? 1.0 : 1.25
      ..shader = LinearGradient(
        colors: [
          AppTheme.cyan.withValues(alpha: 0),
          AppTheme.lime.withValues(alpha: compact ? 0.18 : 0.24),
          AppTheme.amber.withValues(alpha: compact ? 0.10 : 0.14),
          AppTheme.cyan.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final center = Offset(size.width * 0.82, size.height * 0.16);
    for (var i = 0; i < (compact ? 3 : 4); i++) {
      final radius = (longSide * 0.22) + i * spacing * 0.9;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, math.pi * 0.72, math.pi * 0.58, false, sweepPaint);
    }

    final bottomLinePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.amber.withValues(alpha: 0),
          AppTheme.amber.withValues(alpha: compact ? 0.06 : 0.10),
          AppTheme.lime.withValues(alpha: compact ? 0.08 : 0.12),
          AppTheme.amber.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, size.height * 0.68, size.width, 180))
      ..strokeWidth = 1;

    final path = Path()
      ..moveTo(0, size.height * 0.74)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.68,
        size.width * 0.72,
        size.height * 0.76,
      )
      ..quadraticBezierTo(
        size.width * 0.90,
        size.height * 0.80,
        size.width,
        size.height * 0.74,
      );
    canvas.drawPath(path, bottomLinePaint);

    final vignettePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.45, -0.35),
        radius: compact ? 0.92 : 0.78,
        colors: [
          Colors.transparent,
          AppTheme.ink.withValues(alpha: compact ? 0.08 : 0.12),
          AppTheme.ink.withValues(alpha: compact ? 0.34 : 0.28),
        ],
        stops: const [0, 0.62, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      vignettePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _VibeBackdropPainter oldDelegate) {
    return oldDelegate.compact != compact;
  }
}
