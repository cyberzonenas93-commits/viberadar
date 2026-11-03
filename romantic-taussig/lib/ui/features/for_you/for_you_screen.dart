import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../../providers/app_state.dart';
import '../../../providers/repositories.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/spotify_artist_service.dart';

// ── Persistent For You cache ──────────────────────────────────────────────────
// Lives in the Riverpod container so it survives screen navigation.

class _ForYouCache {
  const _ForYouCache({
    this.profiles = const {},
    this.topTracks = const {},
    this.latestRelease = const {},
    this.recommended = const [],
    this.loadedRecommended = false,
  });
  final Map<String, SpotifyArtistProfile> profiles;
  final Map<String, List<SpotifyTrackInfo>> topTracks;
  final Map<String, SpotifyAlbumInfo?> latestRelease;
  final List<SpotifyArtistProfile> recommended;
  final bool loadedRecommended;
}

class _ForYouCacheNotifier extends Notifier<_ForYouCache> {
  @override
  _ForYouCache build() => const _ForYouCache();

  bool hasArtist(String name) => state.profiles.containsKey(name);

  void setArtistData({
    required String name,
    required SpotifyArtistProfile profile,
    required List<SpotifyTrackInfo> tracks,
    required SpotifyAlbumInfo? latestRelease,
  }) {
    state = _ForYouCache(
      profiles: {...state.profiles, name: profile},
      topTracks: {...state.topTracks, name: tracks},
      latestRelease: {...state.latestRelease, name: latestRelease},
      recommended: state.recommended,
      loadedRecommended: state.loadedRecommended,
    );
  }

  void setRecommended(List<SpotifyArtistProfile> artists) {
    state = _ForYouCache(
      profiles: state.profiles,
      topTracks: state.topTracks,
      latestRelease: state.latestRelease,
      recommended: artists,
      loadedRecommended: true,
    );
  }
}

final _forYouCacheProvider = NotifierProvider<_ForYouCacheNotifier, _ForYouCache>(
  _ForYouCacheNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────

class ForYouScreen extends ConsumerStatefulWidget {
  const ForYouScreen({super.key, required this.onOpenArtist});

  /// Called when the user wants to open an artist's full catalog.
  /// Passes the artist name.
  final void Function(String artistName) onOpenArtist;

  @override
  ConsumerState<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends ConsumerState<ForYouScreen> {
  final _spotify = SpotifyArtistService();

  // Only local state that intentionally resets per-session (to avoid re-showing the picker)
  bool _autoPrompted = false;
  // Tracks in-progress loads to avoid duplicate concurrent fetches (race condition fix)
  final _loadingArtists = <String>{};

  _ForYouCacheNotifier get _cache => ref.read(_forYouCacheProvider.notifier);

  Future<void> _loadArtist(String name) async {
    // Skip if already cached or currently loading
    if (_cache.hasArtist(name)) return;
    if (_loadingArtists.contains(name)) return;
    _loadingArtists.add(name);
    try {
      final artistId = await _spotify.findArtistId(name);
      if (artistId == null || !mounted) return;

      final results = await Future.wait([
        _spotify.getArtistProfile(artistId),
        _spotify.getFullCatalogue(name),
        _spotify.getLatestRelease(artistId),
      ]);

      if (!mounted) return;
      final catalogue = results[1] as List<SpotifyTrackInfo>;
      catalogue.sort((a, b) => b.popularity.compareTo(a.popularity));

      _cache.setArtistData(
        name: name,
        profile: results[0] as SpotifyArtistProfile? ??
            SpotifyArtistProfile(id: artistId, name: name),
        tracks: catalogue.take(50).toList(),
        latestRelease: results[2] as SpotifyAlbumInfo?,
      );

      // Load recommendations once we have at least one artist
      if (!ref.read(_forYouCacheProvider).loadedRecommended) {
        _loadRecommendations(artistId);
      }
    } catch (_) {
    } finally {
      _loadingArtists.remove(name);
    }
  }

  Future<void> _loadRecommendations(String seedArtistId) async {
    try {
      final related = await _spotify.getRelatedArtists(seedArtistId);
      if (!mounted) return;
      final userProfile = ref.read(userProfileProvider).value;
      final followed =
          userProfile?.followedArtists.map((a) => a.toLowerCase()).toSet() ?? {};
      final filtered = related
          .where((a) => !followed.contains(a.name.toLowerCase()))
          .take(12)
          .toList();
      _cache.setRecommended(filtered);
    } catch (_) {}
  }

  void _followArtist(UserProfile profile, String artistName) {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    ref.read(userRepositoryProvider).followArtist(
          userId: session.userId,
          fallbackName: session.displayName,
          artistName: artistName,
        );
  }

  void _unfollowArtist(UserProfile profile, String artistName) {
    final session = ref.read(sessionProvider).value;
    if (session == null) return;
    ref.read(userRepositoryProvider).unfollowArtist(
          userId: session.userId,
          fallbackName: session.displayName,
          artistName: artistName,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProfileAsync = ref.watch(userProfileProvider);
    final userProfile = userProfileAsync.value;
    final followed = userProfile?.followedArtists ?? [];
    // Watch the cache so the UI rebuilds when data arrives
    final cache = ref.watch(_forYouCacheProvider);

    // Kick off loads for artists not yet in cache
    for (final name in followed) {
      if (!cache.profiles.containsKey(name)) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _loadArtist(name));
      }
    }

    if (followed.isEmpty) {
      // Auto-open the picker on first visit so the user doesn't have to tap
      if (!_autoPrompted && userProfileAsync.hasValue) {
        _autoPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showArtistPicker(context, userProfile),
        );
      }
      return _EmptyForYou(
        onAddArtists: () => _showArtistPicker(context, userProfile),
      );
    }

    return CustomScrollView(
      slivers: [
        // ── Header ───────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'For You',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${followed.length} artists you follow',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showArtistPicker(context, userProfile),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Artists'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.violet.withValues(alpha: 0.2),
                    foregroundColor: AppTheme.violet,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Followed artists feed ─────────────────────────────────────────────
        for (final name in followed) ...[
          SliverToBoxAdapter(
            child: _ArtistSection(
              artistName: name,
              profile: cache.profiles[name],
              topTracks: cache.topTracks[name] ?? [],
              latestRelease: cache.latestRelease[name],
              onOpenCatalog: () => widget.onOpenArtist(name),
              onUnfollow: userProfile != null
                  ? () => _unfollowArtist(userProfile, name)
                  : null,
            ),
          ),
        ],

        // ── Recommendations ───────────────────────────────────────────────────
        if (cache.recommended.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AppTheme.cyan, AppTheme.violet],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Recommended For You',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final artist = cache.recommended[i];
                  final isFollowed = followed.any(
                      (f) => f.toLowerCase() == artist.name.toLowerCase());
                  return _RecommendedArtistCard(
                    artist: artist,
                    isFollowed: isFollowed,
                    onFollow: () => userProfile != null
                        ? _followArtist(userProfile, artist.name)
                        : null,
                  );
                },
                childCount: cache.recommended.length,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.75,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  void _showArtistPicker(BuildContext context, UserProfile? profile) {
    showDialog(
      context: context,
      builder: (_) => _ArtistPickerDialog(
        initialFollowed: profile?.followedArtists ?? [],
        onSave: (selected) {
          final session = ref.read(sessionProvider).value;
          if (session == null || profile == null) return;
          ref.read(userRepositoryProvider).setFollowedArtists(
                userId: session.userId,
                fallbackName: session.displayName,
                artists: selected,
              );
        },
      ),
    );
  }
}

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
      margin: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Artist header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: imageUrl != null
                  ? null
                  : LinearGradient(
                      colors: [
                        AppTheme.violet.withValues(alpha: 0.1),
                        Colors.transparent
                      ],
                    ),
            ),
            child: Row(
              children: [
                // Avatar
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover)
                      : Container(
                          width: 72,
                          height: 72,
                          color: AppTheme.panelRaised,
                          child: const Icon(Icons.person_rounded,
                              color: AppTheme.textTertiary, size: 36),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!isLoading && profile!.genres.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          profile!.genres.take(3).join(' · '),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                      if (!isLoading && profile!.followers > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_formatFollowers(profile!.followers)} followers',
                          style: const TextStyle(
                              color: AppTheme.textTertiary, fontSize: 11),
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
                        backgroundColor:
                            AppTheme.cyan.withValues(alpha: 0.15),
                        foregroundColor: AppTheme.cyan,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Full Catalog',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: onUnfollow,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textTertiary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child:
                          const Text('Unfollow', style: TextStyle(fontSize: 11)),
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
                      color: AppTheme.violet, strokeWidth: 2)),
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
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Latest Release',
                          style: TextStyle(
                              color: AppTheme.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    if (latestRelease!.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                            imageUrl: latestRelease!.imageUrl!,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${latestRelease!.name} · ${latestRelease!.releaseDate?.substring(0, 4) ?? ''}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
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
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final t = topTracks[i];
                      return _MiniTrackCard(
                        track: t,
                        rank: i + 1,
                        allTracks: topTracks.take(8).toList(),
                        trackIndex: i,
                      );
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

class _MiniTrackCard extends ConsumerStatefulWidget {
  const _MiniTrackCard({
    required this.track,
    required this.rank,
    required this.allTracks,
    required this.trackIndex,
  });
  final SpotifyTrackInfo track;
  final int rank;
  final List<SpotifyTrackInfo> allTracks;
  final int trackIndex;

  @override
  ConsumerState<_MiniTrackCard> createState() => _MiniTrackCardState();
}

class _MiniTrackCardState extends ConsumerState<_MiniTrackCard> {
  bool _hovered = false;

  void _play() async {
    final queue = widget.allTracks
        .skip(widget.trackIndex + 1)
        .map((t) => (t.name, t.artists))
        .toList();
    final played = await ref.read(appleMusicProvider.notifier).playByQuery(
      widget.track.name,
      widget.track.artists,
      queue: queue,
    );
    if (!played && widget.track.spotifyUrl.isNotEmpty) {
      final uri = Uri.tryParse(widget.track.spotifyUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final am = ref.watch(appleMusicProvider);
    final isCurrentTrack = am.currentTrack?.title.toLowerCase() == widget.track.name.toLowerCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _play,
        child: SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: widget.track.albumArt != null
                        ? CachedNetworkImage(
                            imageUrl: widget.track.albumArt!,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover)
                        : Container(
                            width: 110,
                            height: 110,
                            color: AppTheme.panelRaised,
                            child: const Icon(Icons.music_note_rounded,
                                color: AppTheme.textTertiary, size: 32)),
                  ),
                  // Hover / active overlay (full dark scrim + centered icon)
                  if (_hovered || isCurrentTrack)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: Colors.black54,
                          child: Center(
                            child: am.isLoading && isCurrentTrack
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFFFC3C44),
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Icon(
                                    isCurrentTrack && am.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: Colors.white,
                                    size: 44,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  // Persistent small play badge (bottom-right), always visible
                  if (!_hovered && !isCurrentTrack)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFC3C44),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 6)],
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.track.name,
                style: TextStyle(
                    color: isCurrentTrack ? const Color(0xFFFC3C44) : AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.track.albumName,
                style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
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
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: artist.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: artist.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover)
                  : Container(
                      color: AppTheme.panelRaised,
                      child: const Icon(Icons.person_rounded,
                          color: AppTheme.textTertiary, size: 40)),
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
                      fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (artist.genres.isNotEmpty)
                  Text(
                    artist.genres.first,
                    style: const TextStyle(
                        color: AppTheme.textTertiary, fontSize: 10),
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
                      foregroundColor:
                          isFollowed ? AppTheme.violet : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child: Text(
                      isFollowed ? 'Following' : '+ Follow',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
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

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyForYou extends StatelessWidget {
  const _EmptyForYou({required this.onAddArtists});
  final VoidCallback onAddArtists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.violet.withValues(alpha: 0.2),
                  AppTheme.cyan.withValues(alpha: 0.1)
                ],
              ),
              border: Border.all(
                  color: AppTheme.violet.withValues(alpha: 0.3), width: 2),
            ),
            child: ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                      colors: [AppTheme.violet, AppTheme.cyan])
                  .createShader(b),
              child: const Icon(Icons.favorite_rounded,
                  size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Your personal feed',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Follow artists to see their latest releases,\ntop tracks, and personalized recommendations.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAddArtists,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Follow Artists',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.violet,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Artist picker dialog ──────────────────────────────────────────────────────

class _ArtistPickerDialog extends StatefulWidget {
  const _ArtistPickerDialog(
      {required this.initialFollowed, required this.onSave});
  final List<String> initialFollowed;
  final void Function(List<String> selected) onSave;

  @override
  State<_ArtistPickerDialog> createState() => _ArtistPickerDialogState();
}

class _ArtistPickerDialogState extends State<_ArtistPickerDialog> {
  final _searchCtrl = TextEditingController();
  final _spotify = SpotifyArtistService();
  late final Set<String> _selected;
  List<SpotifyArtistResult> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;
  // Cached images for popular artists
  final Map<String, String?> _popularImages = {};

  // Popular artists to show by default
  static const _popular = [
    'Drake',
    'Kendrick Lamar',
    'Bad Bunny',
    'The Weeknd',
    'Taylor Swift',
    'Asake',
    'Wizkid',
    'Burna Boy',
    'Davido',
    'Fireboy DML',
    'Rema',
    'Tems',
    'Ayra Starr',
    'Ckay',
    'Beyoncé',
    'SZA',
    'Doja Cat',
    'Cardi B',
    'Nicki Minaj',
    'Travis Scott',
    'Future',
    'Lil Baby',
    'Gunna',
    'J. Cole',
    'Nas',
    'Jay-Z',
    'Kanye West',
    'Tyler the Creator',
    'Frank Ocean',
    'Bryson Tiller',
    'H.E.R.',
    'Jhené Aiko',
    'Summer Walker',
    'Chris Brown',
    'Usher',
    'Brent Faiyaz',
    'PartyNextDoor',
    'Headie One',
    'Central Cee',
    'Dave',
    'Stormzy',
    'AJ Tracey',
    'Fivio Foreign',
    'Lil Durk',
    'Rod Wave',
    'Morgan Wallen',
    'Luke Combs',
    'Zach Bryan',
    'Peso Pluma',
    'Feid',
    'J Balvin',
    'Maluma',
    'Daddy Yankee',
    'Farruko',
    'Ozuna',
  ];

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialFollowed);
    _loadPopularImages();
  }

  /// Load images for popular artists in batches via Spotify search.
  Future<void> _loadPopularImages() async {
    // Search in batches of 5 to avoid rate limits
    for (var i = 0; i < _popular.length; i += 5) {
      final batch = _popular.skip(i).take(5);
      await Future.wait(batch.map((name) async {
        try {
          final results = await _spotify.searchArtistsByName(name);
          if (results.isNotEmpty && mounted) {
            setState(() => _popularImages[name] = results.first.imageUrl);
          }
        } catch (_) {}
      }));
      if (!mounted) return;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final results = await _spotify.searchArtistsByName(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showSearch = _searchCtrl.text.length >= 2;
    final displayItems =
        showSearch ? _searchResults.map((r) => r.name).toList() : _popular;

    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SizedBox(
        width: 620,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Follow Artists',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Pick artists you love. We'll build your personal feed around them.",
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // Search field
                  TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search any artist...',
                      hintStyle:
                          const TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.textTertiary, size: 18),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.violet)),
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.panelRaised,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.edge)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppTheme.edge)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppTheme.violet, width: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
            // Selected chips
            if (_selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selected
                      .take(8)
                      .map(
                        (name) => GestureDetector(
                          onTap: () =>
                              setState(() => _selected.remove(name)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.violet.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppTheme.violet
                                      .withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                      color: AppTheme.violet,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.close_rounded,
                                    color: AppTheme.violet, size: 12),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
            // Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate:
                    const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: displayItems.length,
                itemBuilder: (context, i) {
                  final name = displayItems[i];
                  final imageUrl = showSearch
                      ? _searchResults[i].imageUrl
                      : _popularImages[name];
                  final isSelected = _selected.contains(name);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (isSelected) {
                        _selected.remove(name);
                      } else {
                        _selected.add(name);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.violet.withValues(alpha: 0.15)
                            : AppTheme.panelRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.violet
                              : AppTheme.edge.withValues(alpha: 0.5),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: imageUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover)
                                    : Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              AppTheme.violet
                                                  .withValues(alpha: 0.3),
                                              AppTheme.cyan
                                                  .withValues(alpha: 0.2),
                                            ],
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontSize: 22,
                                                fontWeight:
                                                    FontWeight.w700),
                                          ),
                                        ),
                                      ),
                              ),
                              if (isSelected)
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: const BoxDecoration(
                                      color: AppTheme.violet,
                                      shape: BoxShape.circle),
                                  child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 12),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              name,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.violet
                                    : AppTheme.textPrimary,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                children: [
                  Text(
                    '${_selected.length} selected',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppTheme.textTertiary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            widget.onSave(_selected.toList());
                            Navigator.pop(context);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.violet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w600)),
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
