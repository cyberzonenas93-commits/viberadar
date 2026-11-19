import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/crate.dart';
import '../../models/crate_track.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/setlist_provider.dart';
import '../../services/crate_export_planner.dart';
import '../../services/pairing_service.dart';
import 'connect_computer_sheet.dart';
import '../widgets/platform_play_actions.dart';

// ---------------------------------------------------------------------------
// Pure helper — exposed for unit testing.
// ---------------------------------------------------------------------------

/// Returns a new list where the item at [oldIndex] is moved to [newIndex].
///
/// Follows the same semantics as [ReorderableListView.onReorder]: when the
/// item is dragged downward the destination index is already adjusted by
/// Flutter, so callers should pass the raw [newIndex] from [onReorder]
/// unchanged.
List<CrateTrack> reorderTracks(
  List<CrateTrack> tracks,
  int oldIndex,
  int newIndex,
) {
  final list = List<CrateTrack>.from(tracks);
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
  late List<CrateTrack> _tracks;
  late String _name;

  // TextField controller for the AppBar title rename.
  late final TextEditingController _nameController;
  bool _editingName = false;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tracks = List<CrateTrack>.from(widget.crate.tracks);
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

  Crate get _current => widget.crate.copyWith(tracks: _tracks, name: _name);

  Future<void> _save(Crate crate) =>
      ref.read(setlistActionsProvider).save(crate);

  // ---- reorder -------------------------------------------------------------

  void _onReorder(int oldIndex, int newIndex) {
    final newTracks = reorderTracks(_tracks, oldIndex, newIndex);
    setState(() => _tracks = newTracks);
    _save(widget.crate.copyWith(tracks: newTracks, name: _name));
  }

  // ---- add tracks ----------------------------------------------------------

  void _addPickedTrack(Track track) {
    final merged = mergeTracks(_tracks, [crateTrackFromTrack(track)]);
    if (merged.length == _tracks.length) return; // already present
    setState(() => _tracks = merged);
    _save(_current);
  }

  Future<void> _openAddTracks() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddTracksSheet(
        existingKeys: _tracks.map((t) => t.stableKey).toSet(),
        onAdd: _addPickedTrack,
      ),
    );
  }

  // ---- remove --------------------------------------------------------------

  void _removeTrack(int index) {
    final newTracks = List<CrateTrack>.from(_tracks)..removeAt(index);
    setState(() => _tracks = newTracks);
    _save(widget.crate.copyWith(tracks: newTracks, name: _name));
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
    _save(widget.crate.copyWith(tracks: _tracks, name: newName));
  }

  // ---- send to computer ----------------------------------------------------

  Future<void> _sendToComputer(PairedComputer pairing) async {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    await ref
        .read(pairingServiceProvider)
        .pushSetlist(pairing.pairingId, _current, editorUid: session.userId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sent to ${pairing.desktopName}')));
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Resolve reference (id-only) entries against the live tracks stream.
    final tracksAsync = ref.watch(trackStreamProvider);
    final trackMap = <String, Track>{};
    for (final t in tracksAsync.value ?? const <Track>[]) {
      trackMap[t.id] = t;
    }

    return Scaffold(
      backgroundColor: AppTheme.ink,
      appBar: _buildAppBar(),
      body: _tracks.isEmpty ? _buildEmpty() : _buildList(trackMap),
    );
  }

  AppBar _buildAppBar() {
    final paired = ref.watch(pairedComputerProvider);
    final session = ref.watch(sessionProvider).value;
    // Only a real signed-in account actually backs up + syncs setlists to the
    // cloud. Guests/demo keep them on-device only — say so instead of always
    // claiming "Synced".
    final synced = session?.isAuthenticated == true && session?.isDemo != true;

    return AppBar(
      backgroundColor: AppTheme.panel,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: BackButton(color: AppTheme.textSecondary),
      // --- actions: add tracks + sync chip + optional send button ---
      actions: [
        IconButton(
          key: const Key('add_tracks_button'),
          icon: const Icon(Icons.add_rounded, color: AppTheme.cyan),
          tooltip: 'Add tracks',
          onPressed: () => _openAddTracks(),
        ),
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
          child: Tooltip(
            message: synced
                ? 'Backed up to your account and synced across your devices'
                : 'Saved on this device only — sign in to back up and sync',
            child: Chip(
              label: Text(
                synced ? 'Synced' : 'Local only',
                style: TextStyle(
                  color: synced ? AppTheme.lime : AppTheme.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              avatar: Icon(
                synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                size: 14,
                color: synced ? AppTheme.lime : AppTheme.textTertiary,
              ),
              backgroundColor: AppTheme.surface,
              side: BorderSide(
                color: (synced ? AppTheme.lime : AppTheme.textTertiary)
                    .withValues(alpha: 0.3),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.queue_music_rounded,
              color: AppTheme.textTertiary,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'No tracks yet',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap “Add tracks” to pull from the trends library — or browse '
              'Trending, Search or AI and choose “Add to Setlist”.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _openAddTracks(),
              icon: const Icon(Icons.add_rounded, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: AppTheme.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              label: const Text('Add tracks'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Map<String, Track> trackMap) {
    return ReorderableListView.builder(
      itemCount: _tracks.length,
      onReorder: _onReorder,
      buildDefaultDragHandles: false, // we add our own handle
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemBuilder: (context, index) {
        final entry = _tracks[index];
        final resolved = entry.isReference ? trackMap[entry.trackId] : null;
        return _TrackRow(
          key: ValueKey('${entry.stableKey}#$index'),
          index: index,
          entry: entry,
          resolved: resolved,
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
    required this.entry,
    required this.resolved,
    required this.onDelete,
  });

  final int index;
  final CrateTrack entry;
  final Track? resolved; // non-null only for resolved reference entries
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = entry.title.isNotEmpty
        ? entry.title
        : (resolved?.title ?? 'Unknown track');
    final artist = entry.artist.isNotEmpty
        ? entry.artist
        : (resolved?.artist ?? '');
    final bpm = entry.bpm != 0 ? entry.bpm : (resolved?.bpm ?? 0);
    final subtitle = [
      if (artist.isNotEmpty) artist,
      if (bpm > 0) '${formatBpm(bpm)} BPM',
    ].join('  ·  ');
    final platformLinks = <String, String?>{
      if (entry.hasUrl) ...{
        'spotify': entry.spotifyUrl,
        'apple': entry.appleUrl,
        'youtube': entry.youtubeUrl,
      } else
        ...resolved?.platformLinks ?? const <String, String>{},
    };

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
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 112),
            child: PlatformPlayActions(
              links: platformLinks,
              compact: true,
              maxLinks: 3,
              alignment: WrapAlignment.end,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppTheme.textTertiary,
            tooltip: 'Remove track',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-tracks picker — search the trends library and add to the open setlist
// without leaving the editor.
// ---------------------------------------------------------------------------

class _AddTracksSheet extends ConsumerStatefulWidget {
  const _AddTracksSheet({required this.existingKeys, required this.onAdd});

  final Set<String> existingKeys;
  final void Function(Track) onAdd;

  @override
  ConsumerState<_AddTracksSheet> createState() => _AddTracksSheetState();
}

class _AddTracksSheetState extends ConsumerState<_AddTracksSheet> {
  final _controller = TextEditingController();
  String _query = '';
  late final Set<String> _added = {...widget.existingKeys};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(trackStreamProvider).value ?? const <Track>[];
    final q = _query.trim().toLowerCase();
    final matches =
        (q.isEmpty
                ? all
                : all.where(
                    (t) =>
                        t.title.toLowerCase().contains(q) ||
                        t.artist.toLowerCase().contains(q),
                  ))
            .take(80)
            .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search trending tracks…',
                hintStyle: const TextStyle(color: AppTheme.textTertiary),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.textSecondary,
                ),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: matches.isEmpty
                  ? const Center(
                      child: Text(
                        'No matches',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (ctx, i) {
                        final t = matches[i];
                        final added = _added.contains(t.id);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              t.artist,
                              if (t.bpm > 0) '${formatBpm(t.bpm)} BPM',
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: added
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.lime,
                                )
                              : const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: AppTheme.cyan,
                                ),
                          onTap: added
                              ? null
                              : () {
                                  widget.onAdd(t);
                                  setState(() => _added.add(t.id));
                                },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
