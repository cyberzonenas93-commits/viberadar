import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';

/// Shows a context menu when a track card is tapped.
/// Options: Play (opens in Spotify/Apple/YouTube), Add to Crate, Track Info.
void showTrackActionMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  Offset? position,
}) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final pos = position ?? Offset(overlay.size.width / 2, overlay.size.height / 2);

  showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
    color: AppTheme.panelRaised,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    elevation: 8,
    items: [
      // Individual platform play options
      for (final entry in track.platformLinks.entries)
        PopupMenuItem(
          value: 'play:${entry.key}',
          child: Row(
            children: [
              Icon(_iconForPlatform(entry.key), color: _colorForPlatform(entry.key), size: 18),
              const SizedBox(width: 10),
              Text('Play on ${_capitalize(entry.key)}',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
      // Divider between play and actions
      if (track.platformLinks.isNotEmpty)
        const PopupMenuDivider(),
      // Add to crate
      PopupMenuItem(
        value: 'crate',
        child: Row(
          children: [
            Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 18),
            const SizedBox(width: 10),
            const Text('Add to Crate',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ],
        ),
      ),
      // Track info
      PopupMenuItem(
        value: 'info',
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.textSecondary, size: 18),
            const SizedBox(width: 10),
            const Text('Track Info',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
          ],
        ),
      ),
    ],
  ).then((value) {
    if (value == null) return;
    if (value.startsWith('play:')) {
      final platform = value.substring(5);
      final url = track.platformLinks[platform];
      if (url != null) _openUrl(url);
    } else if (value == 'crate') {
      _showAddToCrateSheet(context, ref, track);
    } else if (value == 'info') {
      _showTrackInfoSheet(context, track);
    }
  });
}

/// Simpler version for use outside ConsumerWidget (uses GlobalKey etc.)
void showTrackActionMenuFromCard(
  BuildContext context,
  WidgetRef ref,
  Track track,
  TapDownDetails details,
) {
  showTrackActionMenu(context, ref, track, position: details.globalPosition);
}

void _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

IconData _iconForPlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'spotify': return Icons.graphic_eq_rounded;
    case 'apple': return Icons.music_note_rounded;
    case 'youtube': return Icons.play_circle_fill_rounded;
    case 'deezer': return Icons.headphones_rounded;
    case 'soundcloud': return Icons.cloud_rounded;
    case 'beatport': return Icons.equalizer_rounded;
    case 'audius': return Icons.podcasts_rounded;
    case 'billboard': return Icons.bar_chart_rounded;
    default: return Icons.open_in_new_rounded;
  }
}

Color _colorForPlatform(String platform) {
  switch (platform.toLowerCase()) {
    case 'spotify': return const Color(0xFF1ED760);
    case 'apple': return const Color(0xFFFF7AB5);
    case 'youtube': return const Color(0xFFFF4B4B);
    case 'deezer': return const Color(0xFFA238FF);
    case 'soundcloud': return const Color(0xFFFFA237);
    case 'beatport': return const Color(0xFF32FF7E);
    case 'audius': return const Color(0xFF7C5CFF);
    case 'billboard': return const Color(0xFFFFD700);
    default: return AppTheme.cyan;
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

void _showAddToCrateSheet(BuildContext context, WidgetRef ref, Track track) {
  final crateState = ref.read(crateProvider);
  final crates = crateState.crates.keys.toList();

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 20),
              const SizedBox(width: 10),
              Text('Add to Crate', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${track.title} — ${track.artist}',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          const SizedBox(height: 16),
          // Existing crates
          if (crates.isNotEmpty)
            ...crates.map((name) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_rounded, color: AppTheme.violet, size: 20),
              title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              trailing: Text('${crateState.crates[name]?.length ?? 0} tracks',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
              onTap: () {
                ref.read(crateProvider.notifier).addTrackToCrate(name, track.id);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added "${track.title}" to $name'),
                    backgroundColor: AppTheme.violet,
                  ),
                );
              },
            )),
          const Divider(color: AppTheme.edge),
          // New crate
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_circle_rounded, color: AppTheme.cyan, size: 20),
            title: const Text('New Crate...', style: TextStyle(color: AppTheme.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.of(ctx).pop();
              _showNewCrateDialog(context, ref, track);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showNewCrateDialog(BuildContext context, WidgetRef ref, Track track) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('New Crate', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Crate name...'),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            ref.read(crateProvider.notifier).createCrate(value.trim());
            ref.read(crateProvider.notifier).addTrackToCrate(value.trim(), track.id);
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Created "${value.trim()}" with "${track.title}"'), backgroundColor: AppTheme.violet),
            );
          }
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              ref.read(crateProvider.notifier).createCrate(name);
              ref.read(crateProvider.notifier).addTrackToCrate(name, track.id);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Created "$name" with "${track.title}"'), backgroundColor: AppTheme.violet),
              );
            }
          },
          child: const Text('Create & Add'),
        ),
      ],
    ),
  );
}

void _showTrackInfoSheet(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(track.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _InfoTag(icon: Icons.speed_rounded, label: '${track.bpm} BPM'),
              _InfoTag(icon: Icons.music_note_rounded, label: track.keySignature),
              _InfoTag(icon: Icons.category_rounded, label: track.genre),
              _InfoTag(icon: Icons.public_rounded, label: track.leadRegion),
              _InfoTag(icon: Icons.trending_up_rounded, label: 'Score: ${(track.trendScore * 100).toInt()}'),
              _InfoTag(icon: Icons.bolt_rounded, label: 'Energy: ${(track.energyLevel * 100).toInt()}%'),
            ],
          ),
          const SizedBox(height: 16),
          if (track.platformLinks.isNotEmpty) ...[
            const Text('Available on:', style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: track.platformLinks.entries.map((e) => ActionChip(
                label: Text(e.key[0].toUpperCase() + e.key.substring(1), style: const TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.play_arrow_rounded, size: 14),
                onPressed: () async {
                  final uri = Uri.tryParse(e.value);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              )).toList(),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}

String _platformLabel(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    if (track.platformLinks.containsKey(key)) {
      return key[0].toUpperCase() + key.substring(1);
    }
  }
  return 'Browser';
}

class _InfoTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── Bulk add to crate ─────────────────────────────────────────────────────────

/// Shows a sheet to add multiple tracks to a crate at once.
void showBulkAddToCrate(BuildContext context, WidgetRef ref, List<Track> tracks) {
  if (tracks.isEmpty) return;
  final crateState = ref.read(crateProvider);
  final crates = crateState.crates.keys.toList();

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 20),
              const SizedBox(width: 10),
              Text('Add ${tracks.length} tracks to Crate',
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          if (crates.isNotEmpty)
            ...crates.map((name) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_rounded, color: AppTheme.violet, size: 20),
              title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              trailing: Text('${crateState.crates[name]?.length ?? 0} tracks',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
              onTap: () {
                for (final t in tracks) {
                  ref.read(crateProvider.notifier).addTrackToCrate(name, t.id);
                }
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${tracks.length} tracks to $name'),
                    backgroundColor: AppTheme.violet,
                  ),
                );
              },
            )),
          const Divider(color: AppTheme.edge),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_circle_rounded, color: AppTheme.cyan, size: 20),
            title: const Text('New Crate...', style: TextStyle(color: AppTheme.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.of(ctx).pop();
              _showNewBulkCrateDialog(context, ref, tracks);
            },
          ),
        ],
      ),
    ),
  );
}

void _showNewBulkCrateDialog(BuildContext context, WidgetRef ref, List<Track> tracks) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('New Crate', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(hintText: 'Crate name...'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              ref.read(crateProvider.notifier).createCrate(name);
              for (final t in tracks) {
                ref.read(crateProvider.notifier).addTrackToCrate(name, t.id);
              }
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Created "$name" with ${tracks.length} tracks'), backgroundColor: AppTheme.violet),
              );
            }
          },
          child: const Text('Create & Add All'),
        ),
      ],
    ),
  );
}
