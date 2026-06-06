part of 'for_you_screen.dart';

// ── Artist section card ───────────────────────────────────────────────────────

class _ArtistSection extends StatelessWidget {
  const _ArtistSection({
    required this.artistName,
    required this.profile,
    required this.topTracks,
    required this.latestRelease,
    required this.onOpenCatalog,
    required this.onUnfollow,
  });

  final String artistName;
  final SpotifyArtistProfile? profile;
  final List<SpotifyTrackInfo> topTracks;
  final SpotifyAlbumInfo? latestRelease;
  final VoidCallback onOpenCatalog;
  final VoidCallback? onUnfollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = profile?.imageUrl;
    final isLoading = profile == null;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.r2xl,
        0,
        AppTheme.r2xl,
        AppTheme.s6,
      ),
      decoration: AppTheme.glass(
        radius: AppTheme.rXl,
        tint: AppTheme.violet,
        border: AppTheme.hairline,
        glowShadow: AppTheme.glow(AppTheme.violet, blur: 24, opacity: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Artist header
          Container(
            padding: const EdgeInsets.all(AppTheme.s5),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.rXl),
              ),
              gradient: imageUrl != null
                  ? null
                  : LinearGradient(
                      colors: [
                        AppTheme.violet.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
            ),
            child: Row(
              children: [
                // Avatar
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 72,
                          height: 72,
                          color: AppTheme.panelRaised,
                          child: const Icon(
                            Icons.person_rounded,
                            color: AppTheme.textTertiary,
                            size: 36,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoading ? artistName : (profile!.name),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (!isLoading && profile!.genres.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile!.genres.take(3).join(' · '),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (!isLoading && profile!.followers > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_formatFollowers(profile!.followers)} followers',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Actions
                Column(
                  children: [
                    FilledButton(
                      onPressed: onOpenCatalog,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.cyan.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.cyan,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Full Catalog',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onUnfollow,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textTertiary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Unfollow',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.violet,
                  strokeWidth: 2,
                ),
              ),
            )
          else ...[
            // Latest release
            if (latestRelease != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Latest Release',
                        style: TextStyle(
                          color: AppTheme.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (latestRelease!.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: latestRelease!.imageUrl!,
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${latestRelease!.name} · ${latestRelease!.releaseDate?.substring(0, 4) ?? ''}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Top tracks horizontal scroll
            if (topTracks.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 0, 16),
                child: SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(right: 20),
                    itemCount: topTracks.take(8).length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final t = topTracks[i];
                      return _MiniTrackCard(track: t, rank: i + 1);
                    },
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatFollowers(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).round()}K';
    return '$n';
  }
}

// ── Mini track card ───────────────────────────────────────────────────────────

class _MiniTrackCard extends StatelessWidget {
  const _MiniTrackCard({required this.track, required this.rank});
  final SpotifyTrackInfo track;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (track.spotifyUrl.isNotEmpty) {
          final uri = Uri.tryParse(track.spotifyUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      },
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              child: track.albumArt != null
                  ? CachedNetworkImage(
                      imageUrl: track.albumArt!,
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 110,
                      height: 110,
                      color: AppTheme.panelRaised,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppTheme.textTertiary,
                        size: 32,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              track.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              track.albumName,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recommended artist card ───────────────────────────────────────────────────

class _RecommendedArtistCard extends StatelessWidget {
  const _RecommendedArtistCard({
    required this.artist,
    required this.isFollowed,
    required this.onFollow,
  });
  final SpotifyArtistProfile artist;
  final bool isFollowed;
  final VoidCallback? onFollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glass(radius: 14, border: AppTheme.hairline),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: artist.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: artist.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppTheme.panelRaised,
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppTheme.textTertiary,
                        size: 40,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist.genres.isNotEmpty)
                  Text(
                    artist.genres.first,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isFollowed ? null : onFollow,
                    style: FilledButton.styleFrom(
                      backgroundColor: isFollowed
                          ? AppTheme.violet.withValues(alpha: 0.2)
                          : AppTheme.violet,
                      foregroundColor: isFollowed
                          ? AppTheme.violet
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      isFollowed ? 'Following' : '+ Follow',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
