part of 'greatest_of_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 12),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  final double size;
  final bool rounded;
  const _ArtPlaceholder({this.size = 44, this.rounded = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.edge,
            AppTheme.panelRaised,
          ],
        ),
        borderRadius: rounded ? BorderRadius.circular(size * 0.16) : null,
      ),
      child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: size * 0.35),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score bar — inline horizontal bar with label
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ScoreBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        SizedBox(
          width: 48,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(children: [
              Container(color: color.withValues(alpha: 0.15)),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 4),
        Text('${(value * 100).toInt()}',
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9)),
      ],
    );
  }
}

/// Compact badge version for artwork overlay
class _ScoreBadge extends StatelessWidget {
  final double value;
  final Color color;
  final String prefix;
  const _ScoreBadge({required this.value, required this.color, required this.prefix});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '$prefix${(value * 100).toInt()}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle chip
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.violet.withValues(alpha: 0.2) : AppTheme.panelRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppTheme.violet.withValues(alpha: 0.6) : AppTheme.edge.withValues(alpha: 0.5),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.timeline_rounded,
              size: 13, color: active ? AppTheme.violet : AppTheme.textSecondary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                color: active ? AppTheme.violet : AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isDense: true,
              dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}

// ignore: unused_element
Future<void> _openTrack(Track track) async {
  final url = _bestUrl(track);
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
