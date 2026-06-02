import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/artist_model.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/artist_service.dart';
import '../../../services/set_builder_service.dart';
import '../../../services/apple_music_artist_service.dart';
import '../../../services/spotify_artist_service.dart';
import '../../widgets/source_badges.dart';

part 'artists_screen_grid.dart';
part 'artists_screen_cards.dart';
part 'artists_screen_detail.dart';
part 'artists_screen_helpers.dart';

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
