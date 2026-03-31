import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/theme/app_theme.dart';
import '../../../models/library_track.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/dj_player_provider.dart';
import '../../../providers/cue_provider.dart';
import '../../../providers/smart_crate_provider.dart';
import '../../../services/smart_crate_generator_service.dart';
import '../../../models/cue_generation_result.dart';
import '../../../models/hot_cue.dart';
import '../../../services/platform_search_service.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _filterGenre = 'All';
  String _sortBy = 'title';
  bool _sortAsc = true;

  // Recommendation state
  List<PlatformTrackResult> _recommendations = [];
  bool _loadingRecs = false;

  // Crate creation state
  String _crateName = '';
  bool _creatingCrate = false;
  String? _crateResultPath;
  int _crateCopied = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);

    if (!lib.hasLibrary && !lib.isScanning && !lib.isLoading) {
      return _buildEmptyOrScanState(lib);
    }

    if (lib.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.cyan));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(lib),
        _buildTabBar(),
        Expanded(child: _buildTabContent(lib)),
      ],
    );
  }

  Widget _buildEmptyOrScanState(LibraryState lib) {
    if (lib.error != null) return _ErrorState(message: lib.error!);
    if (lib.scannedPath != null) return _ZeroFilesState(path: lib.scannedPath!);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
          child: Row(children: [
            Text('My Library',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _pickAndScan,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Select Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.violet,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        ),
        const Expanded(child: _EmptyState()),
      ],
    );
  }

  Widget _buildHeader(LibraryState lib) {
    final genres = lib.tracks.map((t) => t.genre).toSet().length;
    final artists = lib.tracks.map((t) => t.artist).toSet().length;
    final totalSize = lib.tracks.fold<int>(0, (s, t) => s + t.fileSizeBytes);
    final sizeGB = (totalSize / (1024 * 1024 * 1024)).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.violet.withValues(alpha: 0.12), AppTheme.panel],
        ),
        border: Border.all(color: AppTheme.violet.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.pink]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.library_music_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Library', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Wrap(spacing: 16, children: [
                  _StatBadge(Icons.music_note_rounded, '${lib.tracks.length} tracks', AppTheme.cyan),
                  _StatBadge(Icons.people_rounded, '$artists artists', AppTheme.violet),
                  _StatBadge(Icons.album_rounded, '$genres genres', AppTheme.pink),
                  _StatBadge(Icons.storage_rounded, '$sizeGB GB', AppTheme.amber),
                  if (lib.duplicateCount > 0)
                    _StatBadge(Icons.copy_rounded, '${lib.duplicateCount} dupes', AppTheme.orange),
                ]),
              ],
            ),
          ),
          if (lib.isScanning)
            _ScanProgressChip(scanned: lib.scanProgress, total: lib.scanTotal, label: lib.scanLabel)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _GenerateAllCuesButton(tracks: lib.tracks),
                ElevatedButton.icon(
                  onPressed: () => ref.read(libraryProvider.notifier).fetchAllArtwork(),
                  icon: const Icon(Icons.image_rounded, size: 16),
                  label: const Text('Fetch Artwork'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyan.withValues(alpha: 0.2),
                    foregroundColor: AppTheme.cyan,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickAndScan,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Rescan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.violet,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppTheme.cyan,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.cyan,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(text: 'All Tracks'),
          Tab(text: 'Recommendations'),
          Tab(text: 'Create Crate'),
          Tab(text: 'Duplicates'),
          Tab(text: 'Stats'),
          Tab(text: 'AI Crates'),
        ],
      ),
    );
  }

  Widget _buildTabContent(LibraryState lib) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildAllTracksTab(lib),
        _buildRecommendationsTab(lib),
        _buildCreateCrateTab(lib),
        _buildDuplicatesTab(lib),
        _buildStatsTab(lib),
        _buildAiCratesTab(lib),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1: ALL TRACKS — GRID CARDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAllTracksTab(LibraryState lib) {
    final genres = ['All', ...lib.tracks.map((t) => t.genre).toSet().toList()..sort()];

    var displayTracks = lib.tracks.where((t) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q);
      final matchGenre = _filterGenre == 'All' || t.genre == _filterGenre;
      return matchSearch && matchGenre;
    }).toList();

    displayTracks.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'artist': cmp = a.artist.compareTo(b.artist);
        case 'bpm': cmp = a.bpm.compareTo(b.bpm);
        case 'genre': cmp = a.genre.compareTo(b.genre);
        case 'year': cmp = (a.year ?? 0).compareTo(b.year ?? 0);
        case 'size': cmp = a.fileSizeBytes.compareTo(b.fileSizeBytes);
        default: cmp = a.title.compareTo(b.title);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return Column(
      children: [
        // Filters
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search tracks, artists, albums…',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary, size: 18),
                  filled: true, fillColor: AppTheme.panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FilterDrop(value: _filterGenre, items: genres, onChanged: (v) => setState(() => _filterGenre = v ?? 'All')),
            const SizedBox(width: 8),
            _SortButton(sortBy: _sortBy, asc: _sortAsc, onSort: (col) {
              setState(() {
                if (_sortBy == col) { _sortAsc = !_sortAsc; } else { _sortBy = col; _sortAsc = true; }
              });
            }),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 4),
          child: Text('${displayTracks.length} tracks', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
        ),
        // Grid of track cards
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: displayTracks.length,
            itemBuilder: (ctx, i) => _LibraryTrackCard(track: displayTracks[i]),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2: RECOMMENDATIONS — GRID CARDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildRecommendationsTab(LibraryState lib) {
    final genreCounts = <String, int>{};
    final artistCounts = <String, int>{};
    for (final t in lib.tracks) {
      if (t.genre.isNotEmpty && t.genre != 'Unknown') genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      if (t.artist.isNotEmpty && t.artist != 'Unknown Artist') artistCounts[t.artist] = (artistCounts[t.artist] ?? 0) + 1;
    }
    final topGenres = (genreCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => e.key).toList();
    final topArtists = (artistCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).map((e) => e.key).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: AppTheme.amber, size: 20),
            const SizedBox(width: 8),
            const Text('Recommendations', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
            const Spacer(),
            if (_loadingRecs)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyan))
            else
              ElevatedButton.icon(
                onPressed: () => _generateRecommendations(topGenres, topArtists),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('Find Recommendations'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cyan.withValues(alpha: 0.2),
                  foregroundColor: AppTheme.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 28, 8),
          child: Text(
            lib.tracks.isEmpty
                ? 'Scan your library first to get personalized recommendations.'
                : 'Based on: ${topGenres.join(", ")} · ${topArtists.take(3).join(", ")}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        if (_recommendations.isEmpty && !_loadingRecs)
          const Expanded(
            child: Center(
              child: Text('Tap "Find Recommendations" to discover music.',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 13)),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.78,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _recommendations.length,
              itemBuilder: (ctx, i) => _RecommendationCard(result: _recommendations[i]),
            ),
          ),
      ],
    );
  }

  Future<void> _generateRecommendations(List<String> genres, List<String> artists) async {
    setState(() { _loadingRecs = true; _recommendations = []; });
    final service = PlatformSearchService();
    final results = <PlatformTrackResult>[];
    try {
      for (final genre in genres.take(3)) {
        final r = await service.searchByGenre(genre, limit: 15);
        results.addAll(r);
      }
      for (final artist in artists.take(3)) {
        final r = await service.searchByArtist(artist, limit: 10);
        results.addAll(r);
      }
      final seen = <String>{};
      results.retainWhere((r) => seen.add('${r.title.toLowerCase()}::${r.artist.toLowerCase()}'));
    } catch (_) {}
    if (mounted) setState(() { _recommendations = results; _loadingRecs = false; });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3: CREATE CRATE — GRID CARDS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildCreateCrateTab(LibraryState lib) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
          child: Row(children: [
            const Icon(Icons.create_new_folder_rounded, color: AppTheme.violet, size: 20),
            const SizedBox(width: 8),
            const Text('Create Crate from Library', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          child: const Text('Name the crate, then copy all your tracks into a folder.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _crateName = v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Crate name (e.g. "Friday Warm-Up")',
                  hintStyle: const TextStyle(color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.label_rounded, color: AppTheme.textSecondary, size: 18),
                  filled: true, fillColor: AppTheme.panel,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _crateName.trim().isEmpty || _creatingCrate ? null : () => _createLibraryCrate(lib),
              icon: _creatingCrate
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.folder_copy_rounded, size: 16),
              label: Text(_creatingCrate ? 'Creating…' : 'Create Crate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.violet,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
        ),
        if (_crateResultPath != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.lime.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.lime.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.lime, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Crate created: $_crateCopied files copied', style: const TextStyle(color: AppTheme.lime, fontWeight: FontWeight.w600, fontSize: 12)),
                  Text(_crateResultPath!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                TextButton(
                  onPressed: () => Process.run('open', [_crateResultPath!]),
                  child: const Text('Show in Finder', style: TextStyle(color: AppTheme.cyan, fontSize: 11)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: lib.tracks.length,
            itemBuilder: (ctx, i) => _LibraryTrackCard(track: lib.tracks[i]),
          ),
        ),
      ],
    );
  }

  Future<void> _createLibraryCrate(LibraryState lib) async {
    final destDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose destination for crate');
    if (destDir == null || !mounted) return;
    setState(() { _creatingCrate = true; _crateResultPath = null; });

    final safeName = _crateName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '_');
    final crateDir = Directory(p.join(destDir, safeName));
    await crateDir.create(recursive: true);

    int copied = 0;
    for (final t in lib.tracks) {
      final src = File(t.filePath);
      if (!src.existsSync()) continue;
      try {
        await src.copy(p.join(crateDir.path, p.basename(t.filePath)));
        copied++;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _creatingCrate = false;
        _crateResultPath = crateDir.path;
        _crateCopied = copied;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4: DUPLICATES
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDuplicatesTab(LibraryState lib) {
    if (lib.duplicateGroups.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline_rounded, color: AppTheme.lime, size: 48),
          SizedBox(height: 12),
          Text('No duplicates found', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
          SizedBox(height: 4),
          Text('Your library is clean!', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      itemCount: lib.duplicateGroups.length,
      itemBuilder: (ctx, i) {
        final group = lib.duplicateGroups[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.panel, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.edge),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.copy_rounded, size: 14, color: group.confidence >= 0.9 ? AppTheme.pink : AppTheme.amber),
              const SizedBox(width: 6),
              Flexible(
                child: Text(group.reasonLabel, style: TextStyle(
                  color: group.confidence >= 0.9 ? AppTheme.pink : AppTheme.amber,
                  fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('${group.tracks.length} files · ${(group.confidence * 100).toStringAsFixed(0)}% confidence',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
              const Spacer(),
              if (group.recommended != null)
                Flexible(
                  child: Text('Keep: ${group.recommended!.fileName}',
                      style: const TextStyle(color: AppTheme.lime, fontSize: 10, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ]),
            const SizedBox(height: 8),
            ...group.tracks.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                if (t.id == group.recommended?.id)
                  const Icon(Icons.star_rounded, color: AppTheme.lime, size: 14)
                else
                  const Icon(Icons.file_copy_outlined, color: AppTheme.textTertiary, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(t.fileName, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11), overflow: TextOverflow.ellipsis)),
                Text('${t.bitrate} kbps', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                const SizedBox(width: 8),
                Text(t.fileSizeFormatted, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
              ]),
            )),
          ]),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 5: STATS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsTab(LibraryState lib) {
    final genreCounts = <String, int>{};
    final artistCounts = <String, int>{};
    final bpmBuckets = <String, int>{};
    final yearBuckets = <String, int>{};
    final formatCounts = <String, int>{};

    for (final t in lib.tracks) {
      genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      artistCounts[t.artist] = (artistCounts[t.artist] ?? 0) + 1;
      if (t.bpm > 0) {
        final bucket = '${(t.bpm ~/ 10) * 10}–${(t.bpm ~/ 10) * 10 + 9}';
        bpmBuckets[bucket] = (bpmBuckets[bucket] ?? 0) + 1;
      }
      if (t.year != null && t.year! > 0) {
        final decade = '${(t.year! ~/ 10) * 10}s';
        yearBuckets[decade] = (yearBuckets[decade] ?? 0) + 1;
      }
      formatCounts[t.fileExtension] = (formatCounts[t.fileExtension] ?? 0) + 1;
    }

    final topGenres = genreCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topArtists = artistCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      children: [
        _StatsSection(title: 'Top Genres', items: topGenres.take(10).toList(), color: AppTheme.violet),
        const SizedBox(height: 16),
        _StatsSection(title: 'Top Artists', items: topArtists.take(10).toList(), color: AppTheme.cyan),
        const SizedBox(height: 16),
        _StatsSection(title: 'BPM Distribution', items: (bpmBuckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).toList(), color: AppTheme.amber),
        const SizedBox(height: 16),
        _StatsSection(title: 'By Decade', items: (yearBuckets.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).toList(), color: AppTheme.pink),
        const SizedBox(height: 16),
        _StatsSection(title: 'File Formats', items: formatCounts.entries.toList(), color: AppTheme.lime),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 6: AI SMART CRATES
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAiCratesTab(LibraryState lib) {
    final sc = ref.watch(smartCrateProvider);
    final scNotifier = ref.read(smartCrateProvider.notifier);

    // Gather unique genres from library
    final libraryGenres = lib.tracks
        .map((t) => t.genre)
        .where((g) => g.isNotEmpty && g != 'Unknown')
        .toSet()
        .toList()
      ..sort();

    // BPM range from library
    final bpms = lib.tracks.where((t) => t.bpm > 0).map((t) => t.bpm);
    final libMinBpm = bpms.isEmpty ? 60.0 : bpms.reduce((a, b) => a < b ? a : b);
    final libMaxBpm = bpms.isEmpty ? 200.0 : bpms.reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: AppTheme.violet, size: 20),
          const SizedBox(width: 8),
          const Text('AI Smart Crate Generator',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 16)),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Let AI analyze your library and create perfectly curated crates based on BPM, key, genre, and energy flow.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // ── Preferences Panel ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.edge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Genre chips
              const Text('Genres', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: libraryGenres.take(20).map((genre) {
                  final selected = sc.preferences.genres.contains(genre);
                  return FilterChip(
                    label: Text(genre, style: TextStyle(
                      color: selected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 11,
                    )),
                    selected: selected,
                    onSelected: (_) => scNotifier.toggleGenre(genre),
                    selectedColor: AppTheme.violet,
                    backgroundColor: AppTheme.surface,
                    side: BorderSide(color: selected ? AppTheme.violet : AppTheme.edge),
                    checkmarkColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              if (sc.preferences.genres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${sc.preferences.genres.length} selected',
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                ),

              const SizedBox(height: 16),

              // BPM range slider
              Row(children: [
                const Text('BPM Range', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  '${(sc.preferences.minBpm ?? libMinBpm).toStringAsFixed(0)} - ${(sc.preferences.maxBpm ?? libMaxBpm).toStringAsFixed(0)}',
                  style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ]),
              const SizedBox(height: 4),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppTheme.violet,
                  inactiveTrackColor: AppTheme.edge,
                  thumbColor: AppTheme.violet,
                  overlayColor: AppTheme.violet.withValues(alpha: 0.15),
                  trackHeight: 3,
                ),
                child: RangeSlider(
                  values: RangeValues(
                    (sc.preferences.minBpm ?? libMinBpm).clamp(libMinBpm, libMaxBpm),
                    (sc.preferences.maxBpm ?? libMaxBpm).clamp(libMinBpm, libMaxBpm),
                  ),
                  min: libMinBpm.floorToDouble(),
                  max: libMaxBpm.ceilToDouble(),
                  divisions: ((libMaxBpm - libMinBpm) / 5).round().clamp(1, 100),
                  onChanged: (range) => scNotifier.setBpmRange(range.start, range.end),
                ),
              ),

              const SizedBox(height: 12),

              // Mood + Energy dropdowns
              Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mood', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _AiCrateDropdown(
                      value: sc.preferences.mood,
                      items: const ['Chill', 'Warm-Up', 'Peak Hour', 'Cool Down', 'Eclectic'],
                      onChanged: scNotifier.setMood,
                    ),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Energy', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _AiCrateDropdown(
                      value: sc.preferences.energyLevel,
                      items: const ['Low', 'Medium', 'High', 'Building'],
                      onChanged: scNotifier.setEnergyLevel,
                    ),
                  ],
                )),
              ]),

              const SizedBox(height: 12),

              // Crate count slider
              Row(children: [
                const Text('Number of Crates', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${sc.preferences.crateCount}',
                    style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppTheme.violet,
                  inactiveTrackColor: AppTheme.edge,
                  thumbColor: AppTheme.violet,
                  overlayColor: AppTheme.violet.withValues(alpha: 0.15),
                  trackHeight: 3,
                ),
                child: Slider(
                  value: sc.preferences.crateCount.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) => scNotifier.setCrateCount(v.round()),
                ),
              ),

              const SizedBox(height: 8),

              // Custom instructions
              const Text('Custom Instructions (optional)',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                onChanged: (v) => scNotifier.setCustomPrompt(v.isEmpty ? null : v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'e.g. "Focus on tracks good for wedding receptions" or "Group by Camelot key zones"',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  filled: true,
                  fillColor: AppTheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.edge)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.violet)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 16),

              // Generate button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: sc.isGenerating
                      ? null
                      : const LinearGradient(colors: [AppTheme.violet, Color(0xFF6C4CFF)]),
                  color: sc.isGenerating ? AppTheme.violet.withValues(alpha: 0.3) : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ElevatedButton.icon(
                  onPressed: sc.isGenerating ? null : () => scNotifier.generate(),
                  icon: sc.isGenerating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(sc.isGenerating ? 'Generating...' : 'Generate Smart Crates'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Progress ────────────────────────────────────────────────────
        if (sc.isGenerating && sc.progress.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.violet.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.violet),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(sc.progress,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
            ]),
          ),
        ],

        // ── Error ───────────────────────────────────────────────────────
        if (sc.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.pink.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: AppTheme.pink, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(sc.error!,
                  style: const TextStyle(color: AppTheme.pink, fontSize: 12))),
            ]),
          ),
        ],

        // ── Generated Crate Results ─────────────────────────────────────
        if (sc.crates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Generated ${sc.crates.length} Crates',
              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 12),
          ...sc.crates.asMap().entries.map((entry) => _AiCrateCard(
            index: entry.key,
            crate: entry.value,
          )),
        ],
      ],
    );
  }

  Future<void> _pickAndScan() async {
    final result = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select your music folder');
    if (result != null && mounted) {
      ref.read(libraryProvider.notifier).scanDirectory(result);
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GRID CARD: Library Track (matches trending/search card style)
// ══════════════════════════════════════════════════════════════════════════════

class _LibraryTrackCard extends ConsumerStatefulWidget {
  final LibraryTrack track;
  const _LibraryTrackCard({required this.track});
  @override
  ConsumerState<_LibraryTrackCard> createState() => _LibraryTrackCardState();
}

class _LibraryTrackCardState extends ConsumerState<_LibraryTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final dj = ref.watch(djPlayerProvider);
    final isOnDeckA = dj.deckA.track?.id == t.id;
    final isOnDeckB = dj.deckB.track?.id == t.id;
    final isPlaying = isOnDeckA || isOnDeckB;
    return GestureDetector(
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition, t),
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPlaying
                ? AppTheme.cyan.withValues(alpha: 0.7)
                : AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
            width: isPlaying ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork area
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    child: SizedBox.expand(
                      child: t.artworkUrl != null && t.artworkUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: t.artworkUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _libArtPlaceholder(),
                              placeholder: (_, __) => _libArtPlaceholder(),
                            )
                          : _libArtPlaceholder(),
                    ),
                  ),
                  // Format badge (top-left)
                  Positioned(
                    top: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.violet.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        t.fileExtension.replaceFirst('.', '').toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  // BPM badge (top-right)
                  if (t.bpm > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.amber.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          '${t.bpm.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  // Hover play overlay
                  if (_hovered)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          ref.read(djPlayerProvider.notifier).smartLoad(
                            widget.track,
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.cyan, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          )),
                        ),
                      ),
                    ),
                  // Deck badge (A = cyan, B = violet)
                  if ((isOnDeckA || isOnDeckB) && !_hovered)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnDeckA
                              ? AppTheme.cyan.withValues(alpha: 0.85)
                              : AppTheme.violet.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOnDeckA ? 'A' : 'B',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info section
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (t.key.isNotEmpty && t.key != '--')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                          child: Text(t.key, style: const TextStyle(color: AppTheme.cyan, fontSize: 8, fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 8), overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  void _showContextMenu(BuildContext context, Offset position, LibraryTrack track) {
    final cueState = ref.read(cueProvider);
    final hasCues = cueState.results.containsKey(track.id);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        const PopupMenuItem(value: 'play', child: Row(children: [
          Icon(Icons.play_arrow_rounded, size: 16, color: AppTheme.cyan),
          SizedBox(width: 8),
          Text('Play', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ])),
        const PopupMenuItem(value: 'play_next', child: Row(children: [
          Icon(Icons.playlist_play_rounded, size: 16, color: AppTheme.violet),
          SizedBox(width: 8),
          Text('Play Next', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ])),
        const PopupMenuItem(value: 'add_queue', child: Row(children: [
          Icon(Icons.queue_music_rounded, size: 16, color: AppTheme.textSecondary),
          SizedBox(width: 8),
          Text('Add to Queue', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'cues', child: Row(children: [
          Icon(Icons.flag_rounded, size: 16, color: AppTheme.amber),
          SizedBox(width: 8),
          Text('Generate Hot Cues', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ])),
        if (hasCues)
          PopupMenuItem(value: 'view_cues', child: Row(children: [
            const Icon(Icons.view_list_rounded, size: 16, color: AppTheme.lime),
            const SizedBox(width: 8),
            Text('View Cues (${cueState.results[track.id]!.cues.length})',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          ])),
        const PopupMenuItem(value: 'info', child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textSecondary),
          SizedBox(width: 8),
          Text('Track Info', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        ])),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'play':
          ref.read(djPlayerProvider.notifier).smartLoad(track);
        case 'play_next':
          ref.read(djPlayerProvider.notifier).playNext(track);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${track.title}" will play next'),
            backgroundColor: AppTheme.violet.withValues(alpha: 0.9),
            duration: const Duration(seconds: 2),
          ));
        case 'add_queue':
          ref.read(djPlayerProvider.notifier).addToQueue(track);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${track.title}" added to queue'),
            backgroundColor: AppTheme.cyan.withValues(alpha: 0.9),
            duration: const Duration(seconds: 2),
          ));
        case 'cues':
          _generateCuesForTrack(track);
        case 'view_cues':
          _showCueDialog(context, track, cueState.results[track.id]!);
        case 'info':
          _showTrackInfo(context, track);
      }
    });
  }

  Future<void> _generateCuesForTrack(LibraryTrack track) async {
    try {
      final result = await ref.read(cueProvider.notifier).generateForTrack(track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Generated ${result.cues.length} cue points for "${track.title}"'),
          backgroundColor: AppTheme.lime.withValues(alpha: 0.9),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cue generation failed: $e'),
          backgroundColor: AppTheme.pink,
        ));
      }
    }
  }

  void _showCueDialog(BuildContext ctx, LibraryTrack track, CueGenerationResult result) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.panelRaised,
        title: Text('Hot Cues: ${track.title}',
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${result.cues.length} cues · ${result.highConfidenceCount} high-confidence',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              const SizedBox(height: 12),
              ...result.cues.map((cue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      color: _parseHexColor(cue.cueType.vdjColor),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(cue.label,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11))),
                  Text(_formatSec(cue.timeSeconds),
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontFamily: 'monospace')),
                  const SizedBox(width: 8),
                  Text('${(cue.confidence * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: cue.confidence >= 0.75 ? AppTheme.lime : AppTheme.amber,
                        fontSize: 9, fontWeight: FontWeight.w600)),
                ]),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }

  String _formatSec(double seconds) {
    final s = seconds.toInt();
    final m = s ~/ 60;
    final frac = ((seconds - s) * 10).toInt();
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}.$frac';
  }

  Color _parseHexColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  void _showTrackInfo(BuildContext ctx, LibraryTrack track) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.panelRaised,
        title: Text(track.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Artist', track.artist),
              _infoRow('Album', track.album),
              _infoRow('Genre', track.genre),
              _infoRow('BPM', track.bpm > 0 ? track.bpm.toStringAsFixed(1) : 'Unknown'),
              _infoRow('Key', track.key.isNotEmpty && track.key != '--' ? track.key : 'Unknown'),
              _infoRow('Duration', '${(track.durationSeconds / 60).toStringAsFixed(1)} min'),
              _infoRow('Format', track.fileExtension.replaceFirst('.', '').toUpperCase()),
              _infoRow('Bitrate', '${track.bitrate} kbps'),
              _infoRow('Size', track.fileSizeFormatted),
              _infoRow('Path', track.filePath),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 2)),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Generate All Cues Button (with progress)
// ══════════════════════════════════════════════════════════════════════════════

class _GenerateAllCuesButton extends ConsumerStatefulWidget {
  final List<LibraryTrack> tracks;
  const _GenerateAllCuesButton({required this.tracks});
  @override
  ConsumerState<_GenerateAllCuesButton> createState() => _GenerateAllCuesButtonState();
}

class _GenerateAllCuesButtonState extends ConsumerState<_GenerateAllCuesButton> {
  bool _running = false;
  String? _resultMessage;

  Future<void> _run() async {
    setState(() { _running = true; _resultMessage = null; });
    try {
      final results = await ref.read(cueProvider.notifier).generateForTracks(widget.tracks);
      final success = results.values.where((r) => r.isSuccess).length;
      final failed = results.values.where((r) => r.hasError).length;
      final noMeta = results.values.where((r) => r.status == CueGenerationStatus.insufficientMetadata).length;
      final total = results.length;

      String msg;
      if (success == total) {
        msg = '$success tracks — cues generated';
      } else if (success > 0) {
        msg = '$success cues OK, $noMeta missing metadata, $failed failed';
      } else {
        msg = 'No cues generated — $noMeta tracks lack duration/BPM data';
      }

      if (mounted) {
        setState(() { _running = false; _resultMessage = msg; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: success > 0 ? AppTheme.lime.withValues(alpha: 0.9) : AppTheme.amber,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() { _running = false; _resultMessage = 'Error: $e'; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cue generation error: $e'),
          backgroundColor: AppTheme.pink,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cue = ref.watch(cueProvider);

    if (_running || (cue.isGenerating && cue.batchTotal > 0)) {
      final pct = cue.batchTotal > 0 ? cue.batchProgress / cue.batchTotal : 0.0;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              value: pct > 0 ? pct : null,
              strokeWidth: 2,
              color: AppTheme.amber,
              backgroundColor: AppTheme.amber.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            cue.batchTotal > 0
                ? '${cue.batchProgress}/${cue.batchTotal} tracks'
                : 'Starting…',
            style: const TextStyle(color: AppTheme.amber, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ]),
      );
    }

    // Show result summary if we have one
    if (_resultMessage != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(_resultMessage!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        _buildButton(),
      ]);
    }

    return _buildButton();
  }

  Widget _buildButton() {
    return ElevatedButton.icon(
      onPressed: widget.tracks.isEmpty ? null : _run,
      icon: const Icon(Icons.flag_rounded, size: 16),
      label: const Text('Generate All Cues'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.amber.withValues(alpha: 0.2),
        foregroundColor: AppTheme.amber,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GRID CARD: Recommendation (platform result)
// ══════════════════════════════════════════════════════════════════════════════

Widget _libArtPlaceholder() => Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [
        AppTheme.violet.withValues(alpha: 0.15),
        AppTheme.pink.withValues(alpha: 0.08),
        AppTheme.edge,
      ],
    ),
  ),
  child: Center(
    child: Icon(Icons.music_note_rounded,
        color: AppTheme.textTertiary.withValues(alpha: 0.5), size: 36),
  ),
);

class _RecommendationCard extends StatefulWidget {
  final PlatformTrackResult result;
  const _RecommendationCard({required this.result});
  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: r.hasUrl ? () {
          final uri = Uri.tryParse(r.bestUrl);
          if (uri != null) {
            Process.run('open', [r.bestUrl]);
          }
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: r.artworkUrl != null
                            ? CachedNetworkImage(imageUrl: r.artworkUrl!, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _artPlaceholder())
                            : _artPlaceholder(),
                      ),
                    ),
                    // Source badges (top-right)
                    Positioned(
                      top: 8, right: 8,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (r.spotifyUrl != null) _SourceIcon(Colors.green),
                        if (r.appleUrl != null) _SourceIcon(AppTheme.pink),
                        if (r.youtubeUrl != null) _SourceIcon(const Color(0xFFFF4B4B)),
                      ]),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.cyan, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          )),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(r.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppTheme.cyan.withValues(alpha: 0.12), AppTheme.edge]),
    ),
    child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
  );
}

class _SourceIcon extends StatelessWidget {
  final Color color;
  const _SourceIcon(this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14, height: 14,
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.3), width: 1)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SHARED COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════

class _StatBadge extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _StatBadge(this.icon, this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _ScanProgressChip extends StatelessWidget {
  final int scanned; final int total; final String label;
  const _ScanProgressChip({required this.scanned, required this.total, this.label = 'Scanning'});
  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? scanned / total : 0.0;
    return Row(children: [
      SizedBox(width: 120, child: LinearProgressIndicator(value: pct, backgroundColor: AppTheme.edge, valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyan))),
      const SizedBox(width: 10),
      Text('$label  $scanned / $total', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
    ]);
  }
}

class _FilterDrop extends StatelessWidget {
  final String value; final List<String> items; final ValueChanged<String?> onChanged;
  const _FilterDrop({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.edge)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isDense: true, dropdownColor: AppTheme.panel,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          items: items.take(50).map((g) => DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  final String sortBy; final bool asc; final ValueChanged<String> onSort;
  const _SortButton({required this.sortBy, required this.asc, required this.onSort});
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSort,
      icon: Icon(asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16, color: AppTheme.textSecondary),
      tooltip: 'Sort by', color: AppTheme.panel,
      itemBuilder: (_) => [
        for (final col in ['title', 'artist', 'bpm', 'genre', 'year', 'size'])
          PopupMenuItem(value: col, child: Row(children: [
            if (sortBy == col) const Icon(Icons.check, size: 14, color: AppTheme.cyan) else const SizedBox(width: 14),
            const SizedBox(width: 8),
            Text(col[0].toUpperCase() + col.substring(1), style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
          ])),
      ],
    );
  }
}

class _StatsSection extends StatelessWidget {
  final String title; final List<MapEntry<String, int>> items; final Color color;
  const _StatsSection({required this.title, required this.items, required this.color});
  @override
  Widget build(BuildContext context) {
    final maxVal = items.isEmpty ? 1 : items.first.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 8),
      ...items.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(width: 100, child: Text(e.key, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11), overflow: TextOverflow.ellipsis)),
          Expanded(
            child: Stack(children: [
              Container(height: 16, decoration: BoxDecoration(color: AppTheme.edge, borderRadius: BorderRadius.circular(3))),
              FractionallySizedBox(
                widthFactor: (e.value / maxVal).clamp(0.02, 1.0),
                child: Container(height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(3))),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 30, child: Text('${e.value}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), textAlign: TextAlign.right)),
        ]),
      )),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AI CRATE COMPONENTS
// ══════════════════════════════════════════════════════════════════════════════

class _AiCrateDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _AiCrateDropdown({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.edge),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: const Text('Any', style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
          isExpanded: true,
          isDense: true,
          dropdownColor: AppTheme.panel,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('Any')),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(i))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _AiCrateCard extends ConsumerStatefulWidget {
  final int index;
  final GeneratedCrate crate;
  const _AiCrateCard({required this.index, required this.crate});
  @override
  ConsumerState<_AiCrateCard> createState() => _AiCrateCardState();
}

class _AiCrateCardState extends ConsumerState<_AiCrateCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final crate = widget.crate;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.cyan]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Text(
                    '${widget.index + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(crate.name, style: const TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(crate.description, style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                )),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${crate.tracks.length} tracks',
                      style: const TextStyle(color: AppTheme.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(crate.totalDurationFormatted,
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                ]),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.textSecondary, size: 20,
                ),
              ]),
            ),
          ),

          // Expanded: track list + actions
          if (_expanded) ...[
            const Divider(color: AppTheme.edge, height: 1),
            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                _AiCrateActionButton(
                  icon: Icons.save_rounded,
                  label: 'Save to Crates',
                  color: AppTheme.lime,
                  onTap: () {
                    ref.read(smartCrateProvider.notifier).saveCrate(widget.index);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('"${crate.name}" saved to your crates'),
                      backgroundColor: AppTheme.lime.withValues(alpha: 0.9),
                    ));
                  },
                ),
                _AiCrateActionButton(
                  icon: Icons.headset_rounded,
                  label: 'Export VDJ',
                  color: AppTheme.cyan,
                  onTap: () => ref.read(smartCrateProvider.notifier).exportToVdj(widget.index, context),
                ),
                _AiCrateActionButton(
                  icon: Icons.album_rounded,
                  label: 'Export Serato',
                  color: AppTheme.violet,
                  onTap: () => ref.read(smartCrateProvider.notifier).exportToSerato(widget.index, context),
                ),
                _AiCrateActionButton(
                  icon: Icons.playlist_play_rounded,
                  label: 'Export M3U',
                  color: AppTheme.amber,
                  onTap: () => ref.read(smartCrateProvider.notifier).exportToM3u(widget.index, context),
                ),
              ]),
            ),
            // Track list
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: crate.tracks.asMap().entries.map((entry) {
                    final i = entry.key;
                    final t = entry.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: i < crate.tracks.length - 1
                            ? const Border(bottom: BorderSide(color: AppTheme.edge, width: 0.5))
                            : null,
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: 22,
                          child: Text('${i + 1}',
                              style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontFamily: 'monospace')),
                        ),
                        Expanded(child: Text(t.title,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11),
                            overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: Text(t.artist,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        if (t.bpm > 0)
                          SizedBox(
                            width: 36,
                            child: Text('${t.bpm.toStringAsFixed(0)}',
                                style: const TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600),
                                textAlign: TextAlign.right),
                          ),
                        const SizedBox(width: 8),
                        if (t.key.isNotEmpty && t.key != '--')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(t.key,
                                style: const TextStyle(color: AppTheme.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiCrateActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AiCrateActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 96, height: 96, decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3))),
        child: const Icon(Icons.folder_rounded, size: 48, color: AppTheme.violet)),
      const SizedBox(height: 24),
      const Text('No library scanned yet', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 18)),
      const SizedBox(height: 8),
      const Text('Pick a folder with your music files to start.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      const SizedBox(height: 20),
      const Wrap(spacing: 16, children: [
        _InfoChip(icon: Icons.audio_file_rounded, label: 'MP3, FLAC, WAV, AAC, M4A'),
        _InfoChip(icon: Icons.fingerprint_rounded, label: 'BPM, Key, Duration'),
        _InfoChip(icon: Icons.content_copy_rounded, label: 'Auto duplicate detection'),
      ]),
    ]));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon; final String label;
  const _InfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.edge)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppTheme.cyan, size: 14),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});
  bool get _isPermission => message.toLowerCase().contains('permission') || message.toLowerCase().contains('denied');
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 96, height: 96, decoration: BoxDecoration(color: AppTheme.pink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.pink.withValues(alpha: 0.3))),
        child: Icon(_isPermission ? Icons.lock_outline_rounded : Icons.error_outline_rounded, size: 48, color: AppTheme.pink)),
      const SizedBox(height: 24),
      Text(_isPermission ? 'Permission denied' : 'Scan failed', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 18)),
      const SizedBox(height: 8),
      Text(_isPermission ? 'Grant Full Disk Access in System Settings → Privacy & Security.' : message,
          textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ])));
  }
}

class _ZeroFilesState extends StatelessWidget {
  final String path;
  const _ZeroFilesState({required this.path});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 96, height: 96, decoration: BoxDecoration(color: AppTheme.violet.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppTheme.violet.withValues(alpha: 0.3))),
        child: const Icon(Icons.search_off_rounded, size: 48, color: AppTheme.violet)),
      const SizedBox(height: 24),
      const Text('No audio files found', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 18)),
      const SizedBox(height: 8),
      Text('Scanned: $path\nTry a folder with MP3, FLAC, WAV, AAC, or M4A files.',
          textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
    ])));
  }
}
