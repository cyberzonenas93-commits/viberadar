import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/crate.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/setlist_provider.dart';
import '../widgets/source_badges.dart';

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
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline),
        tooltip: 'Add to setlist',
        onPressed: () => _showAddSheet(context, ref, track),
      ),
    );
  }

  Future<void> _showAddSheet(
    BuildContext context,
    WidgetRef ref,
    Track track,
  ) async {
    final setlists = ref.read(setlistsProvider);
    final actions = ref.read(setlistActionsProvider);

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetCtx) {
        return SafeArea(
          child: _AddToSetlistSheet(
            track: track,
            setlists: setlists,
            actions: actions,
            onDone: (name) {
              Navigator.of(sheetCtx).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Added to $name')));
            },
          ),
        );
      },
    );
  }
}

class _AddToSetlistSheet extends StatelessWidget {
  const _AddToSetlistSheet({
    required this.track,
    required this.setlists,
    required this.actions,
    required this.onDone,
  });

  final Track track;
  final List<Crate> setlists;
  final SetlistActions actions;
  final void Function(String name) onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        ...setlists.map(
          (crate) => ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(crate.name),
            onTap: () async {
              await actions.addTrack(crate, track.id);
              onDone(crate.name);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New setlist…'),
          onTap: () => _promptNewSetlist(context),
        ),
      ],
    );
  }

  Future<void> _promptNewSetlist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New setlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Setlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    await actions.createWithTrack(name, track.id);
    onDone(name);
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
