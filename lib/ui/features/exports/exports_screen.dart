import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/export_service.dart';
import '../../../services/local_match_service.dart';

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

  @override
  void dispose() {
    _crateNameController.dispose();
    super.dispose();
  }

  /// Resolves a crate track ID to a [LibraryTrack].
  ///
  /// Resolution order:
  /// 1. Direct ID match against local library (works for tracks added from the
  ///    library panel — IDs are now stable md5 hashes of file content).
  /// 2. Online Track ID match — look up the VibeRadar [Track] by ID, then
  ///    fuzzy-match its title + artist against the local library.
  /// 3. Encoded ID format `spotify:Title:Artist` or `apple:Title:Artist` from
  ///    the search screen — extract title/artist and fuzzy-match.
  LibraryTrack? _resolveTrackId(
    String id,
    List<LibraryTrack> library,
    List<Track> onlineTracks,
  ) {
    // 1. Direct local library ID match.
    final direct = library.where((t) => t.id == id).firstOrNull;
    if (direct != null) return direct;

    // 2. Online Track ID → title/artist → library match.
    final onlineTrack = onlineTracks.where((t) => t.id == id).firstOrNull;
    if (onlineTrack != null) {
      return _matchByTitleArtist(onlineTrack.title, onlineTrack.artist, library);
    }

    // 3. Encoded search-screen ID `spotify:Title:Artist` or `apple:Title:Artist`.
    if (id.startsWith('spotify:') || id.startsWith('apple:')) {
      final parts = id.split(':');
      if (parts.length >= 3) {
        return _matchByTitleArtist(parts[1], parts[2], library);
      }
    }

    return null;
  }

  LibraryTrack? _matchByTitleArtist(
    String title,
    String artist,
    List<LibraryTrack> library,
  ) {
    final normTitle = _normalise(title);
    final normArtist = _normalise(artist);

    // Exact title + artist.
    for (final t in library) {
      final libTitle = _normalise(t.title.isNotEmpty ? t.title : t.fileName);
      final libArtist = _normalise(t.artist);
      if (libTitle == normTitle &&
          (normArtist.isEmpty || libArtist.isEmpty || libArtist.contains(normArtist) || normArtist.contains(libArtist))) {
        return t;
      }
    }
    // Title-only fallback (artist may be missing in metadata).
    for (final t in library) {
      final libTitle = _normalise(t.title.isNotEmpty ? t.title : t.fileName);
      if (libTitle == normTitle) return t;
    }
    return null;
  }

  String _normalise(String s) {
    var out = s.toLowerCase();
    out = out.replaceAll(RegExp(r'\(feat[^)]*\)', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'\(ft[^)]*\)', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'\(remix[^)]*\)', caseSensitive: false), '');
    out = out.replaceAll(RegExp(r'\[.*?\]'), '');
    out = out.replaceAll(RegExp(r'\.(mp3|flac|wav|aac|m4a|ogg|aiff)$'), '');
    out = out.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    return out.trim().replaceAll(RegExp(r'\s+'), ' ');
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
    final crateLibTracks = crateTrackIds
        .map((id) => _resolveTrackId(id, lib.tracks, vibeTracks))
        .whereType<LibraryTrack>()
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
