import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/track.dart';
import '../../providers/setlist_provider.dart';

/// Adds [track] to one of the user's synced setlists (or a new one).
///
/// Backed by `savedCrates` via [setlistActionsProvider], so the track shows up
/// in the Setlists tab and syncs to the desktop. This is the single "set"
/// concept on the phone — every mobile track card routes here, instead of the
/// desktop-only local crate store, so nothing lands in a dead end.
Future<void> showAddToSetlistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => SafeArea(child: _AddToSetlistSheet(track: track)),
  );
}

class _AddToSetlistSheet extends ConsumerWidget {
  const _AddToSetlistSheet({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlists = ref.watch(setlistsProvider);
    final actions = ref.read(setlistActionsProvider);
    final messenger = ScaffoldMessenger.of(context);

    void done(String name) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added to $name: "${track.title}"'),
          backgroundColor: AppTheme.violet,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.edge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(
                Icons.playlist_add_rounded,
                color: AppTheme.violet,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'Add to Setlist',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${track.title} — ${track.artist}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final setlist in setlists)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.queue_music_rounded,
                        color: AppTheme.violet,
                        size: 20,
                      ),
                      title: Text(
                        setlist.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      trailing: Text(
                        '${setlist.tracks.length}',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                      onTap: () async {
                        await actions.addResolvedTrack(setlist, track);
                        done(setlist.name);
                      },
                    ),
                ],
              ),
            ),
          ),
          const Divider(color: AppTheme.edge),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.add_circle_rounded,
              color: AppTheme.cyan,
              size: 20,
            ),
            title: const Text(
              'New setlist…',
              style: TextStyle(
                color: AppTheme.cyan,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () async {
              final name = await _promptName(context);
              if (name == null || name.isEmpty) return;
              await actions.createWithResolvedTrack(name, track);
              done(name);
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _promptName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelRaised,
        title: const Text(
          'New setlist',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Setlist name'),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
