import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Launch splash: the animated VibeRadar mark — a Veo 3.1 generated equalizer
/// clip, exported as transparent PNG frames (alpha = luminance, so the black is
/// fully transparent). The bars float without an opaque or gradient backdrop.
///
/// PNG frames are used (rather than the source mp4 + a blend mode) because alpha
/// PNGs composite reliably on every platform, whereas blending over a video
/// texture does not. Degrades gracefully — launch is never blocked.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const int _frameCount = 48;
  static const Duration _frameDelay = Duration(milliseconds: 83); // ~12 fps

  int _frame = 0;
  Timer? _timer;
  bool _started = false;
  bool _done = false;

  String _framePath(int i) =>
      'assets/splash/frames/f${(i + 1).toString().padLeft(2, '0')}.png';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Pre-decode every frame so the loop is flicker-free.
    for (var i = 0; i < _frameCount; i++) {
      precacheImage(AssetImage(_framePath(i)), context);
    }
    _timer = Timer.periodic(_frameDelay, (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frameCount);
    });
    // Hold the splash for roughly one full loop, then reveal the app.
    Future.delayed(const Duration(milliseconds: 3600), _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated equalizer bars (transparent PNG frames).
          Center(
            child: Image.asset(
              _framePath(_frame),
              width: 220,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
          // Wordmark.
          Align(
            alignment: const Alignment(0, 0.82),
            child: ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.textPrimary, AppTheme.cyan, AppTheme.lime],
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
    );
  }
}
