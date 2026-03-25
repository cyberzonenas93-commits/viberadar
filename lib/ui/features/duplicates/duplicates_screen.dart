import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../providers/library_provider.dart';

class DuplicatesScreen extends ConsumerWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Duplicates',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    lib.hasLibrary
                        ? '${lib.duplicateGroups.length} duplicate groups  •  '
                            '${lib.duplicateCount} extra files'
                        : 'Scan your library in My Library first',
                    style: const TextStyle(
                        color: Color(0xFF9099B8), fontSize: 13),
                  ),
                ],
              ),
            ),
            if (lib.duplicateGroups.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.pink.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.pink, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${lib.duplicateCount} duplicates found',
                    style: const TextStyle(
                        color: AppTheme.pink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 24),
          if (!lib.hasLibrary)
            const Expanded(child: _NeedScanState())
          else if (lib.duplicateGroups.isEmpty)
            const Expanded(child: _NoDuplicatesState())
          else
            Expanded(
              child: ListView.separated(
                itemCount: lib.duplicateGroups.length,
                separatorBuilder: (_, _x) =>
                    const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _DuplicateGroupCard(
                  group: lib.duplicateGroups[i],
                  onKeep: (id) =>
                      _keepTrack(ref, lib.duplicateGroups[i], id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _keepTrack(
      WidgetRef ref, DuplicateGroup group, String keepId) {
    for (final t in group.tracks) {
      if (t.id != keepId) {
        ref.read(libraryProvider.notifier).removeTrack(t.id);
      }
    }
  }
}

class _NeedScanState extends StatelessWidget {
  const _NeedScanState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.content_copy_rounded,
              size: 48, color: AppTheme.cyan),
        ),
        const SizedBox(height: 24),
        const Text('Scan library first',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Go to My Library and select a music folder.',
            style:
                TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
      ]),
    );
  }
}

class _NoDuplicatesState extends StatelessWidget {
  const _NoDuplicatesState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.lime.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.lime.withValues(alpha: 0.3)),
          ),
          child: const Icon(Icons.check_circle_outline_rounded,
              size: 48, color: AppTheme.lime),
        ),
        const SizedBox(height: 24),
        const Text('No duplicates found',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Your library is clean.',
            style:
                TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
      ]),
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  final DuplicateGroup group;
  final void Function(String keepId) onKeep;
  const _DuplicateGroupCard(
      {required this.group, required this.onKeep});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(group.reasonLabel,
                    style: const TextStyle(
                        color: AppTheme.pink,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text('${group.tracks.length} copies',
                  style: const TextStyle(
                      color: Color(0xFF9099B8), fontSize: 12)),
            ]),
          ),
          const Divider(color: AppTheme.edge, height: 1),
          ...group.tracks.map((t) =>
              _DupeTrackRow(track: t, onKeep: () => onKeep(t.id))),
        ],
      ),
    );
  }
}

class _DupeTrackRow extends StatelessWidget {
  final LibraryTrack track;
  final VoidCallback onKeep;
  const _DupeTrackRow(
      {required this.track, required this.onKeep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.violet.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            track.fileExtension.replaceFirst('.', '').toUpperCase(),
            style: const TextStyle(
                color: AppTheme.violet,
                fontSize: 10,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
              Text(track.filePath,
                  style: const TextStyle(
                      color: Color(0xFF9099B8), fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Text(track.fileSizeFormatted,
            style: const TextStyle(
                color: Color(0xFF9099B8), fontSize: 11)),
        const SizedBox(width: 12),
        TextButton(
          onPressed: onKeep,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.lime,
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 6),
            side: const BorderSide(color: AppTheme.lime),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text('Keep This',
              style: TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }
}
