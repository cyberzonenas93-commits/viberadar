import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

enum PlatformPlayLabelStyle { iconOnly, platform, playOnPlatform }

class PlatformPlayActions extends StatelessWidget {
  const PlatformPlayActions({
    super.key,
    required this.links,
    this.labelStyle = PlatformPlayLabelStyle.iconOnly,
    this.compact = false,
    this.maxLinks,
    this.alignment = WrapAlignment.start,
    this.runAlignment = WrapAlignment.start,
  });

  factory PlatformPlayActions.fromUrls({
    Key? key,
    String? spotifyUrl,
    String? appleUrl,
    String? youtubeUrl,
    String? tidalUrl,
    String? soundchartsUrl,
    String? deezerUrl,
    String? soundcloudUrl,
    String? audiusUrl,
    String? beatportUrl,
    PlatformPlayLabelStyle labelStyle = PlatformPlayLabelStyle.iconOnly,
    bool compact = false,
    int? maxLinks,
    WrapAlignment alignment = WrapAlignment.start,
    WrapAlignment runAlignment = WrapAlignment.start,
  }) {
    return PlatformPlayActions(
      key: key,
      links: {
        'spotify': spotifyUrl ?? '',
        'apple': appleUrl ?? '',
        'youtube': youtubeUrl ?? '',
        'tidal': tidalUrl ?? '',
        'soundcharts': soundchartsUrl ?? '',
        'deezer': deezerUrl ?? '',
        'soundcloud': soundcloudUrl ?? '',
        'audius': audiusUrl ?? '',
        'beatport': beatportUrl ?? '',
      },
      labelStyle: labelStyle,
      compact: compact,
      maxLinks: maxLinks,
      alignment: alignment,
      runAlignment: runAlignment,
    );
  }

  final Map<String, String?> links;
  final PlatformPlayLabelStyle labelStyle;
  final bool compact;
  final int? maxLinks;
  final WrapAlignment alignment;
  final WrapAlignment runAlignment;

  @override
  Widget build(BuildContext context) {
    final entries = orderedPlatformLinks(links).entries;
    final visible = maxLinks == null ? entries : entries.take(maxLinks!);
    final items = visible.toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: compact ? 4 : 8,
      runSpacing: compact ? 4 : 8,
      alignment: alignment,
      runAlignment: runAlignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in items)
          _PlatformPlayButton(
            platform: entry.key,
            url: entry.value,
            labelStyle: labelStyle,
            compact: compact,
          ),
      ],
    );
  }
}

Map<String, String> orderedPlatformLinks(Map<String, String?> links) {
  final cleaned = <String, String>{};
  final seenUrls = <String>{};

  for (final entry in links.entries) {
    final platform = normalizePlatformKey(entry.key);
    final url = entry.value?.trim();
    if (platform.isEmpty || url == null || url.isEmpty) continue;
    if (!seenUrls.add(url)) continue;
    cleaned[platform] = url;
  }

  final ordered = <String, String>{};
  for (final key in _platformPriority) {
    final url = cleaned.remove(key);
    if (url != null) ordered[key] = url;
  }
  ordered.addAll(cleaned);
  return ordered;
}

String normalizePlatformKey(String platform) {
  final key = platform.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  switch (key) {
    case 'apple':
    case 'applemusic':
    case 'musicapple':
      return 'apple';
    case 'yt':
    case 'youtube':
    case 'youtubemusic':
    case 'musicyoutube':
      return 'youtube';
    case 'soundchart':
    case 'soundcharts':
      return 'soundcharts';
    case 'soundcloud':
      return 'soundcloud';
    default:
      return key;
  }
}

String platformLabel(String platform) {
  switch (normalizePlatformKey(platform)) {
    case 'spotify':
      return 'Spotify';
    case 'apple':
      return 'Apple Music';
    case 'youtube':
      return 'YouTube Music';
    case 'tidal':
      return 'TIDAL';
    case 'soundcharts':
      return 'Soundcharts';
    case 'deezer':
      return 'Deezer';
    case 'soundcloud':
      return 'SoundCloud';
    case 'audius':
      return 'Audius';
    case 'beatport':
      return 'Beatport';
    case 'billboard':
      return 'Billboard';
    default:
      return platform.isEmpty
          ? 'Browser'
          : '${platform[0].toUpperCase()}${platform.substring(1)}';
  }
}

String platformActionLabel(String platform) {
  final label = platformLabel(platform);
  return normalizePlatformKey(platform) == 'soundcharts'
      ? 'View on $label'
      : 'Play on $label';
}

IconData platformIcon(String platform) {
  switch (normalizePlatformKey(platform)) {
    case 'spotify':
      return Icons.graphic_eq_rounded;
    case 'apple':
      return Icons.music_note_rounded;
    case 'youtube':
      return Icons.play_circle_fill_rounded;
    case 'tidal':
      return Icons.waves_rounded;
    case 'deezer':
      return Icons.headphones_rounded;
    case 'soundcloud':
      return Icons.cloud_rounded;
    case 'audius':
      return Icons.podcasts_rounded;
    case 'beatport':
      return Icons.equalizer_rounded;
    case 'billboard':
      return Icons.bar_chart_rounded;
    case 'soundcharts':
      return Icons.show_chart_rounded;
    default:
      return Icons.open_in_new_rounded;
  }
}

Color platformColor(String platform) {
  switch (normalizePlatformKey(platform)) {
    case 'spotify':
      return const Color(0xFF1ED760);
    case 'apple':
      return const Color(0xFFFF7AB5);
    case 'youtube':
      return const Color(0xFFFF4B4B);
    case 'tidal':
      return const Color(0xFFFFFFFF);
    case 'deezer':
      return const Color(0xFFA238FF);
    case 'soundcloud':
      return const Color(0xFFFFA237);
    case 'audius':
      return const Color(0xFF7C5CFF);
    case 'beatport':
      return const Color(0xFF32FF7E);
    case 'billboard':
      return const Color(0xFFFFD700);
    case 'soundcharts':
      return AppTheme.cyan;
    default:
      return AppTheme.cyan;
  }
}

const _platformPriority = [
  'apple',
  'spotify',
  'youtube',
  'deezer',
  'soundcharts',
  'billboard',
  'tidal',
  'soundcloud',
  'audius',
  'beatport',
];

class _PlatformPlayButton extends StatelessWidget {
  const _PlatformPlayButton({
    required this.platform,
    required this.url,
    required this.labelStyle,
    required this.compact,
  });

  final String platform;
  final String url;
  final PlatformPlayLabelStyle labelStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final actionLabel = platformActionLabel(platform);
    final color = platformColor(platform);
    final icon = platformIcon(platform);

    if (labelStyle == PlatformPlayLabelStyle.iconOnly) {
      return Semantics(
        button: true,
        label: actionLabel,
        child: IconButton(
          icon: Icon(icon, size: compact ? 18 : 20, color: color),
          tooltip: actionLabel,
          onPressed: () => _openUrl(url),
          padding: EdgeInsets.all(compact ? 3 : 4),
          constraints: BoxConstraints(
            minWidth: compact ? 30 : 34,
            minHeight: compact ? 30 : 34,
          ),
        ),
      );
    }

    final label = labelStyle == PlatformPlayLabelStyle.playOnPlatform
        ? actionLabel
        : platformLabel(platform);

    return Semantics(
      button: true,
      label: actionLabel,
      child: Tooltip(
        message: actionLabel,
        child: TextButton.icon(
          onPressed: () => _openUrl(url),
          icon: Icon(icon, size: compact ? 15 : 17, color: color),
          label: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            backgroundColor: color.withValues(alpha: 0.10),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 10,
              vertical: compact ? 6 : 8,
            ),
            minimumSize: Size(0, compact ? 30 : 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: color.withValues(alpha: 0.28)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
