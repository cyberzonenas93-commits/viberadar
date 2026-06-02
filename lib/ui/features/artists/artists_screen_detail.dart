part of 'artists_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Artist Catalog — full child screen when artist is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistCatalogScreen extends ConsumerStatefulWidget {
  final _ArtistInfo artist;
  final ArtistModel? artistModel;
  final VoidCallback onBack;

  const _ArtistCatalogScreen({
    required this.artist,
    required this.onBack,
    this.artistModel,
  });

  @override
  ConsumerState<_ArtistCatalogScreen> createState() => _ArtistCatalogScreenState();
}

class _ArtistCatalogScreenState extends ConsumerState<_ArtistCatalogScreen> {
  String _sortBy = 'score';
  String _view = 'all'; // 'all', 'top', 'radar'
  final Set<String> _selectedTrackIds = {};
  final _spotifyService = SpotifyArtistService();
  final _appleMusicService = AppleMusicArtistService();
  List<SpotifyTrackInfo>? _spotifyCatalogue;
  List<AppleMusicTrack>? _appleMusicTracks;
  bool _loadingCatalogue = false;
  bool _loadingApple = false;

  @override
  void initState() {
    super.initState();
    _loadSpotifyCatalogue();
    _loadAppleMusic();
  }

  Future<void> _loadSpotifyCatalogue() async {
    setState(() { _loadingCatalogue = true; });
    try {
      final catalogue = await _spotifyService.getFullCatalogue(widget.artist.name);
      if (mounted) {
        setState(() {
          _spotifyCatalogue = catalogue;
          _loadingCatalogue = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCatalogue = false;
        });
      }
    }
  }

  Future<void> _loadAppleMusic() async {
    setState(() { _loadingApple = true; });
    try {
      final tracks = await _appleMusicService.getFullDiscography(widget.artist.name);
      if (mounted) {
        setState(() {
          _appleMusicTracks = tracks;
          _loadingApple = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingApple = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.artist;
    final crateState = ref.watch(crateProvider);

    // Combine radar tracks with Spotify catalogue
    final radarTracks = [...a.tracks];
    radarTracks.sort((a, b) => b.trendScore.compareTo(a.trendScore));

    final spotifyTracks = _spotifyCatalogue ?? [];

    final appleTracks = _appleMusicTracks ?? [];
    final mergedAll = _mergeToUnified(spotifyTracks, appleTracks);
    final mergedTop = mergedAll.where((t) => t.isTopTrack).toList();

    // Sort merged tracks
    var displayMerged = _view == 'top' ? [...mergedTop] : [...mergedAll];
    switch (_sortBy) {
      case 'title':
        displayMerged.sort((a, b) => a.name.compareTo(b.name));
      case 'album':
        displayMerged.sort((a, b) => a.albumName.compareTo(b.albumName));
      case 'popularity':
        displayMerged.sort((a, b) => b.popularity.compareTo(a.popularity));
      default:
        break;
    }

    return Column(
      children: [
        // Header with back button and artist info
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 28, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.violet.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
                tooltip: 'Back to all artists',
              ),
              const SizedBox(width: 8),
              // Artist artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: a.artworkUrl != null
                    ? CachedNetworkImage(
                        imageUrl: a.artworkUrl!,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorWidget: (_, e, s) => _AvatarFallback(name: a.name),
                      )
                    : _AvatarFallback(name: a.name),
              ),
              const SizedBox(width: 20),
              // Artist meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _InfoChip(text: a.topGenre, color: AppTheme.violet),
                        _InfoChip(text: a.topRegion, color: AppTheme.cyan),
                        _InfoChip(text: '${a.trackCount} tracks', color: AppTheme.textSecondary),
                        _InfoChip(text: 'Score: ${(a.avgTrendScore * 100).toInt()}', color: AppTheme.amber),
                      ],
                    ),
                    if (a.spotifyUrl != null) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.tryParse(a.spotifyUrl!);
                          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_new_rounded, color: Color(0xFF1DB954), size: 12),
                              SizedBox(width: 6),
                              Text('Open in Spotify', style: TextStyle(color: Color(0xFF1DB954), fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Build Set button
                  if (widget.artistModel != null && widget.artistModel!.topTracks.isNotEmpty)
                    _BuildSetButton(
                      artistModel: widget.artistModel!,
                      onBuilt: (count) => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added $count tracks to Set Builder'),
                          backgroundColor: AppTheme.violet,
                          duration: const Duration(seconds: 2),
                        ),
                      ),
                    ),
                  if (widget.artistModel != null) const SizedBox(height: 8),
                  // Sort selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Sort: ', style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _sortBy,
                            isDense: true,
                            dropdownColor: AppTheme.panelRaised,
                            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                            items: const [
                              DropdownMenuItem(value: 'score', child: Text('Hottest')),
                              DropdownMenuItem(value: 'title', child: Text('Title A-Z')),
                              DropdownMenuItem(value: 'bpm', child: Text('BPM')),
                              DropdownMenuItem(value: 'genre', child: Text('Genre')),
                            ],
                            onChanged: (v) { if (v != null) setState(() => _sortBy = v); },
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedTrackIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _AddToCrateButton(
                      selectedCount: _selectedTrackIds.length,
                      crateNames: crateState.crates.keys.toList(),
                      onAddToCrate: (crateName) {
                        for (final id in _selectedTrackIds) {
                          ref.read(crateProvider.notifier).addTrackToCrate(crateName, id);
                        }
                        setState(() => _selectedTrackIds.clear());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added ${_selectedTrackIds.isEmpty ? "tracks" : ""} to $crateName'),
                            backgroundColor: AppTheme.violet,
                          ),
                        );
                      },
                      onNewCrate: (name) {
                        ref.read(crateProvider.notifier).createCrate(name);
                        for (final id in _selectedTrackIds) {
                          ref.read(crateProvider.notifier).addTrackToCrate(name, id);
                        }
                        setState(() => _selectedTrackIds.clear());
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Source status + view tabs
        Container(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Source status row (replaces platform switcher)
              Row(
                children: [
                  if (_loadingCatalogue) ...[
                    const SizedBox(width: 4, height: 4, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF1DB954))),
                    const SizedBox(width: 6),
                    const Text('Loading Spotify...', style: TextStyle(color: Color(0xFF1DB954), fontSize: 10)),
                    const SizedBox(width: 12),
                  ] else ...[
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF1DB954), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${spotifyTracks.length} from Spotify', style: const TextStyle(color: Color(0xFF1DB954), fontSize: 10, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                  ],
                  if (_loadingApple) ...[
                    const SizedBox(width: 4, height: 4, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFFC3C44))),
                    const SizedBox(width: 6),
                    const Text('Loading Apple Music...', style: TextStyle(color: Color(0xFFFC3C44), fontSize: 10)),
                  ] else ...[
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFFC3C44), shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('${appleTracks.length} from Apple Music', style: const TextStyle(color: Color(0xFFFC3C44), fontSize: 10, fontWeight: FontWeight.w500)),
                  ],
                  const Spacer(),
                  if (_selectedTrackIds.isNotEmpty) ...[
                    Text('${_selectedTrackIds.length} selected', style: const TextStyle(color: AppTheme.violet, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _selectedTrackIds.clear()),
                      child: const Text('Clear', style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // Sub-view tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ViewTab(label: 'Full Catalogue', subtitle: _loadingCatalogue ? 'Loading...' : '${displayMerged.length}', isActive: _view == 'all', onTap: () => setState(() => _view = 'all')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'Albums', subtitle: _loadingCatalogue ? '...' : '${_albumGroups(spotifyTracks).length}', isActive: _view == 'albums', onTap: () => setState(() => _view = 'albums')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'Top Tracks', subtitle: '${mergedTop.length}', isActive: _view == 'top', onTap: () => setState(() => _view = 'top')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'In Radar', subtitle: '${radarTracks.length}', isActive: _view == 'radar', onTap: () => setState(() => _view = 'radar')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'Trending', subtitle: '${widget.artistModel?.trendingTracks.length ?? 0}', isActive: _view == 'trending', onTap: () => setState(() => _view = 'trending')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'By Era', subtitle: '${widget.artistModel?.tracksByEra.length ?? 0} eras', isActive: _view == 'by_era', onTap: () => setState(() => _view = 'by_era')),
                    const SizedBox(width: 8),
                    _ViewTab(label: 'By BPM', subtitle: widget.artistModel?.bpmRangeLabel ?? '—', isActive: _view == 'by_bpm', onTap: () => setState(() => _view = 'by_bpm')),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
        // Content area
        Expanded(
          child: _view == 'trending'
              ? _buildRadarTrackGrid(
                  widget.artistModel?.trendingTracks ?? [],
                  emptyMsg: 'No trending tracks — all are near the average.',
                )
              : _view == 'by_era'
              ? _buildEraView(widget.artistModel?.tracksByEra ?? {})
              : _view == 'by_bpm'
              ? _buildBpmView(
                  [...(widget.artistModel?.topTracks ?? []),
                   ...(widget.artistModel?.trendingTracks ?? [])]
                    ..sort((a, b) => a.bpm.compareTo(b.bpm)),
                )
              : _view == 'albums'
              ? _buildAlbumsView(spotifyTracks)
              : _view == 'radar'
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: radarTracks.length,
                  itemBuilder: (context, i) => _RadarTrackCard(track: radarTracks[i], rank: i + 1),
                )
              : (_loadingCatalogue && displayMerged.isEmpty)
                  ? const Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.violet),
                        SizedBox(height: 12),
                        Text('Loading catalogue...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ))
                  : displayMerged.isEmpty
                      ? const Center(child: Text('No tracks found', style: TextStyle(color: AppTheme.textTertiary)))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: displayMerged.length,
                          itemBuilder: (context, i) => _UnifiedTrackCard(
                            track: displayMerged[i],
                            rank: i + 1,
                          ),
                        ),
        ),
      ],
    );
  }

  // ── Intelligence tab helpers ──────────────────────────────────────────────

  Widget _buildRadarTrackGrid(List<Track> tracks, {String emptyMsg = 'No tracks found'}) {
    if (tracks.isEmpty) {
      return Center(child: Text(emptyMsg, style: const TextStyle(color: AppTheme.textTertiary)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, childAspectRatio: 0.72,
        crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: tracks.length,
      itemBuilder: (context, i) => _RadarTrackCard(track: tracks[i], rank: i + 1),
    );
  }

  Widget _buildEraView(Map<String, List<Track>> tracksByEra) {
    if (tracksByEra.isEmpty) {
      return const Center(child: Text('No era data available', style: TextStyle(color: AppTheme.textTertiary)));
    }
    final eras = ['2000s', '2010s', '2020s'].where(tracksByEra.containsKey).toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      itemCount: eras.length,
      itemBuilder: (context, eraIdx) {
        final era = eras[eraIdx];
        final tracks = tracksByEra[era]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.violet, AppTheme.cyan]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(era, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Text('${tracks.length} track${tracks.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ]),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200, childAspectRatio: 0.72,
                crossAxisSpacing: 12, mainAxisSpacing: 12,
              ),
              itemCount: tracks.length,
              itemBuilder: (ctx, i) => _RadarTrackCard(track: tracks[i], rank: i + 1),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildBpmView(List<Track> tracks) {
    if (tracks.isEmpty) {
      return const Center(child: Text('No BPM data available', style: TextStyle(color: AppTheme.textTertiary)));
    }
    // Group by BPM bucket (10-BPM bands)
    final buckets = <String, List<Track>>{};
    for (final t in tracks) {
      if (t.bpm <= 0) continue;
      final band = '${(t.bpm ~/ 10) * 10}–${(t.bpm ~/ 10) * 10 + 9}';
      buckets.putIfAbsent(band, () => []).add(t);
    }
    if (buckets.isEmpty) {
      return const Center(child: Text('No BPM data available', style: TextStyle(color: AppTheme.textTertiary)));
    }
    final keys = buckets.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      itemCount: keys.length,
      itemBuilder: (context, idx) {
        final band = keys[idx];
        final bpmTracks = buckets[band]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: Text('$band BPM',
                      style: const TextStyle(color: AppTheme.amber, fontWeight: FontWeight.w700, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Text('${bpmTracks.length} track${bpmTracks.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
              ]),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200, childAspectRatio: 0.72,
                crossAxisSpacing: 12, mainAxisSpacing: 12,
              ),
              itemCount: bpmTracks.length,
              itemBuilder: (ctx, i) => _RadarTrackCard(track: bpmTracks[i], rank: i + 1),
            ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  /// Group tracks by album name, preserving track order.
  static List<_AlbumGroup> _albumGroups(List<SpotifyTrackInfo> tracks) {
    final map = <String, _AlbumGroup>{};
    for (final t in tracks) {
      final key = t.albumName.isEmpty ? 'Singles' : t.albumName;
      map.putIfAbsent(key, () => _AlbumGroup(
        name: key,
        artworkUrl: t.albumArt,
        releaseDate: t.releaseDate,
        tracks: [],
      )).tracks.add(t);
    }
    // Sort albums by release date descending (newest first)
    final groups = map.values.toList();
    groups.sort((a, b) {
      final dateA = a.releaseDate ?? '';
      final dateB = b.releaseDate ?? '';
      return dateB.compareTo(dateA);
    });
    return groups;
  }

  Widget _buildAlbumsView(List<SpotifyTrackInfo> allSpotifyTracks) {
    if (_loadingCatalogue) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.violet),
          SizedBox(height: 12),
          Text('Loading albums...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ));
    }

    final albums = _albumGroups(allSpotifyTracks);
    if (albums.isEmpty) {
      return const Center(child: Text('No albums found', style: TextStyle(color: AppTheme.textTertiary)));
    }

    return CustomScrollView(
      slivers: [
        for (final album in albums) ...[
          // Album header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: album.artworkUrl != null
                        ? CachedNetworkImage(imageUrl: album.artworkUrl!, width: 48, height: 48, fit: BoxFit.cover)
                        : Container(width: 48, height: 48, color: AppTheme.edge, child: const Icon(Icons.album_rounded, color: AppTheme.textTertiary, size: 20)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(album.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${album.tracks.length} track${album.tracks.length > 1 ? 's' : ''}${album.releaseDate != null && album.releaseDate!.length >= 4 ? '  ·  ${album.releaseDate!.substring(0, 4)}' : ''}',
                          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Album tracks grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _SpotifyTrackCard(track: album.tracks[i], rank: i + 1),
                childCount: album.tracks.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AlbumGroup {
  final String name;
  final String? artworkUrl;
  final String? releaseDate;
  final List<SpotifyTrackInfo> tracks;

  _AlbumGroup({
    required this.name,
    required this.artworkUrl,
    required this.releaseDate,
    required this.tracks,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Build Set button — pre-populates set builder with artist's top tracks
// ─────────────────────────────────────────────────────────────────────────────

class _BuildSetButton extends StatelessWidget {
  final ArtistModel artistModel;
  final void Function(int count) onBuilt;
  const _BuildSetButton({required this.artistModel, required this.onBuilt});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Use SetBuilderService to select from top tracks
        final svc = SetBuilderService();
        final allForArtist = {
          ...artistModel.topTracks,
          ...artistModel.trendingTracks,
        }.toList();
        // Build a 12-track set from artist's tracks using existing logic
        final set = svc.buildSet(
          tracks: allForArtist,
          durationMinutes: 48,
          genre: 'All',
          vibe: 'All',
          minBpm: artistModel.hasBpmData ? artistModel.bpmRange[0].toDouble() : 60,
          maxBpm: artistModel.hasBpmData ? artistModel.bpmRange[1].toDouble() : 200,
        );
        final count = set.isEmpty ? allForArtist.length : set.length;
        onBuilt(count);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.violet, AppTheme.cyan],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: AppTheme.violet.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_rounded, color: Colors.white, size: 14),
            SizedBox(width: 6),
            Text('Build Set',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add to Crate button with dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _AddToCrateButton extends StatelessWidget {
  final int selectedCount;
  final List<String> crateNames;
  final ValueChanged<String> onAddToCrate;
  final ValueChanged<String> onNewCrate;

  const _AddToCrateButton({
    required this.selectedCount,
    required this.crateNames,
    required this.onAddToCrate,
    required this.onNewCrate,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == '__new__') {
          _showNewCrateDialog(context);
        } else {
          onAddToCrate(value);
        }
      },
      color: AppTheme.panelRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) => [
        ...crateNames.map((name) => PopupMenuItem(
          value: name,
          child: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
        )),
        if (crateNames.isNotEmpty) const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__new__',
          child: Row(
            children: [
              Icon(Icons.add_rounded, color: AppTheme.violet, size: 16),
              SizedBox(width: 8),
              Text('New Crate...', style: TextStyle(color: AppTheme.violet, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppTheme.violet, Color(0xFF6D4AE6)]),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: AppTheme.violet.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text('Add $selectedCount to Crate', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showNewCrateDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('New Crate', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Crate name...'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              onNewCrate(value.trim());
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                onNewCrate(name);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Create & Add'),
          ),
        ],
      ),
    );
  }
}
