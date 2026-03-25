import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  late final AnimationController _bgController;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.trending_up_rounded,
      gradient: [AppTheme.cyan, AppTheme.violet],
      title: 'Track Global Trends',
      body:
          'Monitor momentum across Spotify, YouTube, Apple Music, and more. See which tracks are breaking out before they peak.',
    ),
    _OnboardingPage(
      icon: Icons.equalizer_rounded,
      gradient: [AppTheme.violet, AppTheme.pink],
      title: 'Build Killer Sets',
      body:
          'Smart set builder with harmonic mixing, BPM progression, and energy shaping. Generate DJ-ready run orders in seconds.',
    ),
    _OnboardingPage(
      icon: Icons.public_rounded,
      gradient: [AppTheme.pink, AppTheme.cyan],
      title: 'Multi-Region Intelligence',
      body:
          'Track what\'s trending in the US, UK, Ghana, Nigeria, South Africa, and Germany. Stay ahead of every market.',
    ),
    _OnboardingPage(
      icon: Icons.play_circle_filled_rounded,
      gradient: [AppTheme.lime, AppTheme.cyan],
      title: 'Listen Instantly',
      body:
          'One tap to play any track on Spotify, Apple Music, or YouTube. Preview tracks without leaving your workflow.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _OrbsPainter(
                  progress: _bgController.value,
                  pageIndex: _currentPage,
                ),
              );
            },
          ),
          // Content
          SafeArea(
            child: Column(
              children: [
                // Skip button
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 20, 0),
                    child: TextButton(
                      onPressed: widget.onComplete,
                      child: Text(
                        'Skip',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
                // Pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _pages.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      return _PageContent(page: page);
                    },
                  ),
                ),
                // Credit
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Designed and Built by Angelo Nartey.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                // Indicators and button
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                  child: Row(
                    children: [
                      // Page indicators
                      Row(
                        children: List.generate(_pages.length, (index) {
                          final isActive = index == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 8),
                            width: isActive ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: isActive
                                  ? LinearGradient(
                                      colors: _pages[index].gradient,
                                    )
                                  : null,
                              color: isActive ? null : AppTheme.edge,
                            ),
                          );
                        }),
                      ),
                      const Spacer(),
                      // Next / Get Started button
                      _currentPage == _pages.length - 1
                          ? FilledButton.icon(
                              onPressed: widget.onComplete,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Get Started'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                backgroundColor: AppTheme.cyan,
                                foregroundColor: AppTheme.ink,
                              ),
                            )
                          : FilledButton.tonalIcon(
                              onPressed: () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              },
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Next'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String body;
}

class _PageContent extends StatefulWidget {
  const _PageContent({required this.page});

  final _OnboardingPage page;

  @override
  State<_PageContent> createState() => _PageContentState();
}

class _PageContentState extends State<_PageContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = widget.page;

    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, _) {
        final opacity = Curves.easeOut.transform(_entryController.value);
        final slideY = (1 - Curves.easeOut.transform(_entryController.value)) * 30;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, slideY),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon container with gradient glow
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          page.gradient[0].withValues(alpha: 0.2),
                          page.gradient[1].withValues(alpha: 0.2),
                        ],
                      ),
                      border: Border.all(
                        color: page.gradient[0].withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: page.gradient[0].withValues(alpha: 0.2),
                          blurRadius: 50,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: page.gradient[1].withValues(alpha: 0.1),
                          blurRadius: 80,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: page.gradient,
                      ).createShader(bounds),
                      child: Icon(
                        page.icon,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Title
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Colors.white, page.gradient[0]],
                    ).createShader(bounds),
                    child: Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Body
                  Text(
                    page.body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white60,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbsPainter extends CustomPainter {
  _OrbsPainter({required this.progress, required this.pageIndex});

  final double progress;
  final int pageIndex;

  static const _orbColors = [
    [AppTheme.cyan, AppTheme.violet],
    [AppTheme.violet, AppTheme.pink],
    [AppTheme.pink, AppTheme.cyan],
    [AppTheme.lime, AppTheme.cyan],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final colors = _orbColors[pageIndex % _orbColors.length];
    final angle = progress * 2 * math.pi;

    // Large slow-moving orb
    final orb1X = size.width * 0.3 + math.cos(angle) * size.width * 0.15;
    final orb1Y = size.height * 0.25 + math.sin(angle * 0.7) * size.height * 0.1;
    _drawOrb(canvas, Offset(orb1X, orb1Y), size.width * 0.35, colors[0], 0.08);

    // Smaller counter-rotating orb
    final orb2X =
        size.width * 0.7 + math.cos(-angle * 0.8) * size.width * 0.12;
    final orb2Y =
        size.height * 0.65 + math.sin(-angle * 0.6) * size.height * 0.08;
    _drawOrb(canvas, Offset(orb2X, orb2Y), size.width * 0.28, colors[1], 0.06);

    // Tiny accent orb
    final orb3X =
        size.width * 0.5 + math.cos(angle * 1.3) * size.width * 0.2;
    final orb3Y =
        size.height * 0.8 + math.sin(angle * 0.9) * size.height * 0.05;
    _drawOrb(canvas, Offset(orb3X, orb3Y), size.width * 0.18, colors[0], 0.04);
  }

  void _drawOrb(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: alpha * 0.3),
          Colors.transparent,
        ],
        stops: const [0, 0.5, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbsPainter old) =>
      old.progress != progress || old.pageIndex != pageIndex;
}
