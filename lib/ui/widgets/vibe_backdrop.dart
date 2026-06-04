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
            Color(0xFF0B1016),
            Color(0xFF111622),
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
                    AppTheme.ink.withValues(alpha: 0.36),
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
    final gridPaint = Paint()
      ..color = AppTheme.edge.withValues(alpha: compact ? 0.12 : 0.16)
      ..strokeWidth = 1;
    final spacing = compact ? 44.0 : 58.0;

    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        gridPaint,
      );
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final horizonY = size.height * (compact ? 0.22 : 0.16);
    final horizonPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.cyan.withValues(alpha: 0),
          AppTheme.cyan.withValues(alpha: 0.28),
          AppTheme.pink.withValues(alpha: 0.16),
          AppTheme.amber.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, horizonY - 60, size.width, 120))
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      horizonPaint,
    );

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = compact ? 1.2 : 1.6
      ..shader = LinearGradient(
        colors: [
          AppTheme.lime.withValues(alpha: 0),
          AppTheme.lime.withValues(alpha: 0.28),
          AppTheme.cyan.withValues(alpha: 0.2),
          AppTheme.pink.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (var row = 0; row < (compact ? 2 : 3); row++) {
      final path = Path();
      final baseY = size.height * (0.5 + row * 0.13);
      for (var i = 0; i <= 72; i++) {
        final t = i / 72;
        final x = t * size.width;
        final y =
            baseY +
            math.sin((t * math.pi * 6) + row) * (compact ? 7 : 10) +
            math.sin((t * math.pi * 17) + row * 2) * (compact ? 2 : 4);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    }

    final radarPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.amber.withValues(alpha: compact ? 0.08 : 0.12);
    final radarCenter = Offset(size.width * 0.88, size.height * 0.08);
    for (
      var radius = spacing;
      radius < size.longestSide * 0.8;
      radius += spacing
    ) {
      canvas.drawCircle(radarCenter, radius, radarPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VibeBackdropPainter oldDelegate) {
    return oldDelegate.compact != compact;
  }
}
