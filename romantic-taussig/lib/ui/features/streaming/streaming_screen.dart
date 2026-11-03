import 'dart:io';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/streaming_provider.dart';
import '../../../services/apple_music_service.dart';
import '../../../services/spotify_preview_service.dart';

class StreamingScreen extends ConsumerStatefulWidget {
  const StreamingScreen({super.key});

  @override
  ConsumerState<StreamingScreen> createState() => _StreamingScreenState();
}

class _StreamingScreenState extends ConsumerState<StreamingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _amSearchController = TextEditingController();
  final _spSearchController = TextEditingController();
  final _spClientIdController = TextEditingController();
  final _spClientSecretController = TextEditingController();
  Timer? _amDebounce;
  Timer? _spDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amSearchController.dispose();
    _spSearchController.dispose();
    _spClientIdController.dispose();
    _spClientSecretController.dispose();
    _amDebounce?.cancel();
    _spDebounce?.cancel();
    super.dispose();
  }

  // ── Apple Music helpers ────────────────────────────────────────────────────

  void _amOnSearchChanged(String value) {
    _amDebounce?.cancel();
    _amDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(appleMusicProvider.notifier).search(value.trim());
    });
  }

  void _amClearSearch() {
    _amSearchController.clear();
    ref.read(appleMusicProvider.notifier).search('');
  }

  // ── Spotify helpers ────────────────────────────────────────────────────────

  void _spOnSearchChanged(String value) {
    _spDebounce?.cancel();
    _spDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(spotifyProvider.notifier).search(value.trim());
    });
  }

  void _spClearSearch() {
    _spSearchController.clear();
    ref.read(spotifyProvider.notifier).search('');
  }

  Future<void> _spConfigure() async {
    final id = _spClientIdController.text.trim();
    final secret = _spClientSecretController.text.trim();
    if (id.isEmpty || secret.isEmpty) return;
    await ref.read(spotifyProvider.notifier).configure(id, secret);
  }

  void _openInSpotify(SpotifyTrack track) {
    Process.run('open', [track.deepLink]);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _AppleMusicTab(
                searchController: _amSearchController,
                onSearchChanged: _amOnSearchChanged,
                onClearSearch: _amClearSearch,
              ),
              _SpotifyTab(
                searchController: _spSearchController,
                clientIdController: _spClientIdController,
                clientSecretController: _spClientSecretController,
                onSearchChanged: _spOnSearchChanged,
                onClearSearch: _spClearSearch,
                onConfigure: _spConfigure,
                onOpenInSpotify: _openInSpotify,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.violet, AppTheme.cyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.stream_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Streaming',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    const Text(
                      'Apple Music full playback  •  Spotify 30-second previews',
                      style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            indicatorColor: AppTheme.violet,
            indicatorWeight: 2,
            labelColor: AppTheme.violet,
            unselectedLabelColor: AppTheme.textTertiary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13),
            tabs: const [
              Tab(
                icon: Icon(Icons.music_note_rounded, size: 16),
                text: 'Apple Music',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
              Tab(
                icon: Icon(Icons.podcasts_rounded, size: 16),
                text: 'Spotify',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
            ],
          ),
          Divider(color: AppTheme.edge.withValues(alpha: 0.4), height: 1),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Apple Music Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AppleMusicTab extends ConsumerWidget {
  const _AppleMusicTab({
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appleMusicProvider);

    return Column(
      children: [
        // Auth banner
        _buildAuthBanner(context, ref, state),

        // Search bar (only visible when authorized)
        if (state.isAuthorized) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _SearchBar(
              controller: searchController,
              hintText: 'Search Apple Music…',
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              accentColor: AppTheme.pink,
            ),
          ),
        ],

        // Content
        Expanded(child: _buildContent(context, ref, state)),
      ],
    );
  }

  Widget _buildAuthBanner(BuildContext context, WidgetRef ref, AppleMusicState state) {
    if (state.isAuthorized && state.hasSubscription) return const SizedBox.shrink();
    if (state.isAuthorized && !state.hasSubscription) {
      // Authorized but no subscription
      return _InfoBanner(
        icon: Icons.music_off_rounded,
        iconColor: AppTheme.amber,
        message: 'Apple Music subscription required for full playback.',
        subtitle: 'Subscribe at music.apple.com to unlock streaming.',
      );
    }

    // Not authorized or not determined
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_note_rounded, color: AppTheme.pink, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect Apple Music',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Stream full tracks directly in VibeRadar via MusicKit.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(appleMusicProvider.notifier).requestAccess(),
              icon: state.isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 16),
              label: Text(state.isLoading ? 'Requesting access…' : 'Connect Apple Music'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.pink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, AppleMusicState state) {
    if (!state.isAuthorized) {
      return const _EmptyHint(
        icon: Icons.music_note_rounded,
        title: 'Apple Music not connected',
        subtitle: 'Connect your Apple Music account above to search and play tracks.',
      );
    }

    if (state.isLoading && state.searchResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.pink, strokeWidth: 2),
      );
    }

    if (state.searchQuery.isNotEmpty && state.searchResults.isEmpty && !state.isLoading) {
      return _EmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No results for "${state.searchQuery}"',
        subtitle: 'Try a different search term.',
      );
    }

    if (state.searchResults.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search_rounded,
        title: 'Search Apple Music',
        subtitle: 'Type a song, artist, or album name above.',
      );
    }

    return _TrackGrid<AppleMusicTrack>(
      tracks: state.searchResults,
      currentTrack: state.currentTrack,
      isPlaying: state.isPlaying,
      accentColor: AppTheme.pink,
      buildArtworkUrl: (t) => t.artworkUrl,
      buildTitle: (t) => t.title,
      buildArtist: (t) => t.artist,
      buildAlbum: (t) => t.album,
      buildDuration: (t) => _formatDuration(t.durationMs),
      buildBadge: (_) => null,
      isCurrentTrack: (t) => state.currentTrack?.id == t.id,
      isCurrentlyPlaying: (t) => state.currentTrack?.id == t.id && state.isPlaying,
      onPlayTap: (t) {
        if (state.currentTrack?.id == t.id) {
          ref.read(appleMusicProvider.notifier).togglePlayPause();
        } else {
          ref.read(appleMusicProvider.notifier).play(t);
        }
      },
      primaryActionLabel: 'Play',
      secondaryActions: [],
    );
  }

  String? _formatDuration(int? ms) {
    if (ms == null) return null;
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Spotify Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SpotifyTab extends ConsumerWidget {
  const _SpotifyTab({
    required this.searchController,
    required this.clientIdController,
    required this.clientSecretController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onConfigure,
    required this.onOpenInSpotify,
  });

  final TextEditingController searchController;
  final TextEditingController clientIdController;
  final TextEditingController clientSecretController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onConfigure;
  final ValueChanged<SpotifyTrack> onOpenInSpotify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(spotifyProvider);

    return Column(
      children: [
        // Setup / status section
        if (!state.isAuthenticated)
          _buildSetupPanel(context, ref, state)
        else
          _buildConnectedBanner(state),

        // Search bar (only visible when authenticated)
        if (state.isAuthenticated) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _SearchBar(
              controller: searchController,
              hintText: 'Search Spotify…',
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              accentColor: AppTheme.lime,
            ),
          ),
        ],

        // Content
        Expanded(child: _buildContent(context, ref, state)),
      ],
    );
  }

  Widget _buildSetupPanel(BuildContext context, WidgetRef ref, SpotifyState state) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.lime.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.podcasts_rounded, color: AppTheme.lime, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connect Spotify',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Search tracks and play 30-second previews. Full playback opens Spotify.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Developer link hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cyan.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.cyan, size: 14),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Create a free app at developer.spotify.com/dashboard to get credentials.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _StyledTextField(
            controller: clientIdController,
            label: 'Client ID',
            hint: 'Paste your Spotify Client ID',
          ),
          const SizedBox(height: 10),
          _StyledTextField(
            controller: clientSecretController,
            label: 'Client Secret',
            hint: 'Paste your Spotify Client Secret',
            obscure: true,
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.isLoading ? null : onConfigure,
              icon: state.isLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.login_rounded, size: 16),
              label: Text(state.isLoading ? 'Authenticating…' : 'Connect Spotify'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedBanner(SpotifyState state) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.lime.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.lime.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppTheme.lime, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          const Text(
            'Spotify connected',
            style: TextStyle(color: AppTheme.lime, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const Spacer(),
          const Text(
            '30s previews  •  Full tracks open in Spotify',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, SpotifyState state) {
    if (!state.isAuthenticated) {
      return const _EmptyHint(
        icon: Icons.podcasts_rounded,
        title: 'Spotify not connected',
        subtitle: 'Enter your Spotify credentials above to search and preview tracks.',
      );
    }

    if (state.isLoading && state.searchResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.lime, strokeWidth: 2),
      );
    }

    if (state.searchQuery.isNotEmpty && state.searchResults.isEmpty && !state.isLoading) {
      return _EmptyHint(
        icon: Icons.search_off_rounded,
        title: 'No results for "${state.searchQuery}"',
        subtitle: 'Try a different search term.',
      );
    }

    if (state.searchResults.isEmpty) {
      return const _EmptyHint(
        icon: Icons.search_rounded,
        title: 'Search Spotify',
        subtitle: 'Type a song, artist, or album name above.',
      );
    }

    return _TrackGrid<SpotifyTrack>(
      tracks: state.searchResults,
      currentTrack: state.currentPreviewTrack,
      isPlaying: state.isPlayingPreview,
      accentColor: AppTheme.lime,
      buildArtworkUrl: (t) => t.artworkUrl,
      buildTitle: (t) => t.title,
      buildArtist: (t) => t.artist,
      buildAlbum: (t) => t.album,
      buildDuration: (t) => _formatDuration(t.durationMs),
      buildBadge: (t) => t.hasPreview ? '30s' : null,
      isCurrentTrack: (t) => state.currentPreviewTrack?.id == t.id,
      isCurrentlyPlaying: (t) => state.currentPreviewTrack?.id == t.id && state.isPlayingPreview,
      onPlayTap: (t) => ref.read(spotifyProvider.notifier).togglePreview(t),
      primaryActionLabel: 'Preview',
      secondaryActions: [
        _TrackSecondaryAction(
          icon: Icons.open_in_new_rounded,
          label: 'Open in Spotify',
          onTap: onOpenInSpotify,
        ),
      ],
    );
  }

  String? _formatDuration(int? ms) {
    if (ms == null) return null;
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic Track Grid
// ─────────────────────────────────────────────────────────────────────────────

class _TrackSecondaryAction<T> {
  const _TrackSecondaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final ValueChanged<T> onTap;
}

class _TrackGrid<T> extends StatelessWidget {
  const _TrackGrid({
    required this.tracks,
    required this.currentTrack,
    required this.isPlaying,
    required this.accentColor,
    required this.buildArtworkUrl,
    required this.buildTitle,
    required this.buildArtist,
    required this.buildAlbum,
    required this.buildDuration,
    required this.buildBadge,
    required this.isCurrentTrack,
    required this.isCurrentlyPlaying,
    required this.onPlayTap,
    required this.primaryActionLabel,
    required this.secondaryActions,
  });

  final List<T> tracks;
  final T? currentTrack;
  final bool isPlaying;
  final Color accentColor;
  final String? Function(T) buildArtworkUrl;
  final String Function(T) buildTitle;
  final String Function(T) buildArtist;
  final String Function(T) buildAlbum;
  final String? Function(T) buildDuration;
  final String? Function(T) buildBadge;
  final bool Function(T) isCurrentTrack;
  final bool Function(T) isCurrentlyPlaying;
  final ValueChanged<T> onPlayTap;
  final String primaryActionLabel;
  final List<_TrackSecondaryAction<T>> secondaryActions;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = isCurrentTrack(track);
        final playing = isCurrentlyPlaying(track);
        final artworkUrl = buildArtworkUrl(track);
        final badge = buildBadge(track);
        final duration = buildDuration(track);

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isCurrent
                ? accentColor.withValues(alpha: 0.08)
                : AppTheme.panelRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isCurrent
                  ? accentColor.withValues(alpha: 0.35)
                  : AppTheme.edge.withValues(alpha: 0.5),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onPlayTap(track),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Artwork
                    _Artwork(url: artworkUrl, size: 48, accentColor: accentColor),
                    const SizedBox(width: 14),

                    // Track info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            buildTitle(track),
                            style: TextStyle(
                              color: isCurrent ? accentColor : AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            buildArtist(track),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            buildAlbum(track),
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

                    const SizedBox(width: 10),

                    // Badge + duration column
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (badge != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (duration != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            duration,
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(width: 12),

                    // Play button
                    GestureDetector(
                      onTap: () => onPlayTap(track),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? accentColor
                              : accentColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: isCurrent ? Colors.white : accentColor,
                          size: 18,
                        ),
                      ),
                    ),

                    // Secondary actions
                    for (final action in secondaryActions) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => action.onTap(track),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
                          ),
                          child: Tooltip(
                            message: action.label,
                            child: Icon(action.icon, color: AppTheme.textSecondary, size: 15),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size, required this.accentColor});

  final String? url;
  final double size;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context2, url2) => _placeholder(),
          errorWidget: (context2, url2, error2) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note_rounded, color: accentColor.withValues(alpha: 0.4), size: size * 0.4),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    required this.accentColor,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(Icons.search_rounded, size: 18, color: accentColor.withValues(alpha: 0.7)),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textTertiary),
                padding: EdgeInsets.zero,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        filled: true,
        fillColor: AppTheme.panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
    );
  }
}

class _StyledTextField extends StatefulWidget {
  const _StyledTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;

  @override
  State<_StyledTextField> createState() => _StyledTextFieldState();
}

class _StyledTextFieldState extends State<_StyledTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.edge.withValues(alpha: 0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.lime, width: 1.5),
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      size: 16,
                      color: AppTheme.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.iconColor,
    required this.message,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.panelRaised,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.edge.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: AppTheme.textTertiary, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
