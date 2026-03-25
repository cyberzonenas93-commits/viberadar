import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/spotify_artist_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Artist aggregate model
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistInfo {
  final String name;
  final String topGenre;
  final String topRegion;
  final double avgTrendScore;
  final int trackCount;
  final String? artworkUrl;
  final String? spotifyUrl;
  final List<Track> tracks;

  const _ArtistInfo({
    required this.name,
    required this.topGenre,
    required this.topRegion,
    required this.avgTrendScore,
    required this.trackCount,
    required this.artworkUrl,
    required this.spotifyUrl,
    required this.tracks,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen — grid of artists OR artist detail (child view)
// ─────────────────────────────────────────────────────────────────────────────

class ArtistsScreen extends ConsumerStatefulWidget {
  const ArtistsScreen({super.key});

  @override
  ConsumerState<ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends ConsumerState<ArtistsScreen> {
  String _search = '';
  String _filterGenre = 'All';
  String _filterRegion = 'All';
  _ArtistInfo? _openedArtist;

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? const <Track>[];

    // Build artist list
    final artistMap = <String, List<Track>>{};
    for (final track in allTracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      artistMap.putIfAbsent(name, () => []).add(track);
    }

    var artists = artistMap.entries.map((entry) {
      final tracks = entry.value;
      final genreCounts = <String, int>{};
      for (final t in tracks) {
        genreCounts[t.genre] = (genreCounts[t.genre] ?? 0) + 1;
      }
      final topGenre = genreCounts.entries.isNotEmpty
          ? (genreCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key
          : 'Open Format';
      final avgScore = tracks.map((t) => t.trendScore).reduce((a, b) => a + b) / tracks.length;
      final bestTrack = tracks.reduce((a, b) => a.trendScore > b.trendScore ? a : b);

      return _ArtistInfo(
        name: entry.key,
        topGenre: topGenre,
        topRegion: bestTrack.leadRegion,
        avgTrendScore: avgScore,
        trackCount: tracks.length,
        artworkUrl: bestTrack.artworkUrl.isNotEmpty ? bestTrack.artworkUrl : null,
        spotifyUrl: bestTrack.platformLinks['spotify'],
        tracks: tracks..sort((a, b) => b.trendScore.compareTo(a.trendScore)),
      );
    }).toList();

    // Default: alphabetical order
    artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Get unique genres/regions for filter dropdowns
    final genreSet = {for (final a in artists) a.topGenre}.toList()..sort();
    final regionSet = {for (final a in artists) a.topRegion}.toList()..sort();
    final allGenres = ['All', ...genreSet];
    final allRegions = ['All', ...regionSet];

    // Apply filters
    if (_filterGenre != 'All') {
      artists = artists.where((a) => a.topGenre == _filterGenre).toList();
    }
    if (_filterRegion != 'All') {
      artists = artists.where((a) => a.topRegion == _filterRegion).toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      artists = artists.where((a) =>
        a.name.toLowerCase().contains(q) ||
        a.topGenre.toLowerCase().contains(q) ||
        a.topRegion.toLowerCase().contains(q)
      ).toList();
    }

    // If an artist is opened, show the detail child screen
    if (_openedArtist != null) {
      return _ArtistCatalogScreen(
        artist: _openedArtist!,
        onBack: () => setState(() => _openedArtist = null),
      );
    }

    return _ArtistGridScreen(
      artists: artists,
      allTracks: allTracks,
      search: _search,
      filterGenre: _filterGenre,
      filterRegion: _filterRegion,
      allGenres: allGenres,
      allRegions: allRegions,
      onSearchChanged: (v) => setState(() => _search = v),
      onGenreChanged: (v) => setState(() => _filterGenre = v),
      onRegionChanged: (v) => setState(() => _filterRegion = v),
      onArtistTapped: (artist) => setState(() => _openedArtist = artist),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Artist Grid — the main listing view
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistGridScreen extends StatelessWidget {
  final List<_ArtistInfo> artists;
  final List<Track> allTracks;
  final String search;
  final String filterGenre;
  final String filterRegion;
  final List<String> allGenres;
  final List<String> allRegions;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onGenreChanged;
  final ValueChanged<String> onRegionChanged;
  final ValueChanged<_ArtistInfo> onArtistTapped;

  const _ArtistGridScreen({
    required this.artists,
    required this.allTracks,
    required this.search,
    required this.filterGenre,
    required this.filterRegion,
    required this.allGenres,
    required this.allRegions,
    required this.onSearchChanged,
    required this.onGenreChanged,
    required this.onRegionChanged,
    required this.onArtistTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_rounded, color: AppTheme.violet, size: 22),
                      const SizedBox(width: 10),
                      Text('Artists', style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${artists.length} artists from ${allTracks.length} tracks  ·  Tap an artist to see their full catalog',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              _FilterDropdown(label: 'Genre', value: filterGenre, options: allGenres, onChanged: onGenreChanged),
              const SizedBox(width: 8),
              _FilterDropdown(label: 'Region', value: filterRegion, options: allRegions, onChanged: onRegionChanged),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  onChanged: onSearchChanged,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search artists...',
                    hintStyle: const TextStyle(color: AppTheme.textTertiary),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.panelRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: artists.isEmpty
              ? const Center(child: Text('No artists found', style: TextStyle(color: AppTheme.textTertiary)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: artists.length,
                  itemBuilder: (context, i) => _ArtistCard(
                    artist: artists[i],
                    onTap: () => onArtistTapped(artists[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ArtistCard extends StatefulWidget {
  final _ArtistInfo artist;
  final VoidCallback onTap;

  const _ArtistCard({required this.artist, required this.onTap});

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.artist;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            children: [
              // Artwork area
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: a.artworkUrl != null
                            ? CachedNetworkImage(
                                imageUrl: a.artworkUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _AvatarFallback(name: a.name, large: true),
                              )
                            : _AvatarFallback(name: a.name, large: true),
                      ),
                    ),
                    // Track count badge
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${a.trackCount} track${a.trackCount > 1 ? 's' : ''}',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    // Hover overlay
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: const Center(
                            child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(a.topGenre, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                        const Spacer(),
                        Text('${(a.avgTrendScore * 100).toInt()}', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Artist Catalog — full child screen when artist is tapped
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistCatalogScreen extends ConsumerStatefulWidget {
  final _ArtistInfo artist;
  final VoidCallback onBack;

  const _ArtistCatalogScreen({required this.artist, required this.onBack});

  @override
  ConsumerState<_ArtistCatalogScreen> createState() => _ArtistCatalogScreenState();
}

class _ArtistCatalogScreenState extends ConsumerState<_ArtistCatalogScreen> {
  String _sortBy = 'score';
  String _view = 'all'; // 'all', 'top', 'radar'
  final Set<String> _selectedTrackIds = {};
  final _spotifyService = SpotifyArtistService();
  List<SpotifyTrackInfo>? _spotifyCatalogue;
  bool _loadingCatalogue = false;
  String? _catalogueError;

  @override
  void initState() {
    super.initState();
    _loadSpotifyCatalogue();
  }

  Future<void> _loadSpotifyCatalogue() async {
    setState(() { _loadingCatalogue = true; _catalogueError = null; });
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
          _catalogueError = e.toString();
          _loadingCatalogue = false;
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
    final topTracks = spotifyTracks.where((t) => t.isTopTrack).toList();

    // Sort Spotify tracks
    var displaySpotify = _view == 'top' ? topTracks : [...spotifyTracks];
    switch (_sortBy) {
      case 'title':
        displaySpotify.sort((a, b) => a.name.compareTo(b.name));
      case 'album':
        displaySpotify.sort((a, b) => a.albumName.compareTo(b.albumName));
      case 'popularity':
        displaySpotify.sort((a, b) => b.popularity.compareTo(a.popularity));
      default:
        // Keep default order (top tracks first, then by album)
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
                    Row(
                      children: [
                        _InfoChip(text: a.topGenre, color: AppTheme.violet),
                        const SizedBox(width: 8),
                        _InfoChip(text: a.topRegion, color: AppTheme.cyan),
                        const SizedBox(width: 8),
                        _InfoChip(text: '${a.trackCount} tracks', color: AppTheme.textSecondary),
                        const SizedBox(width: 8),
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
        // View tabs
        Container(
          padding: const EdgeInsets.fromLTRB(28, 10, 28, 8),
          child: Row(
            children: [
              _ViewTab(label: 'Full Catalogue', subtitle: _loadingCatalogue ? 'Loading...' : '${displaySpotify.length}', isActive: _view == 'all', onTap: () => setState(() => _view = 'all')),
              const SizedBox(width: 8),
              _ViewTab(label: 'Top Tracks', subtitle: '${topTracks.length}', isActive: _view == 'top', onTap: () => setState(() => _view = 'top')),
              const SizedBox(width: 8),
              _ViewTab(label: 'In Radar', subtitle: '${radarTracks.length}', isActive: _view == 'radar', onTap: () => setState(() => _view = 'radar')),
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
        ),
        Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
        // Track list — either Spotify catalogue or radar tracks
        Expanded(
          child: _view == 'radar'
              ? ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
            itemCount: radarTracks.length,
            itemBuilder: (context, i) {
              final track = radarTracks[i];
              final isSelected = _selectedTrackIds.contains(track.id);
              return _CatalogTrackRow(
                track: track,
                rank: i + 1,
                isSelected: isSelected,
                onToggleSelect: () {
                  setState(() {
                    if (isSelected) {
                      _selectedTrackIds.remove(track.id);
                    } else {
                      _selectedTrackIds.add(track.id);
                    }
                  });
                },
              );
            },
          )
              : _loadingCatalogue
                  ? const Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.violet),
                        SizedBox(height: 12),
                        Text('Loading full catalogue from Spotify...', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ))
                  : _catalogueError != null
                      ? Center(child: Text('Could not load catalogue', style: TextStyle(color: AppTheme.textTertiary)))
                      : displaySpotify.isEmpty
                          ? const Center(child: Text('No tracks found', style: TextStyle(color: AppTheme.textTertiary)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                              itemCount: displaySpotify.length,
                              itemBuilder: (context, i) {
                                final st = displaySpotify[i];
                                final isSelected = _selectedTrackIds.contains(st.id);
                                return _SpotifyTrackRow(
                                  track: st,
                                  rank: i + 1,
                                  isSelected: isSelected,
                                  onToggleSelect: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedTrackIds.remove(st.id);
                                      } else {
                                        _selectedTrackIds.add(st.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
        ),
      ],
    );
  }
}

// Spotify catalogue track row
class _SpotifyTrackRow extends StatefulWidget {
  final SpotifyTrackInfo track;
  final int rank;
  final bool isSelected;
  final VoidCallback onToggleSelect;

  const _SpotifyTrackRow({
    required this.track,
    required this.rank,
    required this.isSelected,
    required this.onToggleSelect,
  });

  @override
  State<_SpotifyTrackRow> createState() => _SpotifyTrackRowState();
}

class _SpotifyTrackRowState extends State<_SpotifyTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppTheme.violet.withValues(alpha: 0.08)
              : _hovered ? AppTheme.panelRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: widget.isSelected ? Border.all(color: AppTheme.violet.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: widget.onToggleSelect,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: widget.isSelected ? AppTheme.violet : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: widget.isSelected ? AppTheme.violet : AppTheme.edge, width: 1.5),
                ),
                child: widget.isSelected ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
              ),
            ),
            const SizedBox(width: 12),
            // Rank
            SizedBox(
              width: 28,
              child: Text('${widget.rank}', style: TextStyle(color: t.isTopTrack ? AppTheme.amber : AppTheme.textTertiary, fontWeight: t.isTopTrack ? FontWeight.w700 : FontWeight.w500, fontSize: 12)),
            ),
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: t.albumArt != null
                  ? CachedNetworkImage(imageUrl: t.albumArt!, width: 44, height: 44, fit: BoxFit.cover, errorWidget: (_, e, s) => _SmallArtPlaceholder())
                  : _SmallArtPlaceholder(),
            ),
            const SizedBox(width: 14),
            // Title + Album
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (t.isTopTrack)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.star_rounded, color: AppTheme.amber, size: 14),
                        ),
                      Expanded(
                        child: Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(t.albumName, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Duration
            SizedBox(
              width: 45,
              child: Text(t.durationFormatted, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 12),
            // Release date
            if (t.releaseDate != null)
              SizedBox(
                width: 55,
                child: Text(t.releaseDate!.length >= 4 ? t.releaseDate!.substring(0, 4) : '', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11), textAlign: TextAlign.right),
              ),
            const SizedBox(width: 12),
            // Popularity bar
            if (t.popularity > 0)
              SizedBox(
                width: 50,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: t.popularity / 100,
                          backgroundColor: AppTheme.edge.withValues(alpha: 0.4),
                          valueColor: AlwaysStoppedAnimation(AppTheme.cyan.withValues(alpha: 0.7)),
                          minHeight: 4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('${t.popularity}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            // Play
            if (t.spotifyUrl.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, color: Color(0xFF1DB954), size: 22),
                onPressed: () async {
                  final uri = Uri.tryParse(t.spotifyUrl);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Play on Spotify',
              ),
          ],
        ),
      ),
    );
  }
}

// View tab widget
class _ViewTab extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  const _ViewTab({required this.label, required this.subtitle, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.violet.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.violet.withValues(alpha: 0.3) : AppTheme.edge.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: isActive ? AppTheme.violet : AppTheme.textSecondary, fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isActive ? AppTheme.violet : AppTheme.textTertiary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(subtitle, style: TextStyle(color: isActive ? AppTheme.violet : AppTheme.textTertiary, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTrackRow extends StatefulWidget {
  final Track track;
  final int rank;
  final bool isSelected;
  final VoidCallback onToggleSelect;

  const _CatalogTrackRow({
    required this.track,
    required this.rank,
    required this.isSelected,
    required this.onToggleSelect,
  });

  @override
  State<_CatalogTrackRow> createState() => _CatalogTrackRowState();
}

class _CatalogTrackRowState extends State<_CatalogTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppTheme.violet.withValues(alpha: 0.08)
              : _hovered
                  ? AppTheme.panelRaised
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: widget.isSelected
              ? Border.all(color: AppTheme.violet.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: widget.onToggleSelect,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: widget.isSelected ? AppTheme.violet : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.isSelected ? AppTheme.violet : AppTheme.edge,
                    width: 1.5,
                  ),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Rank
            SizedBox(
              width: 28,
              child: Text(
                '${widget.rank}',
                style: TextStyle(
                  color: widget.rank <= 3 ? AppTheme.amber : AppTheme.textTertiary,
                  fontWeight: widget.rank <= 3 ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: t.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: t.artworkUrl, width: 44, height: 44, fit: BoxFit.cover, errorWidget: (_, e, s) => _SmallArtPlaceholder())
                  : _SmallArtPlaceholder(),
            ),
            const SizedBox(width: 14),
            // Title + genre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
            // BPM
            SizedBox(
              width: 55,
              child: Text('${t.bpm} BPM', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 10),
            // Key
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(5)),
              child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            // Region
            Text(t.leadRegion, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            const SizedBox(width: 12),
            // Score
            SizedBox(
              width: 36,
              child: Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 14), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 8),
            // Play
            if (_bestUrl(t) != null)
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, color: AppTheme.cyan, size: 22),
                onPressed: () async {
                  final uri = Uri.tryParse(_bestUrl(t)!);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Play',
              ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _FilterDropdown({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isDense: true,
              dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  final bool large;
  const _AvatarFallback({required this.name, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: large ? double.infinity : 100,
      height: large ? double.infinity : 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.violet.withValues(alpha: 0.3), AppTheme.pink.withValues(alpha: 0.2)],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: AppTheme.violet, fontSize: large ? 48 : 36, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SmallArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppTheme.edge,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16),
    );
  }
}

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}
