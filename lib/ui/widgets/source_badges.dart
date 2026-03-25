import 'package:flutter/material.dart';

class SourceBadges extends StatelessWidget {
  const SourceBadges({super.key, required this.sources, this.compact = false});

  final Iterable<String> sources;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = sources.toSet().toList()..sort();

    return Wrap(
      spacing: compact ? 4 : 6,
      runSpacing: 6,
      children: ordered
          .map(
            (source) => Tooltip(
              message: _labelForSource(source),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 5 : 8,
                  vertical: compact ? 4 : 5,
                ),
                decoration: BoxDecoration(
                  color: _colorForSource(source).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _colorForSource(source).withValues(alpha: 0.32),
                  ),
                ),
                child: compact
                    ? Icon(
                        _iconForSource(source),
                        size: 12,
                        color: _colorForSource(source),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconForSource(source),
                            size: 14,
                            color: _colorForSource(source),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _labelForSource(source),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          )
          .toList(),
    );
  }

  static IconData _iconForSource(String source) {
    switch (source.toLowerCase()) {
      case 'spotify':
        return Icons.graphic_eq_rounded;
      case 'audius':
        return Icons.podcasts_rounded;
      case 'youtube':
        return Icons.play_circle_fill_rounded;
      case 'apple':
        return Icons.music_note_rounded;
      case 'musicbrainz':
        return Icons.album_outlined;
      case 'soundcloud':
        return Icons.cloud_rounded;
      case 'beatport':
        return Icons.equalizer_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  static Color _colorForSource(String source) {
    switch (source.toLowerCase()) {
      case 'spotify':
        return const Color(0xFF1ED760);
      case 'audius':
        return const Color(0xFF7C5CFF);
      case 'youtube':
        return const Color(0xFFFF4B4B);
      case 'apple':
        return const Color(0xFFFF7AB5);
      case 'musicbrainz':
        return const Color(0xFFF3C969);
      case 'soundcloud':
        return const Color(0xFFFFA237);
      case 'beatport':
        return const Color(0xFF32FF7E);
      default:
        return const Color(0xFF5FD7FF);
    }
  }

  static String _labelForSource(String source) {
    if (source.toLowerCase() == 'apple') {
      return 'Apple';
    }
    if (source.toLowerCase() == 'audius') {
      return 'Audius';
    }
    if (source.toLowerCase() == 'musicbrainz') {
      return 'MusicBrainz';
    }
    return '${source[0].toUpperCase()}${source.substring(1)}';
  }
}
