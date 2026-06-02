part of 'artists_screen.dart';

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
