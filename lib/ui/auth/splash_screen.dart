import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';

/// Launch splash: the animated VibeRadar mark — a Veo 3.1 generated equalizer
/// clip (pure white bars on pure black) screen-blended over the brand gradient,
/// so the black is fully transparent and only the bars float on the gradient.
///
/// Degrades gracefully: if the clip can't load, the gradient + wordmark still
/// show and launch is never blocked.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.asset('assets/splash/splash_motion.mp4');
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      c
        ..setVolume(0)
        ..play();
    }).catchError((_) {
      _finish(); // clip unavailable — don't block launch
    });
    c.addListener(_onTick);
    // Safety net: never hold the launch longer than the clip + a beat.
    Future.delayed(const Duration(milliseconds: 4400), _finish);
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.duration > Duration.zero &&
        c.value.position >= c.value.duration) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Brand gradient backdrop — matches the app icon.
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppTheme.brandGradient),
          ),
          // Animated bars: screen-blend renders the clip's pure black as
          // transparent, leaving the white bars floating on the gradient.
          if (ready)
            _BlendMask(
              blendMode: BlendMode.screen,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          // Wordmark.
          Align(
            alignment: const Alignment(0, 0.8),
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

/// Composites [child] onto the backdrop using [blendMode]. With
/// [BlendMode.screen], pure black in the child becomes transparent and pure
/// white stays white — perfect for keying a black-background clip.
class _BlendMask extends SingleChildRenderObjectWidget {
  const _BlendMask({required this.blendMode, required Widget super.child});

  final BlendMode blendMode;

  @override
  _RenderBlendMask createRenderObject(BuildContext context) =>
      _RenderBlendMask(blendMode);

  @override
  void updateRenderObject(BuildContext context, _RenderBlendMask renderObject) {
    renderObject.blendMode = blendMode;
  }
}

class _RenderBlendMask extends RenderProxyBox {
  _RenderBlendMask(this._blendMode);

  BlendMode _blendMode;
  set blendMode(BlendMode value) {
    if (value == _blendMode) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    context.canvas.saveLayer(offset & size, Paint()..blendMode = _blendMode);
    super.paint(context, offset);
    context.canvas.restore();
  }
}
