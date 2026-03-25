import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../providers/library_provider.dart';
import '../../../services/export_service.dart';

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

  static final _dummyTrack = LibraryTrack(
    id: 'dummy', filePath: '', fileName: '', title: '', artist: '',
    album: '', genre: '', bpm: 0, key: '', durationSeconds: 0,
    fileSizeBytes: 0, fileExtension: '', md5Hash: '', bitrate: 0, sampleRate: 0,
  );

  @override
  void dispose() {
    _crateNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final crateState = ref.watch(crateProvider);
    final lib = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    final crateTrackIds =
        _selectedCrate != null ? crateState.crates[_selectedCrate] ?? [] : <String>[];
    final crateLibTracks = crateTrackIds
        .map((id) => lib.tracks.firstWhere(
              (t) => t.id == id,
              orElse: () => _dummyTrack,
            ))
        .where((t) => t.id != 'dummy')
        .toList();

    return Row(children: [
      // Left: crate list panel
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
                            color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'New crate name…',
                          hintStyle: const TextStyle(
                              color: Color(0xFF9099B8), fontSize: 12),
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
                          ref.read(crateProvider.notifier).createCrate(name);
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
                            color: Colors.white, size: 16),
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
                              color: Color(0xFF9099B8), fontSize: 12)))
                  : ListView.builder(
                      itemCount: crateState.crateNames.length,
                      itemBuilder: (ctx, i) {
                        final name = crateState.crateNames[i];
                        final count =
                            crateState.crates[name]?.length ?? 0;
                        final selected = _selectedCrate == name;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedCrate = name),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(
                                12, 2, 12, 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.violet.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: selected
                                      ? AppTheme.violet.withValues(alpha: 0.5)
                                      : Colors.transparent),
                            ),
                            child: Row(children: [
                              const Icon(Icons.playlist_play_rounded,
                                  color: AppTheme.violet, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis)),
                              Text('$count',
                                  style: const TextStyle(
                                      color: Color(0xFF9099B8),
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
                                    color: Color(0xFF9099B8), size: 14),
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

      // Right: crate content + export
      Expanded(
        child: _selectedCrate == null
            ? const Center(
                child: Text('Select or create a crate',
                    style: TextStyle(
                        color: Color(0xFF9099B8), fontSize: 14)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
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
                                    color: Color(0xFF9099B8),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
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
                      padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
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
                              padding:
                                  const EdgeInsets.fromLTRB(28, 16, 28, 8),
                              child: Text('Crate Tracks',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color: const Color(0xFF9099B8),
                                          letterSpacing: 1,
                                          fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: crateLibTracks.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'Add tracks from library →',
                                          style: TextStyle(
                                              color: Color(0xFF9099B8),
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
                                            border: Border.all(
                                                color: AppTheme.edge),
                                          ),
                                          child: Row(children: [
                                            SizedBox(
                                              width: 20,
                                              child: Text('${i + 1}',
                                                  style: const TextStyle(
                                                      color:
                                                          Color(0xFF9099B8),
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                  textAlign:
                                                      TextAlign.center),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(t.title,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500),
                                                      overflow:
                                                          TextOverflow.ellipsis),
                                                  Text(t.artist,
                                                      style: const TextStyle(
                                                          color:
                                                              Color(0xFF9099B8),
                                                          fontSize: 11),
                                                      overflow:
                                                          TextOverflow.ellipsis),
                                                ],
                                              ),
                                            ),
                                            Text(
                                                '${t.bpm.toStringAsFixed(0)} BPM',
                                                style: const TextStyle(
                                                    color: Color(0xFF9099B8),
                                                    fontSize: 10)),
                                            const SizedBox(width: 8),
                                            Text(t.key,
                                                style: const TextStyle(
                                                    color: AppTheme.cyan,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600)),
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
                          ],
                        ),
                      ),
                      Container(width: 1, color: AppTheme.edge),
                      // Library picker
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 16, 16, 8),
                              child: Text('Add from Library',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(
                                          color: const Color(0xFF9099B8),
                                          letterSpacing: 1,
                                          fontWeight: FontWeight.w700)),
                            ),
                            Expanded(
                              child: lib.tracks.isEmpty
                                  ? const Center(
                                      child: Text('Scan library first',
                                          style: TextStyle(
                                              color: Color(0xFF9099B8),
                                              fontSize: 11)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 20),
                                      itemCount: lib.tracks.length,
                                      itemBuilder: (ctx, i) {
                                        final t = lib.tracks[i];
                                        final inCrate =
                                            crateTrackIds.contains(t.id);
                                        return GestureDetector(
                                          onTap: inCrate
                                              ? null
                                              : () => ref
                                                  .read(crateProvider.notifier)
                                                  .addTrackToCrate(
                                                      _selectedCrate!, t.id),
                                          child: Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 2),
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 7),
                                            decoration: BoxDecoration(
                                              color: inCrate
                                                  ? AppTheme.violet
                                                      .withValues(alpha: 0.08)
                                                  : AppTheme.panelRaised,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Row(children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(t.title,
                                                        style: TextStyle(
                                                            color: inCrate
                                                                ? AppTheme.violet
                                                                : Colors.white,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w500),
                                                        overflow:
                                                            TextOverflow.ellipsis),
                                                    Text(t.artist,
                                                        style: const TextStyle(
                                                            color:
                                                                Color(0xFF9099B8),
                                                            fontSize: 10),
                                                        overflow:
                                                            TextOverflow.ellipsis),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                inCrate
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                        .add_circle_outline_rounded,
                                                color: inCrate
                                                    ? AppTheme.violet
                                                    : const Color(0xFF9099B8),
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

  Future<void> _export(
      String format, List<LibraryTrack> tracks) async {
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppTheme.cyan.withValues(alpha: 0.3)),
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
