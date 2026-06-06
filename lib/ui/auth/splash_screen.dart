import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Launch splash: the VibeRadar radar-wave mark over a deep radial-dark
/// backdrop. The mark scales and fades in, then holds while concentric radar
/// "pings" sweep outward and a soft cyan/violet glow pulses — echoing the
/// logo's radar concept. Pure Flutter motion (no decoded frames), so it
/// composites crisply everywhere and launch is never blocked.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
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
    _scaleIn = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
    );
    _fadeIn = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _enter.forward();

    // Hold roughly one ping cycle, then reveal the app.
    Future.delayed(const Duration(milliseconds: 3400), _finish);
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
      backgroundColor: AppTheme.ink,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.18),
            radius: 1.15,
            colors: [Color(0xFF0E1626), AppTheme.ink],
          ),
        ),
        child: Center(
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
                      final pulse = 1.0 + 0.022 * math.sin(t * 2 * math.pi);
                      return SizedBox(
                        width: 300,
                        height: 300,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Expanding radar pings radiating from the mark.
                            CustomPaint(
                              size: const Size(300, 300),
                              painter: _RadarPingPainter(t),
                            ),
                            // Glow + the radar-wave mark.
                            Transform.scale(
                              scale: pulse,
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(38),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.cyan.withValues(alpha: 0.30),
                                      blurRadius: 48,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: AppTheme.violet.withValues(alpha: 0.24),
                                      blurRadius: 64,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(38),
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    width: 168,
                                    height: 168,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
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
                    colors: [AppTheme.textPrimary, AppTheme.cyan, AppTheme.violet],
                  ).createShader(bounds),
                  child: const Text(
                    'VibeRadar',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 34,
                      letterSpacing: 0.5,
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
}

/// Paints two staggered radar "ping" rings sweeping outward from the mark,
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
        ..color = Color.lerp(AppTheme.cyan, AppTheme.violet, p)!
            .withValues(alpha: 0.42 * fade);
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPingPainter old) => old.t != t;
}
