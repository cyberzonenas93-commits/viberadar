import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/track_selection_provider.dart';

/// Floating action bar shown when tracks are multi-selected.
/// Displays count and actions: Add to Crate, Clear.
class SelectionActionBar extends ConsumerWidget {
  const SelectionActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(trackSelectionProvider);
    if (!sel.isSelecting || sel.count == 0) return const SizedBox.shrink();

    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(16),
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.panelRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.violet.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.violet,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${sel.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${sel.count == 1 ? 'track' : 'tracks'} selected',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 20),
                // Add to Crate button
                _ActionButton(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to Crate',
                  color: AppTheme.violet,
                  onTap: () => _showCrateDialog(context, ref),
                ),
                const SizedBox(width: 10),
                // Clear button
                _ActionButton(
                  icon: Icons.close_rounded,
                  label: 'Clear',
                  color: AppTheme.textSecondary,
                  onTap: () => ref.read(trackSelectionProvider.notifier).clear(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCrateDialog(BuildContext context, WidgetRef ref) {
    final crateState = ref.read(crateProvider);
    final selectedIds = ref.read(trackSelectionProvider).selectedIds.toList();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add ${selectedIds.length} tracks to crate',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Create new
              TextField(
                controller: nameController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'New crate name...',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.edge),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.edge),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_rounded, color: AppTheme.violet, size: 20),
                    onPressed: () {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;
                      final notifier = ref.read(crateProvider.notifier);
                      notifier.createCrate(name);
                      for (final id in selectedIds) {
                        notifier.addTrackToCrate(name, id);
                      }
                      ref.read(trackSelectionProvider.notifier).clear();
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Added ${selectedIds.length} tracks to "$name"'),
                        backgroundColor: AppTheme.violet,
                      ));
                    },
                  ),
                ),
              ),
              if (crateState.crateNames.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Or add to existing:',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: crateState.crateNames.length,
                    itemBuilder: (_, i) {
                      final name = crateState.crateNames[i];
                      final count = crateState.crates[name]?.length ?? 0;
                      return ListTile(
                        dense: true,
                        title: Text(name,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                        trailing: Text('$count tracks',
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        hoverColor: AppTheme.violet.withValues(alpha: 0.1),
                        onTap: () {
                          final notifier = ref.read(crateProvider.notifier);
                          for (final id in selectedIds) {
                            notifier.addTrackToCrate(name, id);
                          }
                          ref.read(trackSelectionProvider.notifier).clear();
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Added ${selectedIds.length} tracks to "$name"'),
                            backgroundColor: AppTheme.violet,
                          ));
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
