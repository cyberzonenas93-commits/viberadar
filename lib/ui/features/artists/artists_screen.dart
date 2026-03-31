import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/artist_model.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/artist_service.dart';
import '../../../services/set_builder_service.dart';
import '../../../services/apple_music_artist_service.dart';
import '../../../services/spotify_artist_service.dart';
import '../../widgets/source_badges.dart';

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
// Unified track model — may exist on Spotify, Apple Music, or both
// ─────────────────────────────────────────────────────────────────────────────

/// A track that may exist on Spotify, Apple Music, or both.
class _UnifiedTrack {
  final String name;
  final String artist;
  final String albumName;
  final String? artworkUrl;
  final int durationMs;
  final String? releaseDate;
  // Spotify fields
  final String? spotifyId;
  final String? spotifyUrl;
  final int popularity;
  final int trackNumber;
  final bool isTopTrack;
  // Apple Music fields
  final String? appleId;
  final String? appleUrl;
  final String? previewUrl;

  const _UnifiedTrack({
    required this.name,
    this.artist = '',
    required this.albumName,
    this.artworkUrl,
    this.durationMs = 0,
    this.releaseDate,
    this.spotifyId,
    this.spotifyUrl,
    this.popularity = 0,
    this.trackNumber = 0,
    this.isTopTrack = false,
    this.appleId,
    this.appleUrl,
    this.previewUrl,
  });

  bool get onSpotify => spotifyId != null;
  bool get onApple => appleId != null;
  bool get onBoth => onSpotify && onApple;
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
  ArtistModel? _openedArtistModel;

  List<SpotifyArtistResult> _spotifyResults = [];
  bool _searchingSpotify = false;

  final _artistService = ArtistService();
  final _spotifyService = SpotifyArtistService();

  Future<void> _searchSpotify(String query) async {
    if (query.length < 2) {
      if (mounted) setState(() { _spotifyResults = []; _searchingSpotify = false; });
      return;
    }
    if (mounted) setState(() => _searchingSpotify = true);
    try {
      final results = await _spotifyService.searchArtistsByName(query);
      if (mounted) setState(() { _spotifyResults = results; _searchingSpotify = false; });
    } catch (_) {
      if (mounted) setState(() { _spotifyResults = []; _searchingSpotify = false; });
    }
  }

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
        artistModel: _openedArtistModel,
        onBack: () => setState(() {
          _openedArtist = null;
          _openedArtistModel = null;
        }),
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
      spotifyResults: _spotifyResults,
      searchingSpotify: _searchingSpotify,
      onSearchChanged: (v) {
        setState(() => _search = v);
        _searchSpotify(v);
      },
      onGenreChanged: (v) => setState(() => _filterGenre = v),
      onRegionChanged: (v) => setState(() => _filterRegion = v),
      onArtistTapped: (artist) {
        final model = _artistService.getArtist(artist.name, allTracks);
        setState(() {
          _openedArtist = artist;
          _openedArtistModel = model;
        });
      },
      onSpotifyArtistTapped: (result) {
        final artist = _ArtistInfo(
          name: result.name,
          topGenre: result.genres.firstOrNull ?? 'Unknown',
          topRegion: 'Global',
          avgTrendScore: result.popularity / 100.0,
          trackCount: 0,
          artworkUrl: result.imageUrl,
          spotifyUrl: null,
          tracks: const [],
        );
        setState(() {
          _openedArtist = artist;
          _openedArtistModel = null;
        });
      },
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
  final List<SpotifyArtistResult> spotifyResults;
  final bool searchingSpotify;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onGenreChanged;
  final ValueChanged<String> onRegionChanged;
  final ValueChanged<_ArtistInfo> onArtistTapped;
  final ValueChanged<SpotifyArtistResult> onSpotifyArtistTapped;

  const _ArtistGridScreen({
    required this.artists,
    required this.allTracks,
    required this.search,
    required this.filterGenre,
    required this.filterRegion,
    required this.allGenres,
    required this.allRegions,
    required this.spotifyResults,
    required this.searchingSpotify,
    required this.onSearchChanged,
    required this.onGenreChanged,
    required this.onRegionChanged,
    required this.onArtistTapped,
    required this.onSpotifyArtistTapped,
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
                    maxLines: 1, overflow: TextOverflow.ellipsis,
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
          child: CustomScrollView(
            slivers: [
              if (artists.isEmpty && spotifyResults.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('No artists found', style: TextStyle(color: AppTheme.textTertiary))),
                )
              else ...[
                if (artists.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        childAspectRatio: 0.78,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _ArtistCard(
                          artist: artists[i],
                          onTap: () => onArtistTapped(artists[i]),
                        ),
                        childCount: artists.length,
                      ),
                    ),
                  ),
                if (spotifyResults.isNotEmpty || searchingSpotify) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: Color(0xFF1DB954), size: 16),
                          const SizedBox(width: 8),
                          const Text('Discover on Spotify', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                          if (searchingSpotify) ...[
                            const SizedBox(width: 10),
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1DB954))),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (spotifyResults.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 200,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _SpotifyArtistCard(
                            result: spotifyResults[i],
                            onTap: () => onSpotifyArtistTapped(spotifyResults[i]),
                          ),
                          childCount: spotifyResults.length,
                        ),
                      ),
                    ),
                ],
              ],
            ],
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
                        Flexible(child: Text(a.topGenre, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 4),
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
// Spotify global search artist card
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyArtistCard extends StatelessWidget {
  const _SpotifyArtistCard({required this.result, required this.onTap});
  final SpotifyArtistResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: result.imageUrl != null
                    ? CachedNetworkImage(imageUrl: result.imageUrl!, fit: BoxFit.cover, width: double.infinity)
                    : Container(color: AppTheme.panelRaised, child: const Icon(Icons.person_rounded, color: AppTheme.textTertiary, size: 48)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (result.genres.isNotEmpty)
                    Text(result.genres.first, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1DB954).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Spotify', style: TextStyle(color: Color(0xFF1DB954), fontSize: 9, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
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
                    Text(a.name, style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
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
// Grid card for Spotify catalogue tracks
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyTrackCard extends ConsumerStatefulWidget {
  final SpotifyTrackInfo track;
  final int rank;
  const _SpotifyTrackCard({required this.track, required this.rank});

  @override
  ConsumerState<_SpotifyTrackCard> createState() => _SpotifyTrackCardState();
}

class _SpotifyTrackCardState extends ConsumerState<_SpotifyTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.name, t.artists);
          if (!played && t.spotifyUrl.isNotEmpty) {
            final uri = Uri.tryParse(t.spotifyUrl);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: t.isTopTrack
                  ? AppTheme.amber.withValues(alpha: _hovered ? 0.5 : 0.3)
                  : AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
            ),
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
                        child: t.albumArt != null
                            ? CachedNetworkImage(imageUrl: t.albumArt!, fit: BoxFit.cover, errorWidget: (_, e, s) => _SmallArtPlaceholder())
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised]),
                                ),
                                child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
                              ),
                      ),
                    ),
                    if (t.isTopTrack)
                      Positioned(
                        top: 8, left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: Colors.white, size: 10),
                              SizedBox(width: 3),
                              Text('TOP', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    if (t.popularity > 0)
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.cyan.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('${t.popularity}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954), shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: const Color(0xFF1DB954).withValues(alpha: 0.5), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.albumName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(t.durationFormatted, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const Spacer(),
                        if (t.releaseDate != null && t.releaseDate!.length >= 4)
                          Text(t.releaseDate!.substring(0, 4), style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
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

// Grid card for radar tracks
class _RadarTrackCard extends ConsumerStatefulWidget {
  final Track track;
  final int rank;
  const _RadarTrackCard({required this.track, required this.rank});

  @override
  ConsumerState<_RadarTrackCard> createState() => _RadarTrackCardState();
}

class _RadarTrackCardState extends ConsumerState<_RadarTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist);
          if (!played) {
            final url = _bestUrl(t);
            if (url != null) {
              final uri = Uri.tryParse(url);
              if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
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
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: t.artworkUrl, fit: BoxFit.cover, errorWidget: (_, e, s) => _SmallArtPlaceholder())
                            : Container(
                                decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised])),
                                child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
                              ),
                      ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(5)),
                        child: Text('$score', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan, shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text('${t.bpm}', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                          child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Flexible(child: SourceBadges(sources: t.effectiveSources, compact: true)),
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

// Keep old _SpotifyTrackRow for compatibility but it's no longer used
class _SpotifyTrackRow extends ConsumerStatefulWidget {
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
  ConsumerState<_SpotifyTrackRow> createState() => _SpotifyTrackRowState();
}

class _SpotifyTrackRowState extends ConsumerState<_SpotifyTrackRow> {
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
                  final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.name, t.artists);
                  if (!played) {
                    final uri = Uri.tryParse(t.spotifyUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
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
        final set = svc.buildSetSync(
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

class _AppleMusicTrackCard extends ConsumerStatefulWidget {
  final AppleMusicTrack track;
  final int rank;
  const _AppleMusicTrackCard({required this.track, required this.rank});

  @override
  ConsumerState<_AppleMusicTrackCard> createState() => _AppleMusicTrackCardState();
}

class _AppleMusicTrackCardState extends ConsumerState<_AppleMusicTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    const appleRed = Color(0xFFFC3C44);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.name, t.artistName);
          if (!played && t.appleUrl != null) {
            final uri = Uri.tryParse(t.appleUrl!);
            if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
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
                        child: t.artworkUrl != null
                            ? Image.network(t.artworkUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, e, s) => _ArtworkPlaceholder())
                            : _ArtworkPlaceholder(),
                      ),
                    ),
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                        child: Text('#${widget.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10)),
                      ),
                    ),
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: appleRed.withValues(alpha: 0.9), shape: BoxShape.circle),
                        child: const Icon(Icons.apple_rounded, color: Colors.white, size: 12),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: appleRed, shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: appleRed.withValues(alpha: 0.5), blurRadius: 16)],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(t.albumName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(t.durationFormatted, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
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

class _UnifiedTrackCard extends ConsumerStatefulWidget {
  const _UnifiedTrackCard({required this.track, required this.rank});
  final _UnifiedTrack track;
  final int rank;

  @override
  ConsumerState<_UnifiedTrackCard> createState() => _UnifiedTrackCardState();
}

class _UnifiedTrackCardState extends ConsumerState<_UnifiedTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final am = ref.watch(appleMusicProvider);
    final isPlaying = am.currentTrack?.title == t.name &&
        am.currentTrack?.artist == t.artist &&
        am.isPlaying;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.name, t.artist);
          if (!played) {
            final url = t.appleUrl ?? t.spotifyUrl;
            if (url != null) {
              final uri = Uri.tryParse(url);
              if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isPlaying
                ? const Color(0xFFFC3C44).withValues(alpha: 0.5)
                : AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: SizedBox.expand(
                        child: t.artworkUrl != null
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (context, error, stack) => _ArtworkPlaceholder(),
                              )
                            : _ArtworkPlaceholder(),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('#${widget.rank}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    // Platform badges
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t.onSpotify)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                            ),
                          if (t.onSpotify && t.onApple) const SizedBox(width: 3),
                          if (t.onApple)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFC3C44),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('A', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                    if (t.isTopTrack)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('TOP', style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    // Play overlay on hover or active
                    if (_hovered || isPlaying)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.violet,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: (isPlaying ? const Color(0xFFFC3C44) : AppTheme.violet).withValues(alpha: 0.5),
                                  blurRadius: 16,
                                )],
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: TextStyle(
                        color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.albumName,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _ArtworkPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.edge, AppTheme.panelRaised]),
      ),
      child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
    );
  }
}

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

class _CatalogTrackRow extends ConsumerStatefulWidget {
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
  ConsumerState<_CatalogTrackRow> createState() => _CatalogTrackRowState();
}

class _CatalogTrackRowState extends ConsumerState<_CatalogTrackRow> {
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
                  Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  final played = await ref.read(appleMusicProvider.notifier).playByQuery(t.title, t.artist);
                  if (!played) {
                    final uri = Uri.tryParse(_bestUrl(t)!);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
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

/// Merge Spotify and Apple Music track lists into a single deduplicated list.
/// Tracks with matching names (case-insensitive) are combined into one entry.
List<_UnifiedTrack> _mergeToUnified(
  List<SpotifyTrackInfo> spotifyTracks,
  List<AppleMusicTrack> appleTracks,
) {
  final unified = <String, _UnifiedTrack>{};

  // Add Spotify tracks first
  for (final t in spotifyTracks) {
    final key = t.name.toLowerCase().trim();
    unified[key] = _UnifiedTrack(
      name: t.name,
      artist: t.artists,
      albumName: t.albumName,
      artworkUrl: t.albumArt,
      durationMs: t.durationMs,
      releaseDate: t.releaseDate,
      spotifyId: t.id,
      spotifyUrl: t.spotifyUrl,
      popularity: t.popularity,
      trackNumber: t.trackNumber,
      isTopTrack: t.isTopTrack,
    );
  }

  // Merge in Apple Music tracks
  for (final t in appleTracks) {
    final key = t.name.toLowerCase().trim();
    final existing = unified[key];
    if (existing != null) {
      // Enrich Spotify entry with Apple data
      unified[key] = _UnifiedTrack(
        name: existing.name,
        artist: existing.artist.isNotEmpty ? existing.artist : t.artistName,
        albumName: existing.albumName,
        artworkUrl: existing.artworkUrl ?? t.artworkUrl,
        durationMs: existing.durationMs > 0 ? existing.durationMs : t.durationMs,
        releaseDate: existing.releaseDate ?? t.releaseDate,
        spotifyId: existing.spotifyId,
        spotifyUrl: existing.spotifyUrl,
        popularity: existing.popularity,
        trackNumber: existing.trackNumber,
        isTopTrack: existing.isTopTrack,
        appleId: t.id,
        appleUrl: t.appleUrl,
        previewUrl: t.previewUrl,
      );
    } else {
      // Apple-only track
      unified[key] = _UnifiedTrack(
        name: t.name,
        artist: t.artistName,
        albumName: t.albumName,
        artworkUrl: t.artworkUrl,
        durationMs: t.durationMs,
        releaseDate: t.releaseDate,
        appleId: t.id,
        appleUrl: t.appleUrl,
        previewUrl: t.previewUrl,
      );
    }
  }

  return unified.values.toList();
}
