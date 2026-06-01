import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/crate.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/setlist_provider.dart';
import '../../services/pairing_service.dart';
import 'connect_computer_sheet.dart';

// ---------------------------------------------------------------------------
// Pure helper — exposed for unit testing.
// ---------------------------------------------------------------------------

/// Returns a new list where the item at [oldIndex] is moved to [newIndex].
///
/// Follows the same semantics as [ReorderableListView.onReorder]: when the
/// item is dragged downward the destination index is already adjusted by
/// Flutter, so callers should pass the raw [newIndex] from [onReorder]
/// unchanged.
List<String> reorderTrackIds(List<String> ids, int oldIndex, int newIndex) {
  final list = List<String>.from(ids);
  // When moving downward Flutter reports newIndex one past the insertion point;
  // account for the removed element by decrementing.
  final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
  final item = list.removeAt(oldIndex);
  list.insert(adjustedNew, item);
  return list;
}

// ---------------------------------------------------------------------------
// SetlistEditor
// ---------------------------------------------------------------------------

class SetlistEditor extends ConsumerStatefulWidget {
  const SetlistEditor({super.key, required this.crate});

  final Crate crate;

  @override
  ConsumerState<SetlistEditor> createState() => _SetlistEditorState();
}

class _SetlistEditorState extends ConsumerState<SetlistEditor> {
  late List<String> _trackIds;
  late String _name;

  // TextField controller for the AppBar title rename.
  late final TextEditingController _nameController;
  bool _editingName = false;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _trackIds = List<String>.from(widget.crate.trackIds);
    _name = widget.crate.name;
    _nameController = TextEditingController(text: _name);
    _nameFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.removeListener(_onFocusChange);
    _nameFocus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_nameFocus.hasFocus && _editingName) {
      _commitRename();
    }
  }

  // ---- persistence helpers -------------------------------------------------

  Crate get _current =>
      widget.crate.copyWith(trackIds: _trackIds, name: _name);

  Future<void> _save(Crate crate) =>
      ref.read(setlistActionsProvider).save(crate);

  // ---- reorder -------------------------------------------------------------

  void _onReorder(int oldIndex, int newIndex) {
    final newIds = reorderTrackIds(_trackIds, oldIndex, newIndex);
    setState(() => _trackIds = newIds);
    _save(widget.crate.copyWith(trackIds: newIds, name: _name));
  }

  // ---- remove --------------------------------------------------------------

  void _removeTrack(int index) {
    final newIds = List<String>.from(_trackIds)..removeAt(index);
    setState(() => _trackIds = newIds);
    _save(widget.crate.copyWith(trackIds: newIds, name: _name));
  }

  // ---- rename --------------------------------------------------------------

  void _beginRename() {
    setState(() {
      _editingName = true;
      _nameController.text = _name;
      // Select all for quick replacement.
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _name.length,
      );
    });
    // Request focus on the next frame so the TextField is in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  void _commitRename() {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == _name) {
      setState(() => _editingName = false);
      return;
    }
    setState(() {
      _name = newName;
      _editingName = false;
    });
    _save(widget.crate.copyWith(trackIds: _trackIds, name: newName));
  }

  // ---- send to computer ----------------------------------------------------

  Future<void> _sendToComputer(PairedComputer pairing) async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    await ref.read(pairingServiceProvider).pushSetlist(
          pairing.pairingId,
          _current,
          editorUid: session.userId,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent to ${pairing.desktopName}')),
    );
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Resolve trackId → Track from the live stream.
    final tracksAsync = ref.watch(trackStreamProvider);
    final trackMap = <String, Track>{};
    for (final t in tracksAsync.value ?? const <Track>[]) {
      trackMap[t.id] = t;
    }

    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: _buildAppBar(),
      body: _trackIds.isEmpty
          ? _buildEmpty()
          : _buildList(trackMap),
    );
  }

  AppBar _buildAppBar() {
    final paired = ref.watch(pairedComputerProvider);

    return AppBar(
      backgroundColor: AppTheme.panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: BackButton(color: AppTheme.textSecondary),
      // --- actions: sync chip + optional send button ---
      actions: [
        if (paired != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              key: const Key('send_to_computer_button'),
              onPressed: () => _sendToComputer(paired),
              icon: const Icon(
                Icons.send_outlined,
                size: 16,
                color: AppTheme.violet,
              ),
              label: Text(
                'Send to ${paired.desktopName}',
                style: const TextStyle(
                  color: AppTheme.violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Chip(
            label: const Text(
              'Synced',
              style: TextStyle(
                color: AppTheme.lime,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            avatar: const Icon(
              Icons.cloud_done_outlined,
              size: 14,
              color: AppTheme.lime,
            ),
            backgroundColor: AppTheme.surface,
            side: BorderSide(color: AppTheme.lime.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
      // --- editable title ---
      title: _editingName
          ? TextField(
              key: const Key('setlist_name_field'),
              controller: _nameController,
              focusNode: _nameFocus,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _commitRename(),
            )
          : GestureDetector(
              onTap: _beginRename,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: AppTheme.textTertiary,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No tracks yet — add some from Search or Trending.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildList(Map<String, Track> trackMap) {
    return ReorderableListView.builder(
      itemCount: _trackIds.length,
      onReorder: _onReorder,
      buildDefaultDragHandles: false, // we add our own handle
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemBuilder: (context, index) {
        final id = _trackIds[index];
        final track = trackMap[id];
        return _TrackRow(
          key: ValueKey(id),
          index: index,
          trackId: id,
          track: track,
          onDelete: () => _removeTrack(index),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private track row
// ---------------------------------------------------------------------------

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    super.key,
    required this.index,
    required this.trackId,
    required this.track,
    required this.onDelete,
  });

  final int index;
  final String trackId;
  final Track? track; // null when id doesn't resolve
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = track?.title ?? 'Unknown track';
    final subtitle = track != null
        ? '${track!.artist}  ·  ${formatBpm(track!.bpm)} BPM'
        : trackId;

    return ListTile(
      tileColor: AppTheme.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(
          Icons.drag_handle,
          color: AppTheme.textTertiary,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        color: AppTheme.textTertiary,
        tooltip: 'Remove track',
        onPressed: onDelete,
      ),
    );
  }
}
