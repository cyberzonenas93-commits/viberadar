import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../services/apple_music_artist_service.dart';
import '../../../services/spotify_artist_service.dart';
import '../../../services/youtube_search_service.dart';

part 'search_screen_results.dart';
part 'search_screen_widgets.dart';

// ── Unified search result model ───────────────────────────────────────────────

class _SearchResult {
  final String title;
  final String artist;
  final String albumName;
  final String? artworkUrl;
  final int durationMs;
  final String? spotifyUrl;
  final String? appleUrl;
  final String? applePreviewUrl;
  final String? youtubeUrl;
  final int popularity;

  const _SearchResult({
    required this.title,
    required this.artist,
    required this.albumName,
    this.artworkUrl,
    this.durationMs = 0,
    this.spotifyUrl,
    this.appleUrl,
    this.applePreviewUrl,
    this.youtubeUrl,
    this.popularity = 0,
  });

  bool get hasSpotify => spotifyUrl != null && spotifyUrl!.isNotEmpty;
  bool get hasApple => appleUrl != null && appleUrl!.isNotEmpty;
  bool get hasYoutube => youtubeUrl != null && youtubeUrl!.isNotEmpty;

  String get durationFormatted {
    if (durationMs == 0) return '';
    final m = durationMs ~/ 60000;
    final s = (durationMs % 60000) ~/ 1000;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get bestUrl => spotifyUrl ?? appleUrl ?? youtubeUrl ?? '';

  _SearchResult mergeApple(AppleMusicTrack apple) {
    return _SearchResult(
      title: title,
      artist: artist,
      albumName: albumName,
      artworkUrl: artworkUrl ?? apple.artworkUrl,
      durationMs: durationMs > 0 ? durationMs : apple.durationMs,
      spotifyUrl: spotifyUrl,
      appleUrl: apple.appleUrl,
      applePreviewUrl: apple.previewUrl,
      youtubeUrl: youtubeUrl,
      popularity: popularity,
    );
  }

  static String _key(String title, String artist) =>
      '${title.toLowerCase().trim()}::${artist.toLowerCase().trim()}';

  String get key => _key(title, artist);

  static List<_SearchResult> merge(
    List<SpotifyTrackInfo> spotify,
    List<AppleMusicTrack> apple,
  ) {
    final map = <String, _SearchResult>{};

    for (final t in spotify) {
      final r = _SearchResult(
        title: t.name,
        artist: t.artists,
        albumName: t.albumName,
        artworkUrl: t.albumArt,
        durationMs: t.durationMs,
        spotifyUrl: t.spotifyUrl,
        popularity: t.popularity,
      );
      map[r.key] = r;
    }

    for (final t in apple) {
      final k = _key(t.name, t.artistName);
      if (map.containsKey(k)) {
        map[k] = map[k]!.mergeApple(t);
      } else {
        map[k] = _SearchResult(
          title: t.name,
          artist: t.artistName,
          albumName: t.albumName,
          artworkUrl: t.artworkUrl,
          durationMs: t.durationMs,
          appleUrl: t.appleUrl,
          applePreviewUrl: t.previewUrl,
        );
      }
    }

    final results = map.values.toList();
    results.sort((a, b) => b.popularity.compareTo(a.popularity));
    return results;
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _spotify = SpotifyArtistService();
  final _apple = AppleMusicArtistService();
  final _youtube = YoutubeSearchService();
  final _controller = TextEditingController();
  final _focus = FocusNode();

  String _query = '';
  bool _searching = false;
  List<_SearchResult> _results = [];
  List<YoutubeVideoResult> _youtubeResults = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search bar
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() { _results = []; _youtubeResults = []; _searching = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value.trim()));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final results = await Future.wait([
        _spotify.searchTracks(q, limit: 20).catchError((_) => <SpotifyTrackInfo>[]),
        _apple.searchSongs(q, limit: 20).catchError((_) => <AppleMusicTrack>[]),
        _youtube.searchMusic(q, limit: 12).catchError((_) => <YoutubeVideoResult>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _results = _SearchResult.merge(
          results[0] as List<SpotifyTrackInfo>,
          results[1] as List<AppleMusicTrack>,
        );
        _youtubeResults = results[2] as List<YoutubeVideoResult>;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracksAsync = ref.watch(trackStreamProvider);
    final allTracks = tracksAsync.value ?? [];
    final topTracks = [...allTracks]
      ..sort((a, b) => b.trendScore.compareTo(a.trendScore));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header + search bar ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.search_rounded, color: AppTheme.cyan, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Search',
                    style: theme.textTheme.headlineSmall?.copyWith(color: AppTheme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Search across Spotify, Apple Music and more',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onQueryChanged,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Song title, artist, album...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 18),
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.cyan, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Body ─────────────────────────────────────────────────────────────
        Expanded(
          child: _query.isEmpty
              ? _DiscoveryView(
                  topTracks: topTracks.take(40).toList(),
                  onGenreSearch: (g) {
                    _controller.text = g;
                    _controller.selection =
                        TextSelection.collapsed(offset: g.length);
                    setState(() => _query = g);
                    _search(g);
                  },
                )
              : _searching && _results.isEmpty && _youtubeResults.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2),
                          SizedBox(height: 16),
                          Text('Searching Spotify, Apple Music, YouTube...', style: TextStyle(color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : _results.isEmpty && _youtubeResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.music_off_rounded, color: AppTheme.textTertiary, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No results for "$_query"',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : _ResultsList(
                          results: _results,
                          youtubeResults: _youtubeResults,
                          query: _query,
                        ),
        ),
      ],
    );
  }
}
