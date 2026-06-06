part of 'search_screen.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Text(
            '$totalCount results',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
            children: [
              // Spotify + Apple Music results
              if (results.isNotEmpty) ...[
                _ResultSectionLabel(
                  label: 'Spotify & Apple Music',
                  count: results.length,
                ),
                ...results.asMap().entries.map(
                  (e) => _ResultRow(result: e.value, index: e.key),
                ),
              ],
              // YouTube results
              if (youtubeResults.isNotEmpty) ...[
                if (results.isNotEmpty) const SizedBox(height: 12),
                _ResultSectionLabel(
                  label: 'YouTube',
                  count: youtubeResults.length,
                ),
                ...youtubeResults.map((v) => _YoutubeVideoCard(video: v)),
              ],
            ],
          ),
        ),
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
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YoutubeVideoCard extends StatefulWidget {
  const _YoutubeVideoCard({required this.video});
  final YoutubeVideoResult video;

  @override
  State<_YoutubeVideoCard> createState() => _YoutubeVideoCardState();
}

class _YoutubeVideoCardState extends State<_YoutubeVideoCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: AppTheme.glass(
          radius: AppTheme.rMd,
          border: _hovered
              ? AppTheme.cyan.withValues(alpha: 0.32)
              : AppTheme.hairline,
          glowShadow: _hovered
              ? AppTheme.glow(AppTheme.cyan, blur: 20, opacity: 0.10)
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 48,
                child: v.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: v.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _thumbPlaceholder(),
                      )
                    : _thumbPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Title + channel
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v.channelName,
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
            const SizedBox(width: 12),
            // YouTube badge
            _SourceBadge(
              label: 'Y',
              color: const Color(0xFFFF0000),
              tooltip: 'YouTube',
            ),
            const SizedBox(width: 12),
            // Play button
            if (_hovered)
              _ActionButton(
                icon: Icons.play_circle_rounded,
                color: const Color(0xFFFF0000),
                tooltip: 'Open on YouTube',
                onTap: () async {
                  final uri = Uri.tryParse(v.youtubeUrl);
                  if (uri != null) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              )
            else
              const SizedBox(width: 31),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
    color: AppTheme.panelRaised,
    child: const Icon(
      Icons.play_circle_outline_rounded,
      color: AppTheme.textTertiary,
      size: 24,
    ),
  );
}

class _ResultRow extends ConsumerStatefulWidget {
  const _ResultRow({required this.result, required this.index});
  final _SearchResult result;
  final int index;

  @override
  ConsumerState<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends ConsumerState<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: AppTheme.glass(
          radius: AppTheme.rMd,
          border: _hovered
              ? AppTheme.cyan.withValues(alpha: 0.32)
              : AppTheme.hairline,
          glowShadow: _hovered
              ? AppTheme.glow(AppTheme.cyan, blur: 20, opacity: 0.10)
              : null,
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
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
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
                    ? CachedNetworkImage(
                        imageUrl: r.artworkUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _artPlaceholder(),
                      )
                    : _artPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Title + artist + album
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
                  if (r.albumName.isNotEmpty)
                    Text(
                      r.albumName,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Duration
            if (r.durationFormatted.isNotEmpty)
              Text(
                r.durationFormatted,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
            const SizedBox(width: 12),
            // Source badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r.hasSpotify)
                  _SourceBadge(
                    label: 'S',
                    color: const Color(0xFF1ED760),
                    tooltip: 'Spotify',
                  ),
                if (r.hasSpotify && (r.hasApple || r.hasYoutube))
                  const SizedBox(width: 4),
                if (r.hasApple)
                  _SourceBadge(
                    label: 'A',
                    color: const Color(0xFFFF7AB5),
                    tooltip: 'Apple Music',
                  ),
                if (r.hasApple && r.hasYoutube) const SizedBox(width: 4),
                if (r.hasYoutube)
                  _SourceBadge(
                    label: 'Y',
                    color: const Color(0xFFFF0000),
                    tooltip: 'YouTube',
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Action buttons
            if (_hovered) ...[
              // Play
              _ActionButton(
                icon: Icons.play_circle_rounded,
                color: AppTheme.cyan,
                tooltip: r.hasSpotify
                    ? 'Open in Spotify'
                    : 'Open in Apple Music',
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
    );
  }

  Widget _artPlaceholder() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [AppTheme.edge, AppTheme.panelRaised]),
    ),
    child: const Icon(
      Icons.music_note_rounded,
      color: AppTheme.textTertiary,
      size: 20,
    ),
  );

  void _play(_SearchResult r) async {
    final url = r.bestUrl;
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showAddToCrate(_SearchResult r) {
    final crateState = ref.read(crateProvider);
    final crates = crateState.crates.keys.toList();
    final trackId = r.hasSpotify
        ? 'spotify:${r.title}:${r.artist}'
        : 'apple:${r.title}:${r.artist}';

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
