import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/spotify_artist_service.dart';

typedef ArtistSearch = Future<List<SpotifyArtistResult>> Function(String query);
typedef ArtistImageLookup =
    Future<Map<String, String>> Function(List<String> names);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final void Function(List<String> artists) onComplete;

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
                      onPressed: () => widget.onComplete(const []),
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
                      // Next / sign-in button. Artist preferences are account
                      // data and are collected only after authentication.
                      _currentPage == _pages.length - 1
                          ? FilledButton.icon(
                              onPressed: () => widget.onComplete(const []),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Continue'),
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

// ── Onboarding artist picker ──────────────────────────────────────────────────

class OnboardingArtistPicker extends StatefulWidget {
  const OnboardingArtistPicker({
    super.key,
    required this.onComplete,
    required this.onSkip,
    this.artistSearch,
    this.artistImageLookup,
  });
  final void Function(List<String> artists) onComplete;
  final VoidCallback onSkip;
  final ArtistSearch? artistSearch;
  final ArtistImageLookup? artistImageLookup;

  @override
  State<OnboardingArtistPicker> createState() => _OnboardingArtistPickerState();
}

class _OnboardingArtistPickerState extends State<OnboardingArtistPicker> {
  final _searchCtrl = TextEditingController();
  final _spotify = SpotifyArtistService();
  late final ArtistSearch _artistSearch;
  late final ArtistImageLookup _artistImageLookup;
  final Set<String> _selected = {};
  final Map<String, String> _popularImages = {};
  List<SpotifyArtistResult> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;

  static const _popular = [
    'Drake',
    'Kendrick Lamar',
    'Bad Bunny',
    'The Weeknd',
    'Taylor Swift',
    'Asake',
    'Wizkid',
    'Burna Boy',
    'Davido',
    'Fireboy DML',
    'Rema',
    'Tems',
    'Ayra Starr',
    'Ckay',
    'Beyoncé',
    'SZA',
    'Doja Cat',
    'Cardi B',
    'Nicki Minaj',
    'Travis Scott',
    'Future',
    'Lil Baby',
    'Gunna',
    'J. Cole',
    'Nas',
    'Jay-Z',
    'Kanye West',
    'Tyler the Creator',
    'Frank Ocean',
    'Bryson Tiller',
    'H.E.R.',
    'Jhené Aiko',
    'Summer Walker',
    'Chris Brown',
    'Usher',
    'Brent Faiyaz',
    'PartyNextDoor',
    'Headie One',
    'Central Cee',
    'Dave',
    'Stormzy',
    'AJ Tracey',
    'Fivio Foreign',
    'Lil Durk',
    'Rod Wave',
    'Morgan Wallen',
    'Luke Combs',
    'Zach Bryan',
    'Peso Pluma',
    'Feid',
    'J Balvin',
    'Maluma',
    'Daddy Yankee',
    'Farruko',
    'Ozuna',
  ];

  @override
  void initState() {
    super.initState();
    _artistSearch = widget.artistSearch ?? _spotify.searchArtistsByName;
    _artistImageLookup =
        widget.artistImageLookup ?? _spotify.fetchOnboardingArtistImages;
    unawaited(_loadPopularImages());
  }

  Future<void> _loadPopularImages() async {
    for (var i = 0; i < _popular.length; i += 12) {
      final batch = _popular
          .skip(i)
          .take(12)
          .where((name) => !_popularImages.containsKey(name))
          .toList();
      if (batch.isEmpty) continue;

      Map<String, String> updates;
      try {
        updates = await _artistImageLookup(batch);
      } catch (e, st) {
        developer.log(
          'Failed to fetch onboarding Spotify artist image batch',
          name: 'Onboarding',
          error: e,
          stackTrace: st,
        );
        updates = const {};
      }
      if (!mounted) return;

      final validUpdates = <String, String>{};
      for (final entry in updates.entries) {
        final imageUrl = _validImageUrl(entry.value);
        if (imageUrl != null) validUpdates[entry.key] = imageUrl;
      }
      if (validUpdates.isNotEmpty) {
        setState(() => _popularImages.addAll(validUpdates));
      }
    }
  }

  String? _validImageUrl(String? imageUrl) {
    final trimmed = imageUrl?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Widget _buildFooter() {
    final selectedCount = Text(
      '${_selected.length} selected',
      style: const TextStyle(color: Colors.white54, fontSize: 12),
    );
    final skipButton = TextButton(
      onPressed: widget.onSkip,
      child: const Text('Skip', style: TextStyle(color: Colors.white38)),
    );
    final startButton = FilledButton(
      onPressed: () => widget.onComplete(_selected.toList()),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.cyan,
        foregroundColor: AppTheme.ink,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        'Get Started',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 400) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selectedCount,
                const SizedBox(height: 10),
                Row(
                  children: [
                    skipButton,
                    const SizedBox(width: 12),
                    Expanded(child: startButton),
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              selectedCount,
              const Spacer(),
              skipButton,
              const SizedBox(width: 12),
              startButton,
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await _artistSearch(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSearch = _searchCtrl.text.length >= 2;
    final displayItems = showSearch
        ? _searchResults.map((r) => r.name).toList()
        : _popular;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Your Artists',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Pick artists you love. We'll personalise your For You feed.",
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search any artist...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.violet,
                              ),
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.cyan,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Selected chips
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _selected
                    .take(8)
                    .map(
                      (name) => GestureDetector(
                        onTap: () => setState(() => _selected.remove(name)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.violet.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.violet.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                                size: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 12),
          // Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 140,
                childAspectRatio: 0.85,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: displayItems.length,
              itemBuilder: (context, i) {
                final name = displayItems[i];
                final imageUrl = showSearch
                    ? _validImageUrl(_searchResults[i].imageUrl)
                    : _popularImages[name];
                final isSelected = _selected.contains(name);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selected.remove(name);
                    } else {
                      _selected.add(name);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.violet.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.violet
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(30),
                              child: _ArtistImage(
                                name: name,
                                imageUrl: imageUrl,
                              ),
                            ),
                            if (isSelected)
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: AppTheme.violet,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Footer
          _buildFooter(),
        ],
      ),
    );
  }
}

class _ArtistImage extends StatelessWidget {
  const _ArtistImage({required this.name, required this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = _fallback();
    if (imageUrl == null) return fallback;

    return CachedNetworkImage(
      key: ValueKey('onboarding-artist-image-$name'),
      imageUrl: imageUrl!,
      width: 56,
      height: 56,
      fit: BoxFit.cover,
      memCacheWidth: 112,
      memCacheHeight: 112,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }

  Widget _fallback() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppTheme.violet.withValues(alpha: 0.4),
            AppTheme.cyan.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
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
        final slideY =
            (1 - Curves.easeOut.transform(_entryController.value)) * 30;

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
                      child: Icon(page.icon, size: 56, color: Colors.white),
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
                        letterSpacing: 0,
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
    final orb1Y =
        size.height * 0.25 + math.sin(angle * 0.7) * size.height * 0.1;
    _drawOrb(canvas, Offset(orb1X, orb1Y), size.width * 0.35, colors[0], 0.08);

    // Smaller counter-rotating orb
    final orb2X = size.width * 0.7 + math.cos(-angle * 0.8) * size.width * 0.12;
    final orb2Y =
        size.height * 0.65 + math.sin(-angle * 0.6) * size.height * 0.08;
    _drawOrb(canvas, Offset(orb2X, orb2Y), size.width * 0.28, colors[1], 0.06);

    // Tiny accent orb
    final orb3X = size.width * 0.5 + math.cos(angle * 1.3) * size.width * 0.2;
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
