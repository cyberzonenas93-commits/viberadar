import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../widgets/add_to_setlist_sheet.dart';
import '../widgets/platform_play_actions.dart';
import '../widgets/source_badges.dart';
import '../widgets/track_action_menu.dart';

class TrendingTab extends ConsumerWidget {
  const TrendingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTracks = ref.watch(trackStreamProvider);

    return asyncTracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const Center(child: Text('No trending tracks yet.'));
        }

        // Sort a copy by trendScore descending
        final sorted = [...tracks]
          ..sort((a, b) => b.trendScore.compareTo(a.trendScore));

        return ListView.separated(
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final track = sorted[index];
            return _TrendingRow(track: track);
          },
        );
      },
    );
  }
}

class _TrendingRow extends ConsumerWidget {
  const _TrendingRow({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: _Artwork(url: track.artworkUrl),
      onTap: () => showTrackActionMenu(context, ref, track),
      title: Text(
        track.title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artist,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _BpmChip(bpm: track.bpm),
              const SizedBox(width: 8),
              Flexible(
                child: SourceBadges(
                  sources: track.effectiveSources,
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          PlatformPlayActions(
            links: track.platformLinks,
            compact: true,
            maxLinks: 3,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline),
        tooltip: 'Add to setlist',
        onPressed: () => showAddToSetlistSheet(context, ref, track),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const _ArtworkPlaceholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        placeholder: (_, __) => const _ArtworkPlaceholder(),
        errorWidget: (_, __, ___) => const _ArtworkPlaceholder(),
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.music_note, size: 24, color: Colors.white38),
    );
  }
}

class _BpmChip extends StatelessWidget {
  const _BpmChip({required this.bpm});

  final int bpm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${formatBpm(bpm)} BPM',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
