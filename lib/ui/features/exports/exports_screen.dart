import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/dj_export_result.dart';
import '../../../models/library_track.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/cue_provider.dart';
import '../../../providers/dj_export_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../services/export_service.dart';
import '../../../services/local_match_service.dart';
import '../cues/cue_preview_panel.dart';

class ExportsScreen extends ConsumerStatefulWidget {
  const ExportsScreen({super.key});
  @override
  ConsumerState<ExportsScreen> createState() => _ExportsScreenState();
}

class _ExportsScreenState extends ConsumerState<ExportsScreen> {
  String? _selectedCrate;
  final _crateNameController = TextEditingController();
  String? _exportingFormat;
  String? _lastExportPath;
  final _exportService = ExportService();

  // Match panel state
  final _matchService = LocalMatchService();
  List<TrackMatch>? _matchResults;
  bool _isMatching = false;
  bool _exportMatchedOnly = false;
  String? _expandedMatchId; // track id whose candidates are shown

  // ── Physical crate state ─────────────────────────────────────────────────
  CrateType _physCrateType = CrateType.virtualOnly;
  String? _physDestDir;
  bool _physCreating = false;
  double _physProgress = 0.0; // 0.0 – 1.0
  PhysicalCrateResult? _physResult;

  static final _dummyTrack = LibraryTrack(
    id: 'dummy',
    filePath: '',
    fileName: '',
    title: '',
    artist: '',
    album: '',
    genre: '',
    bpm: 0,
    key: '',
    durationSeconds: 0,
    fileSizeBytes: 0,
    fileExtension: '',
    md5Hash: '',
    bitrate: 0,
    sampleRate: 0,
  );

  @override
  void dispose() {
    _crateNameController.dispose();
    super.dispose();
  }

  Future<void> _runMatch(List<Track> vibeTracks, List<LibraryTrack> library) async {
    setState(() { _isMatching = true; _matchResults = null; });
    final results = await _matchService.matchSet(vibeTracks, library);
    if (mounted) setState(() { _matchResults = results; _isMatching = false; });
  }

  // ── Physical crate helpers ───────────────────────────────────────────────

  Future<void> _pickDestDir() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose destination folder for physical crate',
    );
    if (result != null && mounted) {
      setState(() {
        _physDestDir = result;
        _physResult = null;
      });
    }
  }

  Future<void> _createPhysicalCrate(
      String crateName, List<LibraryTrack> tracks) async {
    if (_physCrateType != CrateType.virtualOnly &&
        (_physDestDir == null || _physDestDir!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please choose a destination folder first.'),
        backgroundColor: AppTheme.amber,
      ));
      return;
    }

    setState(() {
      _physCreating = true;
      _physProgress = 0;
      _physResult = null;
    });

    try {
      final result = await _exportService.createPhysicalCrate(
        tracks: tracks,
        crateName: crateName,
        type: _physCrateType,
        destinationDir: _physDestDir ?? '',
        overwriteExisting: false,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _physProgress = done / total);
          }
        },
      );
      if (mounted) {
        setState(() {
          _physCreating = false;
          _physProgress = 1.0;
          _physResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _physCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Crate creation failed: $e'),
          backgroundColor: AppTheme.pink,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final crateState = ref.watch(crateProvider);
    final lib = ref.watch(libraryProvider);
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final vibeTracks = tracksAsync.value ?? const <Track>[];

    final crateTrackIds = _selectedCrate != null
        ? crateState.crates[_selectedCrate] ?? []
        : <String>[];
    // Resolve tracks from BOTH local library and streaming/Firestore sources
    final crateLibTracks = crateTrackIds
        .map((id) {
          // First check local library
          final local = lib.tracks.cast<LibraryTrack?>().firstWhere(
                (t) => t?.id == id,
                orElse: () => null,
              );
          if (local != null) return local;
          // Then check streaming tracks — wrap as LibraryTrack stub
          final vibe = vibeTracks.cast<Track?>().firstWhere(
                (t) => t?.id == id,
                orElse: () => null,
              );
          if (vibe != null) {
            return LibraryTrack(
              id: vibe.id,
              filePath: '',
              fileName: '',
              title: vibe.title,
              artist: vibe.artist,
              album: '',
              genre: vibe.genre,
              bpm: vibe.bpm.toDouble(),
              key: vibe.keySignature,
              durationSeconds: 0,
              fileSizeBytes: 0,
              fileExtension: '',
              md5Hash: '',
              bitrate: 0,
              sampleRate: 0,
            );
          }
          return _dummyTrack;
        })
        .where((t) => t.id != 'dummy')
        .toList();

    return Row(children: [
      // ── Left: crate list panel ───────────────────────────────────────────
      Container(
        width: 240,
        decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppTheme.edge))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Crates',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _crateNameController,
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'New crate name…',
                          hintStyle: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                          filled: true,
                          fillColor: AppTheme.panelRaised,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.edge),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.edge),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        final name = _crateNameController.text.trim();
                        if (name.isNotEmpty) {
                          ref
                              .read(crateProvider.notifier)
                              .createCrate(name);
                          setState(() => _selectedCrate = name);
                          _crateNameController.clear();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.violet,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.add,
                            color: AppTheme.textPrimary, size: 16),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: crateState.crateNames.isEmpty
                  ? const Center(
                      child: Text('No crates yet',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)))
                  : ListView.builder(
                      itemCount: crateState.crateNames.length,
                      itemBuilder: (ctx, i) {
                        final name = crateState.crateNames[i];
                        final count =
                            crateState.crates[name]?.length ?? 0;
                        final selected = _selectedCrate == name;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCrate = name;
                              _physResult = null;
                            });
                          },
                          child: Container(
                            margin:
                                const EdgeInsets.fromLTRB(12, 2, 12, 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.violet.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: selected
                                      ? AppTheme.violet
                                          .withValues(alpha: 0.5)
                                      : Colors.transparent),
                            ),
                            child: Row(children: [
                              const Icon(Icons.playlist_play_rounded,
                                  color: AppTheme.violet, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis)),
                              Text('$count',
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 11)),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  ref
                                      .read(crateProvider.notifier)
                                      .deleteCrate(name);
                                  if (_selectedCrate == name) {
                                    setState(() => _selectedCrate = null);
                                  }
                                },
                                child: const Icon(Icons.close,
                                    color: AppTheme.textSecondary,
                                    size: 14),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // ── Right: crate content + export ───────────────────────────────────
      Expanded(
        child: _selectedCrate == null
            ? const Center(
                child: Text('Select or create a crate',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(28, 24, 28, 0),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_selectedCrate!,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(color: Colors.white)),
                            Text('${crateLibTracks.length} tracks',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      if (lib.hasLibrary && vibeTracks.isNotEmpty) ...[
                        GestureDetector(
                          onTap: _isMatching
                              ? null
                              : () => _runMatch(vibeTracks, lib.tracks),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _matchResults != null
                                  ? AppTheme.violet.withValues(alpha: 0.15)
                                  : AppTheme.panelRaised,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppTheme.violet.withValues(alpha: 0.4)),
                            ),
                            child: _isMatching
                                ? const SizedBox(
                                    width: 80, height: 16,
                                    child: Center(
                                      child: SizedBox(width: 12, height: 12,
                                        child: CircularProgressIndicator(
                                            color: AppTheme.violet, strokeWidth: 2)),
                                    ))
                                : Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.library_music_rounded,
                                        color: AppTheme.violet, size: 13),
                                    const SizedBox(width: 6),
                                    const Text('Match to Library',
                                        style: TextStyle(
                                            color: AppTheme.violet,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (crateLibTracks.isNotEmpty) ...[
                        _ExportBtn(
                          label: 'Rekordbox',
                          icon: Icons.music_note_rounded,
                          loading: _exportingFormat == 'rekordbox',
                          onTap: () =>
                              _export('rekordbox', crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: 'Serato CSV',
                          icon: Icons.table_chart_rounded,
                          loading: _exportingFormat == 'serato',
                          onTap: () =>
                              _export('serato', crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: 'M3U',
                          icon: Icons.queue_music_rounded,
                          loading: _exportingFormat == 'm3u',
                          onTap: () =>
                              _export('m3u', crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: 'Traktor',
                          icon: Icons.folder_zip_rounded,
                          loading: _exportingFormat == 'traktor',
                          onTap: () =>
                              _export('traktor', crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: '→ VirtualDJ',
                          icon: Icons.queue_play_next_rounded,
                          loading: false,
                          onTap: () => _showVdjExportDialog(
                              _selectedCrate!, crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: '→ Serato',
                          icon: Icons.library_add_rounded,
                          loading: false,
                          onTap: () => _showSeratoExportDialog(
                              _selectedCrate!, crateLibTracks),
                        ),
                        const SizedBox(width: 8),
                        _ExportBtn(
                          label: '🎯 Auto Cue',
                          icon: Icons.flag_rounded,
                          loading: ref.watch(cueProvider).isGenerating,
                          onTap: () => _autoCueCrate(crateLibTracks),
                        ),
                      ],
                    ]),
                  ),
                  if (_lastExportPath != null)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(28, 10, 28, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.lime.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.lime.withValues(alpha: 0.4)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppTheme.lime, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Exported: $_lastExportPath',
                                style: const TextStyle(
                                    color: AppTheme.lime, fontSize: 11),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => Process.run('open', ['-R', _lastExportPath!]),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.cyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.folder_open_rounded, color: AppTheme.cyan, size: 12),
                                SizedBox(width: 4),
                                Text('Show in Finder', style: TextStyle(color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.edge, height: 1),
                  Expanded(
                    child: Row(children: [
                      // Crate tracks
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  28, 16, 28, 8),
                              child: Text('Crate Tracks',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color: AppTheme.textSecondary,
                                          letterSpacing: 1,
                                          fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: crateLibTracks.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'Add tracks from library →',
                                          style: TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 12)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          28, 0, 28, 20),
                                      itemCount: crateLibTracks.length,
                                      itemBuilder: (ctx, i) {
                                        final t = crateLibTracks[i];
                                        return Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 2),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.panel,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border:
                                                Border.all(color: AppTheme.edge),
                                          ),
                                          child: Row(children: [
                                            SizedBox(
                                              width: 20,
                                              child: Text('${i + 1}',
                                                  style: const TextStyle(
                                                      color: AppTheme
                                                          .textSecondary,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                  textAlign: TextAlign.center),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(t.title,
                                                      style: const TextStyle(
                                                          color: AppTheme
                                                              .textPrimary,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                      overflow:
                                                          TextOverflow.ellipsis),
                                                  Text(t.artist,
                                                      style: const TextStyle(
                                                          color: AppTheme
                                                              .textSecondary,
                                                          fontSize: 11),
                                                      overflow:
                                                          TextOverflow.ellipsis),
                                                ],
                                              ),
                                            ),
                                            Text(
                                                '${t.bpm.toStringAsFixed(0)} BPM',
                                                style: const TextStyle(
                                                    color: AppTheme.textSecondary,
                                                    fontSize: 10)),
                                            const SizedBox(width: 8),
                                            Text(t.key,
                                                style: const TextStyle(
                                                    color: AppTheme.cyan,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 8),
                                            InkWell(
                                              onTap: () => ref
                                                  .read(crateProvider.notifier)
                                                  .removeTrackFromCrate(
                                                      _selectedCrate!, t.id),
                                              child: const Icon(
                                                  Icons
                                                      .remove_circle_outline_rounded,
                                                  color: AppTheme.pink,
                                                  size: 14),
                                            ),
                                          ]),
                                        );
                                      },
                                    ),
                            ),

                            // ── Physical Crate Creation panel ────────────
                            if (crateLibTracks.isNotEmpty)
                              _PhysicalCratePanel(
                                crateType: _physCrateType,
                                destDir: _physDestDir,
                                creating: _physCreating,
                                progress: _physProgress,
                                result: _physResult,
                                onTypeChanged: (t) => setState(() {
                                  _physCrateType = t;
                                  _physResult = null;
                                }),
                                onPickDir: _pickDestDir,
                                onCreate: () => _createPhysicalCrate(
                                    _selectedCrate!, crateLibTracks),
                              ),
                          ],
                        ),
                      ),
                      Container(width: 1, color: AppTheme.edge),
                      // Right panel: match results OR library picker
                      Expanded(
                        flex: 1,
                        child: _matchResults != null
                            ? _MatchPanel(
                                results: _matchResults!,
                                exportMatchedOnly: _exportMatchedOnly,
                                expandedId: _expandedMatchId,
                                onToggleExportFilter: (v) =>
                                    setState(() => _exportMatchedOnly = v),
                                onToggleExpand: (id) => setState(() =>
                                    _expandedMatchId =
                                        _expandedMatchId == id ? null : id),
                                onClear: () => setState(() {
                                  _matchResults = null;
                                  _expandedMatchId = null;
                                }),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                    child: Text('Add from Library',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: AppTheme.textSecondary,
                                                letterSpacing: 1,
                                                fontWeight: FontWeight.w700)),
                                  ),
                                  Expanded(
                                    child: lib.tracks.isEmpty
                                        ? const Center(
                                            child: Text('Scan library first',
                                                style: TextStyle(
                                                    color: AppTheme.textSecondary,
                                                    fontSize: 11)))
                                        : ListView.builder(
                                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                            itemCount: lib.tracks.length,
                                            itemBuilder: (ctx, i) {
                                              final t = lib.tracks[i];
                                              final inCrate = crateTrackIds.contains(t.id);
                                              return GestureDetector(
                                                onTap: inCrate
                                                    ? null
                                                    : () => ref
                                                        .read(crateProvider.notifier)
                                                        .addTrackToCrate(_selectedCrate!, t.id),
                                                child: Container(
                                                  margin: const EdgeInsets.only(bottom: 2),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 7),
                                                  decoration: BoxDecoration(
                                                    color: inCrate
                                                        ? AppTheme.violet.withValues(alpha: 0.08)
                                                        : AppTheme.panelRaised,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(t.title,
                                                              style: TextStyle(
                                                                  color: inCrate ? AppTheme.violet : Colors.white,
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.w500),
                                                              overflow: TextOverflow.ellipsis),
                                                          Text(t.artist,
                                                              style: const TextStyle(
                                                                  color: AppTheme.textSecondary,
                                                                  fontSize: 10),
                                                              overflow: TextOverflow.ellipsis),
                                                        ],
                                                      ),
                                                    ),
                                                    Icon(
                                                      inCrate
                                                          ? Icons.check_circle_rounded
                                                          : Icons.add_circle_outline_rounded,
                                                      color: inCrate ? AppTheme.violet : AppTheme.textSecondary,
                                                      size: 12,
                                                    ),
                                                  ]),
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                      ),
                    ]),
                  ),
                ],
              ),
      ),
    ]);
  }

  // ── Auto Cue helpers ──────────────────────────────────────────────────────

  Future<void> _autoCueCrate(List<LibraryTrack> tracks) async {
    if (tracks.isEmpty) return;
    final notifier = ref.read(cueProvider.notifier);
    final results = await notifier.generateForTracks(tracks);
    if (!mounted) return;
    final succeeded = results.values.where((r) => r.isSuccess).length;
    final failed = results.length - succeeded;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        failed == 0
            ? 'Cues generated for $succeeded track${succeeded == 1 ? '' : 's'}'
            : 'Cues generated for $succeeded/${results.length} tracks ($failed failed)',
      ),
      backgroundColor: failed == 0 ? AppTheme.lime : AppTheme.amber,
      duration: const Duration(seconds: 3),
      action: succeeded > 0
          ? SnackBarAction(
              label: 'View',
              textColor: AppTheme.panel,
              onPressed: () => _showCueSummarySheet(results.keys.toList()),
            )
          : null,
    ));
  }

  void _showCueSummarySheet(List<String> trackIds) {
    final lib = ref.read(libraryProvider);
    final tracks = trackIds
        .map((id) => lib.tracks.where((t) => t.id == id).firstOrNull)
        .whereType<LibraryTrack>()
        .toList();
    if (tracks.isEmpty || !mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Generated Cues',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...tracks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CuePreviewPanel(
                    track: t,
                    showWriteToVdjButton: true,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── DJ Software export helpers ────────────────────────────────────────────

  Future<void> _showVdjExportDialog(
      String crateName, List<LibraryTrack> tracks) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DjExportDialog(
        target: DjExportTarget.virtualDj,
        crateName: crateName,
        tracks: tracks,
      ),
    );
  }

  Future<void> _showSeratoExportDialog(
      String crateName, List<LibraryTrack> tracks) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DjExportDialog(
        target: DjExportTarget.serato,
        crateName: crateName,
        tracks: tracks,
      ),
    );
  }

  Future<void> _export(String format, List<LibraryTrack> tracks) async {
    setState(() => _exportingFormat = format);
    final crate = ExportCrate(name: _selectedCrate!, tracks: tracks);
    try {
      String path;
      switch (format) {
        case 'rekordbox':
          path = await _exportService.exportRekordboxXml(crate);
          break;
        case 'serato':
          path = await _exportService.exportSeratoCsv(crate);
          break;
        case 'm3u':
          path = await _exportService.exportM3u(crate);
          break;
        case 'traktor':
          path = await _exportService.exportTraktorNml(crate);
          break;
        default:
          return;
      }
      // Auto-reveal in Finder so user immediately sees where the file went
      ExportService.revealInFinder(path);
      if (mounted) {
        setState(() {
          _exportingFormat = null;
          _lastExportPath = path;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exportingFormat = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: AppTheme.pink,
        ));
      }
    }
  }
}

// ── Physical Crate Panel ──────────────────────────────────────────────────────

class _PhysicalCratePanel extends StatelessWidget {
  final CrateType crateType;
  final String? destDir;
  final bool creating;
  final double progress;
  final PhysicalCrateResult? result;
  final ValueChanged<CrateType> onTypeChanged;
  final VoidCallback onPickDir;
  final VoidCallback onCreate;

  const _PhysicalCratePanel({
    required this.crateType,
    required this.destDir,
    required this.creating,
    required this.progress,
    required this.result,
    required this.onTypeChanged,
    required this.onPickDir,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(children: [
            const Icon(Icons.folder_special_rounded,
                color: AppTheme.violet, size: 14),
            const SizedBox(width: 8),
            const Text('Create Physical Crate',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),

          // Radio buttons
          Row(children: [
            _CrateTypeRadio(
              label: 'Virtual (M3U)',
              value: CrateType.virtualOnly,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(width: 16),
            _CrateTypeRadio(
              label: 'Copy Files',
              value: CrateType.copyFiles,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
            const SizedBox(width: 16),
            _CrateTypeRadio(
              label: 'Alias Links',
              value: CrateType.aliasLinks,
              groupValue: crateType,
              onChanged: onTypeChanged,
            ),
          ]),

          // Destination folder row (hidden for virtual-only)
          if (crateType != CrateType.virtualOnly) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.panel,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.edge),
                  ),
                  child: Text(
                    destDir ?? 'No folder selected…',
                    style: TextStyle(
                        color: destDir != null
                            ? AppTheme.textPrimary
                            : AppTheme.textTertiary,
                        fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onPickDir,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.cyan.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_rounded,
                            color: AppTheme.cyan, size: 13),
                        SizedBox(width: 6),
                        Text('Browse',
                            style: TextStyle(
                                color: AppTheme.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 12),

          // Create button + progress
          Row(children: [
            GestureDetector(
              onTap: creating ? null : onCreate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  gradient: creating
                      ? null
                      : const LinearGradient(
                          colors: [AppTheme.violet, Color(0xFF6D4AE6)]),
                  color: creating ? AppTheme.edge : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: creating
                    ? const SizedBox(
                        width: 60,
                        height: 14,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          ),
                        ),
                      )
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.create_new_folder_rounded,
                            color: Colors.white, size: 13),
                        SizedBox(width: 6),
                        Text('Create Crate',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
            if (creating) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.edge,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.violet),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(progress * 100).toInt()}%',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ]),

          // Result summary
          if (result != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: result!.errors.isEmpty
                    ? AppTheme.lime.withValues(alpha: 0.08)
                    : AppTheme.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: result!.errors.isEmpty
                        ? AppTheme.lime.withValues(alpha: 0.3)
                        : AppTheme.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      result!.errors.isEmpty
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: result!.errors.isEmpty
                          ? AppTheme.lime
                          : AppTheme.amber,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${result!.filesCopied} file(s) created  ·  '
                      '${result!.filesSkipped} skipped'
                      '${result!.errors.isNotEmpty ? "  ·  ${result!.errors.length} error(s)" : ""}',
                      style: TextStyle(
                          color: result!.errors.isEmpty
                              ? AppTheme.lime
                              : AppTheme.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(result!.cratePath,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 10),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CrateTypeRadio extends StatelessWidget {
  final String label;
  final CrateType value;
  final CrateType groupValue;
  final ValueChanged<CrateType> onChanged;
  const _CrateTypeRadio(
      {required this.label,
      required this.value,
      required this.groupValue,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? AppTheme.violet : AppTheme.textTertiary,
                width: 2),
            color: selected
                ? AppTheme.violet.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          child: selected
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.violet,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: selected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }
}

// ── Export button ─────────────────────────────────────────────────────────────

class _ExportBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback onTap;
  const _ExportBtn(
      {required this.label,
      required this.icon,
      required this.loading,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
        ),
        child: loading
            ? const SizedBox(
                width: 40,
                height: 16,
                child: Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        color: AppTheme.cyan, strokeWidth: 2),
                  ),
                ),
              )
            : Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: AppTheme.cyan, size: 13),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.cyan,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }
}
// ──────────────────────────────────────────────────────────────────────────────
// _DjExportDialog — handles VirtualDJ / Serato export with root detection
// ──────────────────────────────────────────────────────────────────────────────

class _DjExportDialog extends ConsumerStatefulWidget {
  const _DjExportDialog({
    required this.target,
    required this.crateName,
    required this.tracks,
  });

  final DjExportTarget target;
  final String crateName;
  final List<LibraryTrack> tracks;

  @override
  ConsumerState<_DjExportDialog> createState() => _DjExportDialogState();
}

class _DjExportDialogState extends ConsumerState<_DjExportDialog> {
  bool _exporting = false;
  DjExportResult? _result;
  String? _error;
  String? _seratoParentCrate;
  final _parentController = TextEditingController();

  @override
  void dispose() {
    _parentController.dispose();
    super.dispose();
  }

  bool get _isVdj => widget.target == DjExportTarget.virtualDj;
  String get _targetLabel => widget.target.label;

  String? get _currentRoot {
    final st = ref.read(djExportProvider);
    return _isVdj ? st.vdjRoot : st.seratoRoot;
  }

  Future<void> _pickRoot() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose $_targetLabel root folder',
    );
    if (result == null || !mounted) return;
    final notifier = ref.read(djExportProvider.notifier);
    if (_isVdj) {
      await notifier.forceSetVirtualDjRoot(result);
    } else {
      await notifier.forceSetSeratoRoot(result);
    }
    if (mounted) setState(() {});
  }

  Future<void> _doExport() async {
    final root = _currentRoot;
    if (root == null) {
      setState(() => _error = 'Please select the $_targetLabel folder first.');
      return;
    }
    setState(() { _exporting = true; _error = null; _result = null; });
    try {
      final notifier = ref.read(djExportProvider.notifier);
      DjExportResult? result;
      if (_isVdj) {
        result = await notifier.exportToVirtualDj(
          crateName: widget.crateName,
          tracks: widget.tracks,
        );
      } else {
        result = await notifier.exportToSerato(
          crateName: widget.crateName,
          tracks: widget.tracks,
          parentCrateName: _seratoParentCrate?.isNotEmpty == true
              ? _seratoParentCrate
              : null,
        );
      }
      if (mounted) setState(() { _exporting = false; _result = result; });
    } catch (e) {
      if (mounted) setState(() { _exporting = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final djState = ref.watch(djExportProvider);
    final root = _isVdj ? djState.vdjRoot : djState.seratoRoot;
    final isValidated = _isVdj
        ? ref.read(djRootDetectionServiceProvider).validateVirtualDjRoot(root ?? '')
        : ref.read(djRootDetectionServiceProvider).validateSeratoRoot(root ?? '');

    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.edge),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Icon(
                  _isVdj ? Icons.queue_play_next_rounded : Icons.library_add_rounded,
                  color: AppTheme.cyan,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Export to $_targetLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary, size: 18),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${widget.tracks.length} tracks  ·  ${widget.crateName}',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 20),
              const Divider(color: AppTheme.edge),
              const SizedBox(height: 16),

              // Root path section
              Text(
                '$_targetLabel Root Folder',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: root != null
                            ? (isValidated
                                ? AppTheme.lime.withValues(alpha: 0.4)
                                : AppTheme.amber.withValues(alpha: 0.4))
                            : AppTheme.edge,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        root != null
                            ? (isValidated
                                ? Icons.check_circle_rounded
                                : Icons.warning_amber_rounded)
                            : Icons.folder_off_rounded,
                        color: root != null
                            ? (isValidated ? AppTheme.lime : AppTheme.amber)
                            : AppTheme.textTertiary,
                        size: 13,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          root ?? 'Not detected — choose folder below',
                          style: TextStyle(
                            color: root != null
                                ? AppTheme.textPrimary
                                : AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _exporting ? null : _pickRoot,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.cyan.withValues(alpha: 0.3)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.folder_open_rounded,
                          color: AppTheme.cyan, size: 13),
                      SizedBox(width: 6),
                      Text('Browse',
                          style: TextStyle(
                              color: AppTheme.cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
              if (!isValidated && root != null) ...[
                const SizedBox(height: 6),
                Text(
                  '⚠ This folder may not be a valid $_targetLabel root '
                  '(expected markers not found). Export will still proceed.',
                  style: const TextStyle(
                      color: AppTheme.amber, fontSize: 10),
                ),
              ],

              // Serato parent crate option
              if (!_isVdj) ...[
                const SizedBox(height: 16),
                Text(
                  'Parent Crate (optional)',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _parentController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'e.g. LocalMusic  (leave empty for top-level)',
                    hintStyle: const TextStyle(
                        color: AppTheme.textTertiary, fontSize: 11),
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppTheme.edge),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: AppTheme.edge),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                  ),
                  onChanged: (v) =>
                      setState(() => _seratoParentCrate = v.trim()),
                ),
                const SizedBox(height: 4),
                Text(
                  'Creates Serato crate: '
                  '${(_seratoParentCrate?.isNotEmpty == true) ? '${_seratoParentCrate}%%' : ''}'
                  '${widget.crateName}.crate',
                  style: const TextStyle(
                      color: AppTheme.textTertiary, fontSize: 10),
                ),
              ],

              // VirtualDJ TIDAL note
              if (_isVdj) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.panelRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.violet.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppTheme.violet, size: 13),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tracks are exported using their local file paths. '
                          'If you use TIDAL inside VirtualDJ, enable it under '
                          'Settings → Audio → TIDAL so VirtualDJ can stream '
                          'any tracks you discover but don\'t own locally.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Error
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.pink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppTheme.pink.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.pink, size: 13),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.pink, fontSize: 11)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // Result summary
              if (_result != null) ...[
                _DjResultBanner(result: _result!),
                const SizedBox(height: 12),
              ],

              // Action row
              if (_result == null)
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppTheme.panelRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.edge),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: (_exporting || root == null) ? null : _doExport,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: (_exporting || root == null)
                            ? null
                            : const LinearGradient(colors: [
                                AppTheme.cyan,
                                Color(0xFF00B4CC)
                              ]),
                        color: (_exporting || root == null)
                            ? AppTheme.edge
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _exporting
                          ? const SizedBox(
                              width: 60,
                              height: 16,
                              child: Center(
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2),
                                ),
                              ),
                            )
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.upload_rounded,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Export to $_targetLabel',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ]),
                    ),
                  ),
                ])
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppTheme.lime.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.lime.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded,
                                color: AppTheme.lime, size: 14),
                            SizedBox(width: 6),
                            Text('Done',
                                style: TextStyle(
                                    color: AppTheme.lime,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── DJ export result banner ───────────────────────────────────────────────────

class _DjResultBanner extends StatelessWidget {
  const _DjResultBanner({required this.result});
  final DjExportResult result;

  @override
  Widget build(BuildContext context) {
    final hasWarnings = result.warnings.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasWarnings
            ? AppTheme.amber.withValues(alpha: 0.08)
            : AppTheme.lime.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasWarnings
              ? AppTheme.amber.withValues(alpha: 0.3)
              : AppTheme.lime.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              hasWarnings
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_rounded,
              color: hasWarnings ? AppTheme.amber : AppTheme.lime,
              size: 14,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Exported to ${result.target.label} — ${result.summary}',
                style: TextStyle(
                  color: hasWarnings ? AppTheme.amber : AppTheme.lime,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Stats row
          Row(children: [
            _StatChip(
                label: '${result.localCount}',
                sublabel: 'local',
                color: AppTheme.cyan),
            if (result.tidalCount > 0) ...[
              const SizedBox(width: 6),
              _StatChip(
                  label: '${result.tidalCount}',
                  sublabel: 'TIDAL',
                  color: AppTheme.violet),
            ],
            if (result.skippedCount > 0) ...[
              const SizedBox(width: 6),
              _StatChip(
                  label: '${result.skippedCount}',
                  sublabel: 'skipped',
                  color: AppTheme.textSecondary),
            ],
          ]),
          const SizedBox(height: 6),
          Text(
            result.outputPath,
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
          if (result.target == DjExportTarget.virtualDj) ...[
            const SizedBox(height: 6),
            const Text(
              '↻ Refresh VirtualDJ (Settings → Database → Refresh) to see the new playlist.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              '↻ Restart Serato DJ Pro or press ⌘R to refresh your crate list.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.warnings.take(3).map((w) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(
                              color: AppTheme.amber, fontSize: 10)),
                      Expanded(
                        child: Text(w,
                            style: const TextStyle(
                                color: AppTheme.amber, fontSize: 10)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.label,
      required this.sublabel,
      required this.color});
  final String label;
  final String sublabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            TextSpan(
                text: ' $sublabel',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// _MatchPanel — shows VibeRadar → local library match results
// ──────────────────────────────────────────────────────────────────────────────

class _MatchPanel extends StatelessWidget {
  final List<TrackMatch> results;
  final bool exportMatchedOnly;
  final String? expandedId;
  final ValueChanged<bool> onToggleExportFilter;
  final ValueChanged<String> onToggleExpand;
  final VoidCallback onClear;

  const _MatchPanel({
    required this.results,
    required this.exportMatchedOnly,
    required this.expandedId,
    required this.onToggleExportFilter,
    required this.onToggleExpand,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final found = results.where((r) => r.isFound).length;
    final fuzzy = results.where((r) => r.isFuzzy).length;
    final missing = results.where((r) => r.isMissing).length;

    final displayed = exportMatchedOnly
        ? results.where((r) => r.isFound || r.isFuzzy).toList()
        : results;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.edge)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Library Match',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textSecondary, size: 14),
                ),
              ]),
              const SizedBox(height: 8),
              // Summary pills
              Row(children: [
                _StatusPill(icon: Icons.check_circle_rounded,
                    color: AppTheme.lime, label: '$found found'),
                const SizedBox(width: 6),
                _StatusPill(icon: Icons.change_circle_rounded,
                    color: AppTheme.amber, label: '$fuzzy fuzzy'),
                const SizedBox(width: 6),
                _StatusPill(icon: Icons.cancel_rounded,
                    color: AppTheme.pink, label: '$missing missing'),
              ]),
              const SizedBox(height: 8),
              // Export matched only toggle
              GestureDetector(
                onTap: () => onToggleExportFilter(!exportMatchedOnly),
                child: Row(children: [
                  Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: exportMatchedOnly
                          ? AppTheme.violet
                          : AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: exportMatchedOnly
                              ? AppTheme.violet
                              : AppTheme.edge),
                    ),
                    child: exportMatchedOnly
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 11)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  const Text('Export matched only',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ]),
              ),
            ],
          ),
        ),
        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            itemCount: displayed.length,
            itemBuilder: (context, i) {
              final r = displayed[i];
              final isExpanded = expandedId == r.vibeTrack.id;
              return _MatchRow(
                result: r,
                isExpanded: isExpanded,
                onTap: () => onToggleExpand(r.vibeTrack.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  final TrackMatch result;
  final bool isExpanded;
  final VoidCallback onTap;

  const _MatchRow({
    required this.result,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = result;
    final (icon, color) = switch (r.status) {
      MatchStatus.found => (Icons.check_circle_rounded, AppTheme.lime),
      MatchStatus.fuzzyMatch => (Icons.change_circle_rounded, AppTheme.amber),
      MatchStatus.duplicateVersions => (Icons.copy_rounded, AppTheme.cyan),
      MatchStatus.uncertain => (Icons.help_outline_rounded, AppTheme.orange),
      MatchStatus.missing => (Icons.cancel_rounded, AppTheme.pink),
    };

    return GestureDetector(
      onTap: r.candidates.isNotEmpty || r.localFilePath != null ? onTap : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isExpanded
              ? AppTheme.panelRaised
              : AppTheme.panel.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: isExpanded
                  ? color.withValues(alpha: 0.3)
                  : AppTheme.edge.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.vibeTrack.title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        r.vibeTrack.artist,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (r.matchScore > 0)
                  Text(
                    '${(r.matchScore * 100).toInt()}%',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                if (r.candidates.isNotEmpty || r.localFilePath != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textTertiary,
                    size: 14,
                  ),
                ],
              ]),
            ),
            // Expanded: show file candidates
            if (isExpanded) ...[
              const Divider(color: AppTheme.edge, height: 1, indent: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final path in r.candidates.isNotEmpty
                        ? r.candidates
                        : [if (r.localFilePath != null) r.localFilePath!])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(children: [
                          const Icon(Icons.insert_drive_file_rounded,
                              color: AppTheme.textTertiary, size: 11),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              path.split('/').last,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 9,
                                  fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusPill(
      {required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
