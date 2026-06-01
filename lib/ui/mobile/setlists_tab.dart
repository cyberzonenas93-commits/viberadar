import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/setlist_provider.dart';
import 'connect_computer_sheet.dart';
import 'setlist_editor.dart';

class SetlistsTab extends ConsumerWidget {
  const SetlistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlists = ref.watch(setlistsProvider);
    final paired = ref.watch(pairedComputerProvider);

    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: AppBar(
        title: const Text(
          'Setlists',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppTheme.panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (paired == null)
            // No computer connected — show link icon to open the sheet.
            IconButton(
              key: const Key('connect_computer_button'),
              icon: const Icon(Icons.link, color: AppTheme.textSecondary),
              tooltip: 'Connect a computer',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppTheme.panel,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (_) => const ConnectComputerSheet(),
              ),
            )
          else
            // Connected — show the desktop name chip; tap to disconnect.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () =>
                    ref.read(pairedComputerProvider.notifier).set(null),
                child: Chip(
                  key: const Key('paired_computer_chip'),
                  label: Text(
                    '\u{1F4F1} ${paired.desktopName}',
                    style: const TextStyle(
                      color: AppTheme.lime,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: AppTheme.surface,
                  side: BorderSide(color: AppTheme.lime.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
      body: setlists.isEmpty ? _buildEmpty() : _buildList(context, ref, setlists),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.violet,
        foregroundColor: Colors.white,
        onPressed: () => _showCreateDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text(
        'No setlists yet — tap ＋ to create one.',
        style: TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 15,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, crates) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: crates.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: AppTheme.edge.withValues(alpha: 0.4),
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final crate = crates[index];
        final trackCount = crate.trackIds.length;
        final subtitle =
            '$trackCount tracks  ·  ${formatUpdatedAt(crate.updatedAt)}';

        return InkWell(
          onTap: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SetlistEditor(crate: crate),
              ),
            );
          },
          child: ListTile(
            tileColor: Colors.transparent,
            title: Text(
              crate.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CreateSetlistDialog(onSubmit: (name) {
        if (name.isNotEmpty) {
          ref.read(setlistActionsProvider).create(name);
        }
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Private dialog widget — owns its own TextEditingController lifecycle.
// ---------------------------------------------------------------------------

class _CreateSetlistDialog extends StatefulWidget {
  const _CreateSetlistDialog({required this.onSubmit});
  final void Function(String name) onSubmit;

  @override
  State<_CreateSetlistDialog> createState() => _CreateSetlistDialogState();
}

class _CreateSetlistDialogState extends State<_CreateSetlistDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSubmit(_controller.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panelRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
      ),
      title: const Text(
        'New Setlist',
        style: TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Setlist name',
          filled: true,
          fillColor: AppTheme.surface,
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.violet,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
