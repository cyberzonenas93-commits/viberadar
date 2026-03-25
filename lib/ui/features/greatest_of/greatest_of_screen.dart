import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/greatest_of_result.dart';
import '../../../providers/greatest_of_provider.dart';

// ---------------------------------------------------------------------------
// Artists & genres available for selection
// ---------------------------------------------------------------------------

const _kArtists = [
  'Burna Boy',
  'Wizkid',
  'Tems',
  'Rema',
  'Davido',
  'Kabza De Small',
  'DJ Maphorisa',
  'Drake',
  'SZA',
  'Travis Scott',
  'Fred Again',
  'Kendrick Lamar',
  'Black Coffee',
];

const _kGenres = [
  'Afrobeats',
  'Amapiano',
  'R&B',
  'Hip-Hop',
  'House',
  'Afro House',
];

// ---------------------------------------------------------------------------
// Component labels & weights
// ---------------------------------------------------------------------------

const _kComponents = [
  ('peakTrend', 'Peak Trend', 0.35),
  ('longevity', 'Longevity', 0.25),
  ('culturalImpact', 'Cultural Impact', 0.25),
  ('regionalDominance', 'Regional Dominance', 0.15),
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class GreatestOfScreen extends ConsumerStatefulWidget {
  const GreatestOfScreen({super.key});

  @override
  ConsumerState<GreatestOfScreen> createState() => _GreatestOfScreenState();
}

class _GreatestOfScreenState extends ConsumerState<GreatestOfScreen> {
  // Local pending selections — committed on "Compute"
  String _pendingArtist = 'Burna Boy';
  String? _pendingGenre;
  String _pendingMode = 'artist';

  GreatestOfResult? _selected;

  @override
  void initState() {
    super.initState();
    // Initialise local state from providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingMode = ref.read(greatestOfModeProvider);
      _pendingArtist = ref.read(greatestOfArtistFilterProvider);
      _pendingGenre = ref.read(greatestOfGenreFilterProvider);
    });
  }

  void _compute() {
    ref.read(greatestOfModeProvider.notifier).state = _pendingMode;
    ref.read(greatestOfArtistFilterProvider.notifier).state = _pendingArtist;
    ref.read(greatestOfGenreFilterProvider.notifier).state = _pendingGenre;
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(greatestOfResultsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Greatest Of',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'All-time greatest tracks by artist or genre',
                style: TextStyle(color: Color(0xFF9099B8), fontSize: 13),
              ),
              const SizedBox(height: 20),
              // ── Controls row ───────────────────────────────────────────────
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Mode toggle
                  _ModeToggle(
                    value: _pendingMode,
                    onChange: (v) => setState(() {
                      _pendingMode = v;
                      if (v == 'genre' && _pendingGenre == null) {
                        _pendingGenre = _kGenres.first;
                      }
                    }),
                  ),
                  // Artist / genre selector
                  if (_pendingMode == 'artist')
                    _StyledDropdown<String>(
                      value: _pendingArtist,
                      items: _kArtists,
                      label: (v) => v,
                      onChanged: (v) => setState(() => _pendingArtist = v),
                    )
                  else
                    _StyledDropdown<String>(
                      value: _pendingGenre ?? _kGenres.first,
                      items: _kGenres,
                      label: (v) => v,
                      onChanged: (v) =>
                          setState(() => _pendingGenre = v),
                    ),
                  // Compute button
                  ElevatedButton.icon(
                    onPressed: _compute,
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label: const Text('Compute'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.violet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ── Two-pane body ──────────────────────────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left pane — results list
              Expanded(
                child: results.isEmpty
                    ? _EmptyState(mode: _pendingMode)
                    : _ResultsList(
                        results: results,
                        selected: _selected,
                        onSelect: (r) =>
                            setState(() => _selected = r),
                      ),
              ),
              // Right pane — breakdown panel
              if (_selected != null) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 280,
                  child: _ScoreBreakdownPanel(
                    result: _selected!,
                    onClose: () => setState(() => _selected = null),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mode toggle
// ---------------------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.value, required this.onChange});

  final String value;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tab(label: 'By Artist', active: value == 'artist',
              onTap: () => onChange('artist')),
          _Tab(label: 'By Genre', active: value == 'genre',
              onTap: () => onChange('genre')),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.violet : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF9099B8),
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Styled dropdown
// ---------------------------------------------------------------------------

class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.edge),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: AppTheme.panel,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: items
              .map((o) => DropdownMenuItem<T>(
                    value: o,
                    child: Text(label(o)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results list
// ---------------------------------------------------------------------------

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.selected,
    required this.onSelect,
  });

  final List<GreatestOfResult> results;
  final GreatestOfResult? selected;
  final ValueChanged<GreatestOfResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 0, 12, 28),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final isSelected = selected?.trackId == r.trackId;
        return _ResultCard(
          result: r,
          isSelected: isSelected,
          onTap: () => onSelect(r),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.isSelected,
    required this.onTap,
  });

  final GreatestOfResult result;
  final bool isSelected;
  final VoidCallback onTap;

  Color get _rankColor {
    switch (result.rank) {
      case 1:
        return const Color(0xFFFFD700); // gold
      case 2:
        return const Color(0xFFC0C0C0); // silver
      case 3:
        return const Color(0xFFCD7F32); // bronze
      default:
        return const Color(0xFF6B7494);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.violet.withOpacity(0.12)
              : AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.violet : AppTheme.edge,
          ),
        ),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _rankColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#${result.rank}',
                  style: TextStyle(
                    color: _rankColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.artist,
                    style: const TextStyle(
                        color: Color(0xFF9099B8), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Mini component bars
            SizedBox(
              width: 60,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _kComponents
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _MiniBar(
                              value:
                                  result.components[c.$1] ?? 0.0),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(width: 12),
            // Year badge
            _Badge(
              label: '${result.releaseYear}',
              color: AppTheme.edge,
            ),
            const SizedBox(width: 6),
            // BPM badge
            _Badge(
              label: '${result.bpm}',
              color: AppTheme.edge,
            ),
            const SizedBox(width: 6),
            // Key badge
            _Badge(
              label: result.key,
              color: AppTheme.panelRaised,
              textColor: AppTheme.cyan,
            ),
            const SizedBox(width: 10),
            // Greatest score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  (result.greatestScore * 100).toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppTheme.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const Text(
                  'score',
                  style:
                      TextStyle(color: Color(0xFF6B7494), fontSize: 9),
                ),
              ],
            ),
            const SizedBox(width: 4),
            // Add to crate
            IconButton(
              icon: const Icon(Icons.add_circle_outline,
                  size: 18, color: AppTheme.violet),
              onPressed: () {},
              tooltip: 'Add to Crate',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBar extends StatelessWidget {
  const _MiniBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 3,
        backgroundColor: AppTheme.edge,
        valueColor:
            const AlwaysStoppedAnimation<Color>(AppTheme.violet),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.textColor = const Color(0xFF9099B8),
  });
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: textColor, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Score breakdown panel (right pane)
// ---------------------------------------------------------------------------

class _ScoreBreakdownPanel extends StatelessWidget {
  const _ScoreBreakdownPanel({
    required this.result,
    required this.onClose,
  });

  final GreatestOfResult result;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 28, right: 12),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.artist,
                        style: const TextStyle(
                            color: Color(0xFF9099B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close,
                      size: 18, color: Color(0xFF6B7494)),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Gauge
          Center(
            child: _ScoreGauge(score: result.greatestScore),
          ),
          const SizedBox(height: 20),
          // Component rows
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: _kComponents
                  .map((c) => _ComponentRow(
                        label: c.$2,
                        weight: c.$3,
                        value: result.components[c.$1] ?? 0.0,
                      ))
                  .toList(),
            ),
          ),
          const Spacer(),
          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.queue_music_rounded, size: 15),
                  label: const Text('Add to Set Builder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.violet,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.visibility_rounded, size: 15),
                  label: const Text('Save to Watchlist'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.cyan,
                    side: const BorderSide(color: AppTheme.cyan),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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

// ---------------------------------------------------------------------------
// Circular gauge (CustomPainter arc)
// ---------------------------------------------------------------------------

class _ScoreGauge extends StatelessWidget {
  const _ScoreGauge({required this.score});
  final double score;

  @override
  Widget build(BuildContext context) {
    final display = (score * 100).toStringAsFixed(1);
    return SizedBox(
      width: 120,
      height: 120,
      child: CustomPaint(
        painter: _GaugePainter(score: score),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                display,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'SCORE',
                style: TextStyle(
                  color: Color(0xFF6B7494),
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.score});
  final double score;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Track ring
    final trackPaint = Paint()
      ..color = AppTheme.edge
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Value arc — starts at top (−π/2), sweeps clockwise
    final valuePaint = Paint()
      ..shader = const SweepGradient(
        colors: [AppTheme.violet, AppTheme.cyan],
        startAngle: 0,
        endAngle: math.pi * 2,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * score.clamp(0.0, 1.0),
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.score != score;
}

// ---------------------------------------------------------------------------
// Component row with label, weight, bar, and score
// ---------------------------------------------------------------------------

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.label,
    required this.weight,
    required this.value,
  });

  final String label;
  final double weight;
  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (weight * 100).toStringAsFixed(0);
    final scoreStr = (value * 100).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                '$pct%',
                style: const TextStyle(
                    color: Color(0xFF6B7494), fontSize: 10),
              ),
              const SizedBox(width: 8),
              Text(
                scoreStr,
                style: const TextStyle(
                  color: AppTheme.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppTheme.edge,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.lerp(AppTheme.violet, AppTheme.cyan, value) ??
                    AppTheme.violet,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border_rounded,
              size: 56, color: AppTheme.edge),
          const SizedBox(height: 16),
          Text(
            mode == 'artist'
                ? 'No tracks found for this artist.'
                : 'No tracks found for this genre.',
            style: const TextStyle(color: Color(0xFF9099B8), fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different selection or press Compute.',
            style: TextStyle(color: Color(0xFF6B7494), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
