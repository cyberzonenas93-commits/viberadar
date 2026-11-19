import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/music_genres.dart';
import '../../core/theme/app_theme.dart';
import '../../models/track.dart';
import '../../services/platform_search_service.dart';
import '../widgets/add_to_setlist_sheet.dart';

// ---------------------------------------------------------------------------
// Provider — injectable so tests can override with a fake
// ---------------------------------------------------------------------------

final platformSearchServiceProvider = Provider<PlatformSearchService>(
  (ref) => PlatformSearchService(),
);

// ---------------------------------------------------------------------------
// SearchTab widget
// ---------------------------------------------------------------------------

class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  bool _searching = false;
  List<PlatformTrackResult> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Query handling ──────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      if (value.trim().isEmpty) {
        _results = [];
        _searching = false;
      }
    });

    if (value.trim().isEmpty) return;

    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(value.trim()),
    );
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _searching = true);
    try {
      final service = ref.read(platformSearchServiceProvider);
      final results = await service.searchMusicPlatforms(q, limit: 30);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(
          controller: _controller,
          query: _query,
          onChanged: _onQueryChanged,
          onClear: () {
            _controller.clear();
            _onQueryChanged('');
          },
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_query.trim().isEmpty) {
      return const _HintView();
    }
    if (_searching && _results.isEmpty) {
      return const _LoadingView();
    }
    if (_results.isEmpty) {
      return _NoResultsView(query: _query);
    }
    return _ResultsList(results: _results);
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Song title, artist, album…',
          hintStyle: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppTheme.textTertiary,
            size: 20,
          ),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textTertiary,
                    size: 18,
                  ),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: AppTheme.panel.withValues(alpha: 0.82),
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
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 16,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State views
// ---------------------------------------------------------------------------

class _HintView extends StatelessWidget {
  const _HintView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 48),
          SizedBox(height: 16),
          Text(
            'Search Apple Music, Spotify, YouTube Music, Deezer',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.cyan, strokeWidth: 2),
          SizedBox(height: 16),
          Text(
            'Searching…',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _NoResultsView extends StatelessWidget {
  const _NoResultsView({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.music_off_rounded,
            color: AppTheme.textTertiary,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No results for "$query"',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results list
// ---------------------------------------------------------------------------

class _ResultsList extends ConsumerWidget {
  const _ResultsList({required this.results});
  final List<PlatformTrackResult> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      itemCount: results.length,
      itemBuilder: (ctx, i) => _ResultRow(result: results[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual result row
// ---------------------------------------------------------------------------

class _ResultRow extends ConsumerWidget {
  const _ResultRow({required this.result});
  final PlatformTrackResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final hasSpotify = r.spotifyUrl != null && r.spotifyUrl!.isNotEmpty;
    final hasApple = r.appleUrl != null && r.appleUrl!.isNotEmpty;
    final hasYoutube = r.youtubeUrl != null && r.youtubeUrl!.isNotEmpty;
    final hasDeezer = r.deezerUrl != null && r.deezerUrl!.isNotEmpty;
    final track = _trackFromSearchResult(r);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.panel.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showAddToSetlistSheet(context, ref, track),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Artwork
                _Artwork(url: r.artworkUrl),
                const SizedBox(width: 12),

                // Title + artist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.artist,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // "Open in…" icon buttons for each present URL
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    runAlignment: WrapAlignment.end,
                    children: [
                      if (hasSpotify)
                        _OpenInButton(
                          url: r.spotifyUrl!,
                          icon: Icons.queue_music_rounded,
                          color: const Color(0xFF1ED760),
                          tooltip: 'Play on Spotify',
                        ),
                      if (hasApple)
                        _OpenInButton(
                          url: r.appleUrl!,
                          icon: Icons.music_note_rounded,
                          color: const Color(0xFFFF7AB5),
                          tooltip: 'Play on Apple Music',
                        ),
                      if (hasYoutube)
                        _OpenInButton(
                          url: r.youtubeUrl!,
                          icon: Icons.play_circle_rounded,
                          color: const Color(0xFFFF0000),
                          tooltip: 'Play on YouTube Music',
                        ),
                      if (hasDeezer)
                        _OpenInButton(
                          url: r.deezerUrl!,
                          icon: Icons.headphones_rounded,
                          color: const Color(0xFFA238FF),
                          tooltip: 'Play on Deezer',
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const Key('search_result_add_to_setlist'),
                  icon: const Icon(
                    Icons.playlist_add_rounded,
                    color: AppTheme.violet,
                    size: 22,
                  ),
                  tooltip: 'Add to setlist',
                  onPressed: () => showAddToSetlistSheet(context, ref, track),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Track _trackFromSearchResult(PlatformTrackResult result) {
  final now = DateTime.now();
  final links = <String, String>{
    if (result.spotifyUrl?.isNotEmpty == true) 'spotify': result.spotifyUrl!,
    if (result.appleUrl?.isNotEmpty == true) 'apple': result.appleUrl!,
    if (result.youtubeUrl?.isNotEmpty == true) 'youtube': result.youtubeUrl!,
    if (result.deezerUrl?.isNotEmpty == true) 'deezer': result.deezerUrl!,
  };
  final id = [
    'search',
    result.artist,
    result.title,
  ].join(':').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  return Track(
    id: id,
    title: result.title,
    artist: result.artist,
    artworkUrl: result.artworkUrl ?? '',
    bpm: 0,
    keySignature: '--',
    genre: canonicalGenre(result.genre),
    vibe: 'club',
    trendScore: result.trendScore,
    regionScores: const {},
    platformLinks: links,
    createdAt: now,
    updatedAt: now,
    energyLevel: 0.5,
    trendHistory: const [],
    sources: links.keys.toList(),
  );
}

// ---------------------------------------------------------------------------
// Artwork thumbnail
// ---------------------------------------------------------------------------

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(),
                errorWidget: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppTheme.panelRaised,
    child: const Icon(
      Icons.music_note_rounded,
      color: AppTheme.textTertiary,
      size: 20,
    ),
  );
}

// ---------------------------------------------------------------------------
// "Open in" icon button
// ---------------------------------------------------------------------------

class _OpenInButton extends StatelessWidget {
  const _OpenInButton({
    required this.url,
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  final String url;
  final IconData icon;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      tooltip: tooltip,
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}
