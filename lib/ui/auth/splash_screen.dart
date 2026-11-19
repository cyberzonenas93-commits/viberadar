import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Launch splash with a solid brand background and a procedural radar core.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const Color _splashBackground = Color(0xFF0C1015);

  late final AnimationController _enter;
  late final AnimationController _loop;
  late final Animation<double> _scaleIn;
  late final Animation<double> _fadeIn;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scaleIn = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));
    _fadeIn = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
    _enter.forward();

    // Hold the animated mark briefly, then reveal the app.
    Future.delayed(const Duration(milliseconds: 3600), _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _splashBackground,
      body: ColoredBox(
        color: _splashBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _fadeIn,
                    child: ScaleTransition(
                      scale: _scaleIn,
                      child: AnimatedBuilder(
                        animation: _loop,
                        builder: (context, _) {
                          final t = _loop.value;
                          final beat = 0.5 - 0.5 * math.cos(t * 4 * math.pi);
                          final pulse = 0.985 + 0.045 * beat;
                          return SizedBox(
                            width: 300,
                            height: 300,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CustomPaint(
                                  size: const Size(300, 300),
                                  painter: _RadarPingPainter(t),
                                ),
                                Transform.scale(
                                  scale: pulse,
                                  child: _AnimatedSplashCore(t: t, beat: beat),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  FadeTransition(
                    opacity: _fadeIn,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          AppTheme.textPrimary,
                          AppTheme.cyan,
                          AppTheme.violet,
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        'VibeRadar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedSplashCore extends StatelessWidget {
  const _AnimatedSplashCore({required this.t, required this.beat});

  final double t;
  final double beat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(38),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.cyan.withValues(alpha: 0.18 + 0.06 * beat),
            AppTheme.panel.withValues(alpha: 0.86),
            AppTheme.violet.withValues(alpha: 0.16 + 0.06 * beat),
          ],
        ),
        border: Border.all(
          color: AppTheme.cyan.withValues(alpha: 0.36 + 0.22 * beat),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.cyan.withValues(alpha: 0.20 + 0.16 * beat),
            blurRadius: 42 + 20 * beat,
            spreadRadius: 1 + 3 * beat,
          ),
          BoxShadow(
            color: AppTheme.violet.withValues(alpha: 0.16 + 0.12 * beat),
            blurRadius: 56 + 22 * beat,
            spreadRadius: 4 + 4 * beat,
          ),
        ],
      ),
      child: CustomPaint(painter: _SplashCorePainter(t, beat)),
    );
  }
}

class _SplashCorePainter extends CustomPainter {
  _SplashCorePainter(this.t, this.beat);

  final double t;
  final double beat;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(38),
    );
    canvas.clipRRect(clip);

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.045);
    for (var x = 24.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 24.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final radius in const [34.0, 54.0, 74.0]) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppTheme.cyan.withValues(alpha: 0.14),
      );
    }

    final sweepAngle = t * math.pi * 2;
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.lime.withValues(alpha: 0.72 + 0.18 * beat);
    canvas.drawLine(
      center,
      center + Offset(math.cos(sweepAngle), math.sin(sweepAngle)) * 68,
      sweepPaint,
    );

    final wedgePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          AppTheme.lime.withValues(alpha: 0.20 + 0.08 * beat),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 76));
    final wedgePath = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: 76),
        sweepAngle - 0.72,
        0.72,
        false,
      )
      ..close();
    canvas.drawPath(wedgePath, wedgePaint);

    for (var i = 0; i < 3; i += 1) {
      final p = (t + i / 3) % 1;
      final angle = p * math.pi * 2;
      final radius = 42.0 + 10.0 * math.sin(p * math.pi * 2);
      final dot = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        dot,
        3.2,
        Paint()
          ..color = Color.lerp(
            AppTheme.cyan,
            AppTheme.violet,
            p,
          )!.withValues(alpha: 0.78),
      );
    }

    canvas.drawCircle(
      center,
      8 + 2 * beat,
      Paint()..color = AppTheme.textPrimary.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      center,
      18 + 6 * beat,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = AppTheme.cyan.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashCorePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.beat != beat;
  }
}

/// Paints two staggered radar "ping" rings sweeping outward from the core,
/// shifting cyan→violet and fading as they expand.
class _RadarPingPainter extends CustomPainter {
  _RadarPingPainter(this.t);

  final double t; // 0..1 loop position

  static const double _minR = 90.0; // just outside the 168px mark
  static const double _maxR = 150.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (final phase in const [0.0, 0.5]) {
      final p = (t + phase) % 1.0;
      final r = _minR + (_maxR - _minR) * p;
      final fade = 1.0 - p;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Color.lerp(
          AppTheme.cyan,
          AppTheme.violet,
          p,
        )!.withValues(alpha: 0.42 * fade);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPingPainter old) => old.t != t;
}
