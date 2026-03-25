import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../providers/library_provider.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _searchQuery = '';
  String _filterGenre = 'All';

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    final genres = <String>{'All', ...lib.tracks.map((t) => t.genre)}.toList();
    final displayTracks = lib.tracks.where((t) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q);
      final matchGenre = _filterGenre == 'All' || t.genre == _filterGenre;
      return matchSearch && matchGenre;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Library',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    lib.hasLibrary
                        ? '${lib.tracks.length} tracks  •  '
                            '${lib.duplicateCount} duplicates found'
                        : 'Scan your local music folder to index tracks',
                    style:
                        const TextStyle(color: Color(0xFF9099B8), fontSize: 13),
                  ),
                ],
              ),
            ),
            if (lib.isScanning)
              _ScanProgressChip(
                  scanned: lib.scanProgress, total: lib.scanTotal)
            else
              ElevatedButton.icon(
                onPressed: _pickAndScan,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: Text(lib.hasLibrary ? 'Rescan Folder' : 'Select Folder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.violet,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ]),
        ),
        if (!lib.hasLibrary && !lib.isScanning)
          const Expanded(child: _EmptyState())
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: Row(children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search tracks, artists…',
                    hintStyle: const TextStyle(color: Color(0xFF9099B8)),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0xFF9099B8), size: 18),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _filterGenre,
                dropdownColor: AppTheme.panel,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                underline: const SizedBox(),
                items: genres
                    .map((g) =>
                        DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _filterGenre = v ?? 'All'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: lib.isScanning
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: AppTheme.cyan),
                        const SizedBox(height: 16),
                        Text(
                          'Scanning… ${lib.scanProgress} / ${lib.scanTotal}',
                          style: const TextStyle(color: Color(0xFF9099B8)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    itemCount: displayTracks.length,
                    itemBuilder: (ctx, i) => _TrackRow(
                      track: displayTracks[i],
                      onDelete: () => ref
                          .read(libraryProvider.notifier)
                          .removeTrack(displayTracks[i].id),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickAndScan() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select your music folder',
    );
    if (result != null && mounted) {
      ref.read(libraryProvider.notifier).scanDirectory(result);
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: AppTheme.violet.withOpacity(0.3)),
          ),
          child: const Icon(Icons.folder_rounded,
              size: 48, color: AppTheme.violet),
        ),
        const SizedBox(height: 24),
        const Text('No library scanned yet',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18)),
        const SizedBox(height: 8),
        const Text('Pick a folder with your music files to start.',
            style:
                TextStyle(color: Color(0xFF9099B8), fontSize: 13)),
        const SizedBox(height: 20),
        const Wrap(spacing: 16, children: [
          _InfoChip(
              icon: Icons.audio_file_rounded,
              label: 'MP3, FLAC, WAV, AAC, M4A'),
          _InfoChip(
              icon: Icons.fingerprint_rounded,
              label: 'BPM, Key, Duration'),
          _InfoChip(
              icon: Icons.content_copy_rounded,
              label: 'Auto duplicate detection'),
        ]),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppTheme.cyan, size: 14),
        const SizedBox(width: 8),
        Text(label,
            style:
                const TextStyle(color: Color(0xFF9099B8), fontSize: 11)),
      ]),
    );
  }
}

class _ScanProgressChip extends StatelessWidget {
  final int scanned;
  final int total;
  const _ScanProgressChip(
      {required this.scanned, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? scanned / total : 0.0;
    return Row(children: [
      SizedBox(
        width: 120,
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: AppTheme.edge,
          valueColor:
              const AlwaysStoppedAnimation<Color>(AppTheme.cyan),
        ),
      ),
      const SizedBox(width: 10),
      Text('$scanned / $total',
          style: const TextStyle(
              color: Color(0xFF9099B8), fontSize: 12)),
    ]);
  }
}

class _TrackRow extends StatelessWidget {
  final LibraryTrack track;
  final VoidCallback onDelete;
  const _TrackRow({required this.track, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.2),
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
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
              Text(track.artist,
                  style: const TextStyle(
                      color: Color(0xFF9099B8), fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        _MetaChip(label: '${track.bpm.toStringAsFixed(0)} BPM'),
        const SizedBox(width: 8),
        _MetaChip(label: track.key, color: AppTheme.cyan),
        const SizedBox(width: 8),
        _MetaChip(label: track.genre),
        const SizedBox(width: 8),
        Text(track.durationFormatted,
            style: const TextStyle(
                color: Color(0xFF9099B8), fontSize: 11)),
        const SizedBox(width: 8),
        Text(track.fileSizeFormatted,
            style: const TextStyle(
                color: Color(0xFF9099B8), fontSize: 11)),
        const SizedBox(width: 8),
        InkWell(
          onTap: onDelete,
          child: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFF9099B8), size: 16),
        ),
      ]),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip(
      {required this.label,
      this.color = const Color(0xFF9099B8)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    );
  }
}
