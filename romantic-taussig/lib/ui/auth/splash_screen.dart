import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _sequenceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _barsOpacity;
  late final Animation<double> _glowRadius;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _sequenceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _logoScale = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.0, 0.35, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );
    _barsOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.15, 0.45, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.35, 0.55, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.5, 0.7, curve: Curves.easeOut),
      ),
    );
    _glowRadius = Tween(begin: 0.0, end: 180.0).animate(
      CurvedAnimation(
        parent: _sequenceController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _sequenceController.forward();

    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sequenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: AnimatedBuilder(
        animation: Listenable.merge([_sequenceController, _pulseController]),
        builder: (context, _) {
          return Stack(
            children: [
              // Animated background glow
              Center(
                child: Container(
                  width: _glowRadius.value * 2.5,
                  height: _glowRadius.value * 2.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.violet.withValues(
                          alpha: 0.15 + _pulseController.value * 0.08,
                        ),
                        AppTheme.cyan.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Secondary glow
              Center(
                child: Transform.translate(
                  offset: const Offset(60, -40),
                  child: Container(
                    width: _glowRadius.value * 1.8,
                    height: _glowRadius.value * 1.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.pink.withValues(
                            alpha: 0.1 + _pulseController.value * 0.06,
                          ),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Main content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo icon with EQ bars
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.violet,
                                AppTheme.pink,
                                AppTheme.cyan,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.violet.withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                              BoxShadow(
                                color: AppTheme.cyan.withValues(alpha: 0.2),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Opacity(
                            opacity: _barsOpacity.value,
                            child: CustomPaint(
                              painter: _EqBarsPainter(
                                progress: _pulseController.value,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Title
                    Opacity(
                      opacity: _titleOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - _titleOpacity.value) * 16),
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Colors.white, AppTheme.cyan],
                          ).createShader(bounds),
                          child: Text(
                            'VibeRadar',
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -2,
                                  fontSize: 48,
                                ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Subtitle
                    Opacity(
                      opacity: _subtitleOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - _subtitleOpacity.value) * 12),
                        child: Text(
                          'DJ Trend Intelligence',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Colors.white54,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EqBarsPainter extends CustomPainter {
  _EqBarsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;

    const barCount = 5;
    final barSpacing = size.width * 0.12;
    final totalWidth = barCount * paint.strokeWidth + (barCount - 1) * barSpacing;
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;
    final maxHeight = size.height * 0.32;

    for (var i = 0; i < barCount; i++) {
      final phase = (progress + i * 0.2) % 1.0;
      final height =
          maxHeight * (0.3 + 0.7 * math.sin(phase * math.pi));
      final x = startX + i * (paint.strokeWidth + barSpacing);
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqBarsPainter old) =>
      old.progress != progress;
}
