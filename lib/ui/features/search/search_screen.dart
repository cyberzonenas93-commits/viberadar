import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../providers/app_state.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/apple_music_artist_service.dart';
import '../../../services/spotify_artist_service.dart';
import '../../../services/youtube_search_service.dart';

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
  final int bpm;
  final String keySignature;

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
    this.bpm = 0,
    this.keySignature = '',
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
      bpm: bpm,
      keySignature: keySignature,
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
        _youtube.searchMusic(q, limit: 5).catchError((_) => <YoutubeVideoResult>[]),
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
                  topTracks: topTracks.take(200).toList(),
                  onSearch: (q) {
                    _controller.text = q;
                    _onQueryChanged(q);
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

// ── Discovery (no query) ──────────────────────────────────────────────────────

class _DiscoveryView extends StatelessWidget {
  const _DiscoveryView({required this.topTracks, required this.onSearch});
  final List<Track> topTracks;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final trending = topTracks.take(100).toList();
    final recent = [...topTracks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentTop = recent.take(100).toList();

    final genres = <String>[
      'Afrobeats', 'Amapiano', 'Hip-Hop', 'House', 'R&B',
      'Dancehall', 'Drill', 'Dance', 'Latin', 'UK Garage',
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          sliver: SliverToBoxAdapter(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: genres.map((g) => _GenreChip(label: g, onTap: () => onSearch(g))).toList(),
            ),
          ),
        ),

        if (trending.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  _SectionLabel(icon: Icons.local_fire_department_rounded, color: AppTheme.amber, label: 'Trending Now'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                    child: Text('${trending.length}', style: const TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _FirestoreTrackCard(track: trending[i], rank: i + 1),
                childCount: trending.length,
              ),
            ),
          ),
        ],

        if (recentTop.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  _SectionLabel(icon: Icons.new_releases_rounded, color: AppTheme.cyan, label: 'Hot This Week'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                    child: Text('${recentTop.length}', style: const TextStyle(color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _FirestoreTrackCard(track: recentTop[i]),
                childCount: recentTop.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
          ),
          child: Text(label, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _FirestoreTrackCard extends ConsumerStatefulWidget {
  const _FirestoreTrackCard({required this.track, this.rank});
  final Track track;
  final int? rank;

  @override
  ConsumerState<_FirestoreTrackCard> createState() => _FirestoreTrackCardState();
}

class _FirestoreTrackCardState extends ConsumerState<_FirestoreTrackCard> {
  bool _hovered = false;

  void _play() {
    ref.read(appleMusicProvider.notifier).playByQuery(widget.track.title, widget.track.artist);
  }

  @override
  Widget build(BuildContext context) {
    final am = ref.watch(appleMusicProvider);
    final isPlaying = am.currentTrack?.title == widget.track.title &&
        am.currentTrack?.artist == widget.track.artist &&
        am.isPlaying;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _play,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 130,
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                      child: SizedBox.expand(
                        child: widget.track.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: widget.track.artworkUrl, fit: BoxFit.cover)
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppTheme.edge, AppTheme.panelRaised],
                                  ),
                                ),
                                child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 28),
                              ),
                      ),
                    ),
                    if (widget.rank != null)
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('#${widget.rank}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    // Play overlay on hover
                    if (_hovered || isPlaying)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                          ),
                          child: Center(
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isPlaying ? const Color(0xFFFC3C44) : AppTheme.cyan).withValues(alpha: 0.5),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      style: TextStyle(
                        color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(widget.track.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
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

// ── Search results list ───────────────────────────────────────────────────────

class _ResultsList extends ConsumerWidget {
  const _ResultsList({
    required this.results,
    required this.youtubeResults,
    required this.query,
  });
  final List<_SearchResult> results;
  final List<YoutubeVideoResult> youtubeResults;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = results.length + youtubeResults.length;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          sliver: SliverToBoxAdapter(
            child: Text('$totalCount results for "$query"',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ),
        ),
        // Spotify + Apple Music grid
        if (results.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            sliver: SliverToBoxAdapter(
              child: _ResultSectionLabel(label: 'Spotify & Apple Music', count: results.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ResultCard(result: results[i]),
                childCount: results.length,
              ),
            ),
          ),
        ],
        // YouTube grid
        if (youtubeResults.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            sliver: SliverToBoxAdapter(
              child: _ResultSectionLabel(label: 'YouTube', count: youtubeResults.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _YoutubeResultCard(video: youtubeResults[i]),
                childCount: youtubeResults.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultSectionLabel extends StatelessWidget {
  const _ResultSectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.panelRaised,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grid card for search results (matches trending/region/genre card style) ──

class _ResultCard extends ConsumerStatefulWidget {
  const _ResultCard({required this.result});
  final _SearchResult result;

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  bool _hovered = false;

  void _play(_SearchResult r) async {
    final played = await ref.read(appleMusicProvider.notifier).playByQuery(r.title, r.artist);
    if (!played && mounted) {
      final url = r.bestUrl;
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final am = ref.watch(appleMusicProvider);
    final isPlaying = am.currentTrack?.title == r.title &&
        am.currentTrack?.artist == r.artist &&
        am.isPlaying;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _play(r),
        onLongPress: () => _showTrackDetail(context, r),
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
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: r.artworkUrl != null
                            ? CachedNetworkImage(imageUrl: r.artworkUrl!, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _artPlaceholder())
                            : _artPlaceholder(),
                      ),
                    ),
                    // Source badges top-left
                    Positioned(
                      top: 8, left: 8,
                      child: Row(
                        children: [
                          if (r.hasSpotify) _SourceBadge(label: 'S', color: const Color(0xFF1ED760), tooltip: 'Spotify'),
                          if (r.hasSpotify && r.hasApple) const SizedBox(width: 4),
                          if (r.hasApple) _SourceBadge(label: 'A', color: const Color(0xFFFF7AB5), tooltip: 'Apple Music'),
                          if ((r.hasSpotify || r.hasApple) && r.hasYoutube) const SizedBox(width: 4),
                          if (r.hasYoutube) _SourceBadge(label: 'Y', color: const Color(0xFFFF0000), tooltip: 'YouTube'),
                        ],
                      ),
                    ),
                    // BPM badge top-right
                    if (r.bpm > 0)
                      Positioned(
                        top: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.cyan.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${r.bpm}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
                        ),
                      ),
                    // Play overlay on hover or active
                    if (_hovered || isPlaying)
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
                                color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(
                                  color: (isPlaying ? const Color(0xFFFC3C44) : AppTheme.cyan).withValues(alpha: 0.5),
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
              // Title + artist
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title, style: TextStyle(
                        color: isPlaying ? const Color(0xFFFC3C44) : AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(r.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (r.durationFormatted.isNotEmpty)
                          Text(r.durationFormatted, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        if (r.durationFormatted.isNotEmpty && r.keySignature.isNotEmpty) const SizedBox(width: 4),
                        if (r.keySignature.isNotEmpty && r.keySignature != '--')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                            child: Text(r.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                          ),
                        const Spacer(),
                        if (r.albumName.isNotEmpty)
                          Flexible(
                            child: Text(r.albumName, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.6), fontSize: 9),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
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

  Widget _artPlaceholder() => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised])),
    child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
  );

  void _showTrackDetail(BuildContext context, _SearchResult r) {
    showDialog(context: context, builder: (_) => _TrackDetailDialog(result: r));
  }
}

// ── YouTube result card (grid format) ──

class _YoutubeResultCard extends StatefulWidget {
  const _YoutubeResultCard({required this.video});
  final YoutubeVideoResult video;

  @override
  State<_YoutubeResultCard> createState() => _YoutubeResultCardState();
}

class _YoutubeResultCardState extends State<_YoutubeResultCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.tryParse(v.youtubeUrl);
          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hovered
                ? const Color(0xFFFF4B4B).withValues(alpha: 0.4)
                : AppTheme.edge.withValues(alpha: 0.35)),
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
                        child: v.thumbnailUrl != null
                            ? CachedNetworkImage(imageUrl: v.thumbnailUrl!, fit: BoxFit.cover)
                            : Container(color: AppTheme.panelRaised,
                                child: const Center(child: Icon(Icons.play_circle_outline_rounded, color: AppTheme.textTertiary, size: 32))),
                      ),
                    ),
                    Positioned(
                      top: 8, left: 8,
                      child: _SourceBadge(label: 'Y', color: const Color(0xFFFF0000), tooltip: 'YouTube'),
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
                              decoration: const BoxDecoration(color: Color(0xFFFF4B4B), shape: BoxShape.circle),
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
                    Text(v.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(v.channelName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
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

// Keep _ResultRow for backwards compatibility but unused
class _ResultRow extends ConsumerStatefulWidget {
  const _ResultRow({required this.result, required this.index});
  final _SearchResult result;
  final int index;

  @override
  ConsumerState<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends ConsumerState<_ResultRow> {
  bool _hovered = false;

  void _showTrackDetail(BuildContext context, _SearchResult r) {
    showDialog(
      context: context,
      builder: (_) => _TrackDetailDialog(result: r),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    return GestureDetector(
      onTap: () => _showTrackDetail(context, r),
      child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.5 : 0.3)),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Index number
            SizedBox(
              width: 28,
              child: Text(
                '${widget.index + 1}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                height: 48,
                child: r.artworkUrl != null
                    ? CachedNetworkImage(imageUrl: r.artworkUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _artPlaceholder())
                    : _artPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Title + artist + album
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(r.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (r.albumName.isNotEmpty)
                    Text(r.albumName, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // BPM + Key
            if (r.bpm > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${r.bpm}', style: const TextStyle(color: AppTheme.amber, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 4),
            ],
            if (r.keySignature.isNotEmpty && r.keySignature != '--') ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.edge.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(r.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
            ],
            // Duration
            if (r.durationFormatted.isNotEmpty)
              Text(r.durationFormatted, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
            const SizedBox(width: 12),
            // Source badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.hasSpotify) _SourceBadge(label: 'S', color: const Color(0xFF1ED760), tooltip: 'Spotify'),
                if (r.hasSpotify && (r.hasApple || r.hasYoutube)) const SizedBox(width: 4),
                if (r.hasApple) _SourceBadge(label: 'A', color: const Color(0xFFFF7AB5), tooltip: 'Apple Music'),
                if (r.hasApple && r.hasYoutube) const SizedBox(width: 4),
                if (r.hasYoutube) _SourceBadge(label: 'Y', color: const Color(0xFFFF0000), tooltip: 'YouTube'),
              ],
            ),
            const SizedBox(width: 12),
            // Action buttons
            if (_hovered) ...[
              // Play
              _ActionButton(
                icon: Icons.play_circle_rounded,
                color: AppTheme.cyan,
                tooltip: r.hasSpotify ? 'Open in Spotify' : 'Open in Apple Music',
                onTap: () => _play(r),
              ),
              const SizedBox(width: 6),
              // Add to crate
              _ActionButton(
                icon: Icons.playlist_add_rounded,
                color: AppTheme.violet,
                tooltip: 'Add to Crate',
                onTap: () => _showAddToCrate(r),
              ),
            ] else
              const SizedBox(width: 68),
          ],
        ),
      ),
      ),
    );
  }

  Widget _artPlaceholder() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.edge, AppTheme.panelRaised],
      ),
    ),
    child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 20),
  );

  void _play(_SearchResult r) async {
    final played = await ref.read(appleMusicProvider.notifier).playByQuery(r.title, r.artist);
    if (!played) {
      final url = r.bestUrl;
      if (url.isEmpty) return;
      final uri = Uri.tryParse(url);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAddToCrate(_SearchResult r) {
    final crateState = ref.read(crateProvider);
    final crates = crateState.crates.keys.toList();
    final trackId = r.hasSpotify ? 'spotify:${r.title}:${r.artist}' : 'apple:${r.title}:${r.artist}';

    showDialog(
      context: context,
      builder: (ctx) => _AddToCrateDialog(
        trackTitle: r.title,
        crates: crates,
        onAddToCrate: (name) {
          ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${r.title}" to $name'),
              backgroundColor: AppTheme.violet,
              duration: const Duration(seconds: 2),
            ),
          );
        },
        onNewCrate: (name) {
          ref.read(crateProvider.notifier).createCrate(name);
          ref.read(crateProvider.notifier).addTrackToCrate(name, trackId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Created crate "$name" and added "${r.title}"'),
              backgroundColor: AppTheme.violet,
              duration: const Duration(seconds: 2),
            ),
          );
        },
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color, required this.tooltip});
  final String label;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.color, required this.tooltip, required this.onTap});
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 31, height: 31,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}

class _AddToCrateDialog extends StatefulWidget {
  const _AddToCrateDialog({
    required this.trackTitle,
    required this.crates,
    required this.onAddToCrate,
    required this.onNewCrate,
  });
  final String trackTitle;
  final List<String> crates;
  final void Function(String name) onAddToCrate;
  final void Function(String name) onNewCrate;

  @override
  State<_AddToCrateDialog> createState() => _AddToCrateDialogState();
}

class _AddToCrateDialogState extends State<_AddToCrateDialog> {
  final _newCrateCtrl = TextEditingController();
  bool _creatingNew = false;

  @override
  void dispose() {
    _newCrateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 20),
                const SizedBox(width: 8),
                const Text('Add to Crate', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text('"${widget.trackTitle}"', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),

            if (widget.crates.isEmpty && !_creatingNew)
              const Text('No crates yet — create one below.', style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),

            if (widget.crates.isNotEmpty && !_creatingNew) ...[
              const Text('EXISTING CRATES', style: TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              ...widget.crates.map((name) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded, color: AppTheme.violet, size: 18),
                title: Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                onTap: () {
                  widget.onAddToCrate(name);
                  Navigator.of(context).pop();
                },
              )),
              const Divider(color: AppTheme.edge, height: 20),
            ],

            if (_creatingNew) ...[
              TextField(
                controller: _newCrateCtrl,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'New crate name...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: AppTheme.panelRaised,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.edge)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.edge)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.violet)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  widget.onNewCrate(v.trim());
                  Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _creatingNew = false),
                    child: const Text('Back', style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final name = _newCrateCtrl.text.trim();
                      if (name.isEmpty) return;
                      widget.onNewCrate(name);
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.violet),
                    child: const Text('Create & Add'),
                  ),
                ],
              ),
            ] else
              TextButton.icon(
                onPressed: () => setState(() => _creatingNew = true),
                icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.violet),
                label: const Text('New Crate', style: TextStyle(color: AppTheme.violet)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Track Detail Dialog ─────────────────────────────────────────────────────

class _TrackDetailDialog extends ConsumerWidget {
  const _TrackDetailDialog({required this.result});
  final _SearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art hero
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: SizedBox(
                height: 280,
                width: double.infinity,
                child: r.artworkUrl != null
                    ? CachedNetworkImage(imageUrl: r.artworkUrl!, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder())
                    : _placeholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(r.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  if (r.albumName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(r.albumName, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                  ],
                  const SizedBox(height: 16),
                  // Metadata pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (r.bpm > 0) _Pill('${r.bpm} BPM', AppTheme.amber),
                      if (r.keySignature.isNotEmpty && r.keySignature != '--') _Pill(r.keySignature, AppTheme.cyan),
                      if (r.durationFormatted.isNotEmpty) _Pill(r.durationFormatted, AppTheme.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Platform buttons
                  Row(
                    children: [
                      if (r.hasSpotify)
                        _PlatformButton(label: 'Spotify', color: const Color(0xFF1ED760), icon: Icons.graphic_eq_rounded, url: r.spotifyUrl!),
                      if (r.hasSpotify && r.hasApple) const SizedBox(width: 8),
                      if (r.hasApple)
                        _PlatformButton(label: 'Apple Music', color: const Color(0xFFFF7AB5), icon: Icons.music_note_rounded, url: r.appleUrl!,
                          onTap: () => ref.read(appleMusicProvider.notifier).playByQuery(r.title, r.artist)),
                      if ((r.hasSpotify || r.hasApple) && r.hasYoutube) const SizedBox(width: 8),
                      if (r.hasYoutube)
                        _PlatformButton(label: 'YouTube', color: const Color(0xFFFF0000), icon: Icons.play_circle_fill_rounded, url: r.youtubeUrl!),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Close button
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close', style: TextStyle(color: AppTheme.textSecondary)),
                    ),
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

  Widget _placeholder() => Container(
    color: AppTheme.panelRaised,
    child: const Center(child: Icon(Icons.album_rounded, color: AppTheme.textTertiary, size: 64)),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _PlatformButton extends StatelessWidget {
  const _PlatformButton({required this.label, required this.color, required this.icon, required this.url, this.onTap});
  final String label;
  final Color color;
  final IconData icon;
  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap ?? () {
            final uri = Uri.tryParse(url);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
