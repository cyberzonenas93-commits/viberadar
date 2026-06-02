part of 'vibe_shell.dart';

// ── Playlists View ────────────────────────────────────────────────────────────

class _PlaylistsView extends StatefulWidget {
  const _PlaylistsView();

  @override
  State<_PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<_PlaylistsView> {
  final _service = PlaylistAggregationService();
  String _genre = 'All';
  String _region = 'All';
  List<AggregatedPlaylist> _playlists = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await _service.fetchPlaylists(
        genre: _genre,
        region: _region,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _playlists = results;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genreOptions = [
      'All',
      'Afrobeats',
      'Amapiano',
      'Hip-Hop',
      'R&B',
      'House',
      'Dancehall',
      'Pop',
      'Latin',
      'Drill',
    ];
    final regionOptions = ['All', 'GH', 'NG', 'ZA', 'GB', 'US', 'DE'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Row(
            children: [
              const Icon(
                Icons.playlist_play_rounded,
                color: AppTheme.cyan,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                'Top Playlists',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_playlists.length} playlists from Apple Music, Spotify & YouTube',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              // Genre filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.edge.withValues(alpha: 0.5),
                  ),
                ),
                child: DropdownButton<String>(
                  value: _genre,
                  dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                  underline: const SizedBox(),
                  isDense: true,
                  items: genreOptions
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _genre = v);
                      _load();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Region filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.edge.withValues(alpha: 0.5),
                  ),
                ),
                child: DropdownButton<String>(
                  value: _region,
                  dropdownColor: AppTheme.panelRaised,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                  underline: const SizedBox(),
                  isDense: true,
                  items: regionOptions
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _region = v);
                      _load();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.cyan,
                    strokeWidth: 2,
                  ),
                )
              : _playlists.isEmpty
              ? const Center(
                  child: Text(
                    'No playlists found. Try a different genre.',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                  itemCount: _playlists.length,
                  itemBuilder: (ctx, i) =>
                      _PlaylistCard(playlist: _playlists[i]),
                ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});
  final AggregatedPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (playlist.artworkUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: playlist.artworkUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.panelRaised,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.playlist_play_rounded,
                      color: AppTheme.cyan,
                      size: 24,
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.tracks.length} tracks from ${playlist.sourceLabel}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Track grid
          if (playlist.tracks.isNotEmpty)
            SizedBox(
              height: 200,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 150,
                ),
                itemCount: playlist.tracks.length,
                itemBuilder: (ctx, i) =>
                    _PlaylistTrackCard(track: playlist.tracks[i]),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Platform result card (for set builder) ──────────────────────────────────

class _PlatformResultCard extends StatefulWidget {
  const _PlatformResultCard({required this.track, required this.index});
  final AiCrateTrack track;
  final int index;

  @override
  State<_PlatformResultCard> createState() => _PlatformResultCardState();
}

class _PlatformResultCardState extends State<_PlatformResultCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final url = t.bestUrl;
          if (url.isNotEmpty) {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      child: SizedBox.expand(
                        child: t.artworkUrl != null
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppTheme.panelRaised,
                                child: const Center(
                                  child: Icon(
                                    Icons.music_note_rounded,
                                    color: AppTheme.textTertiary,
                                    size: 32,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Source badges
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Row(
                        children: [
                          if (t.spotifyUrl != null)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1ED760),
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (t.spotifyUrl != null && t.appleUrl != null)
                            const SizedBox(width: 3),
                          if (t.appleUrl != null)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF7AB5),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(13),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.cyan.withValues(alpha: 0.5),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (t.bpm > 0 || t.key.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (t.bpm > 0)
                            Text(
                              '${t.bpm}',
                              style: const TextStyle(
                                color: AppTheme.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                          if (t.bpm > 0 && t.key.isNotEmpty)
                            const SizedBox(width: 4),
                          if (t.key.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.edge.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                t.key,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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

class _PlaylistTrackCard extends StatefulWidget {
  const _PlaylistTrackCard({required this.track});
  final PlatformTrackResult track;

  @override
  State<_PlaylistTrackCard> createState() => _PlaylistTrackCardState();
}

class _PlaylistTrackCardState extends State<_PlaylistTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final url = t.bestUrl;
          if (url.isNotEmpty) {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11),
                      ),
                      child: SizedBox.expand(
                        child: t.artworkUrl != null
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: AppTheme.panelRaised,
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                      ),
                    ),
                    if (_hovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(11),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Source badges
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Row(
                        children: [
                          if (t.spotifyUrl != null)
                            _miniSourceBadge(const Color(0xFF1ED760)),
                          if (t.spotifyUrl != null && t.appleUrl != null)
                            const SizedBox(width: 3),
                          if (t.appleUrl != null)
                            _miniSourceBadge(const Color(0xFFFF7AB5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 9,
                      ),
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

  Widget _miniSourceBadge(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
