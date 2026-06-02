import 'dart:async';
import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/user_profile.dart';
import '../../../providers/app_state.dart';
import '../../../providers/repositories.dart';
import '../../../services/spotify_artist_service.dart';

part 'for_you_screen_cards.dart';
part 'for_you_screen_widgets.dart';

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

  // artistName → profile
  final Map<String, SpotifyArtistProfile> _profiles = {};
  // artistName → top tracks
  final Map<String, List<SpotifyTrackInfo>> _topTracks = {};
  // artistName → latest release
  final Map<String, SpotifyAlbumInfo?> _latestRelease = {};
  // recommended artists (deduped across all followed)
  List<SpotifyArtistProfile> _recommended = [];
  bool _loadedRecommended = false;
  // Auto-open the artist picker once on first visit when no artists are followed
  bool _autoPrompted = false;

  Future<void> _loadArtist(String name) async {
    if (_profiles.containsKey(name)) return;
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
      // Sort by popularity descending, keep at least 50
      catalogue.sort((a, b) => b.popularity.compareTo(a.popularity));
      setState(() {
        _profiles[name] = results[0] as SpotifyArtistProfile? ??
            SpotifyArtistProfile(id: artistId, name: name);
        _topTracks[name] = catalogue.take(50).toList();
        _latestRelease[name] = results[2] as SpotifyAlbumInfo?;
      });

      // Load recommendations once we have at least one artist
      if (!_loadedRecommended) {
        _loadedRecommended = true;
        _loadRecommendations(artistId);
      }
    } catch (e, st) {
      developer.log('Failed to load artist data for $name', name: 'ForYou', error: e, stackTrace: st);
    }
  }

  Future<void> _loadRecommendations(String seedArtistId) async {
    try {
      final related = await _spotify.getRelatedArtists(seedArtistId);
      if (!mounted) return;
      // Filter out artists already followed
      final userProfile = ref.read(userProfileProvider).value;
      final followed =
          userProfile?.followedArtists.map((a) => a.toLowerCase()).toSet() ??
              {};
      final filtered = related
          .where((a) => !followed.contains(a.name.toLowerCase()))
          .take(12)
          .toList();
      setState(() => _recommended = filtered);
    } catch (e, st) {
      developer.log('Failed to load artist recommendations', name: 'ForYou', error: e, stackTrace: st);
    }
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

    // Kick off loads for newly followed artists
    for (final name in followed) {
      if (!_profiles.containsKey(name)) {
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
              profile: _profiles[name],
              topTracks: _topTracks[name] ?? [],
              latestRelease: _latestRelease[name],
              onOpenCatalog: () => widget.onOpenArtist(name),
              onUnfollow: userProfile != null
                  ? () => _unfollowArtist(userProfile, name)
                  : null,
            ),
          ),
        ],

        // ── Recommendations ───────────────────────────────────────────────────
        if (_recommended.isNotEmpty) ...[
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
                  final artist = _recommended[i];
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
                childCount: _recommended.length,
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
