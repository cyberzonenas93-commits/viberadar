part of 'artists_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _FilterDropdown({required this.label, required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: options.contains(value) ? value : options.first,
              isDense: true,
              dropdownColor: AppTheme.panelRaised,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final Color color;
  const _InfoChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String name;
  final bool large;
  const _AvatarFallback({required this.name, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: large ? double.infinity : 100,
      height: large ? double.infinity : 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.violet.withValues(alpha: 0.3), AppTheme.pink.withValues(alpha: 0.2)],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(color: AppTheme.violet, fontSize: large ? 48 : 36, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SmallArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: AppTheme.edge,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.edge, AppTheme.panelRaised]),
      ),
      child: const Center(child: Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 32)),
    );
  }
}

class _ViewTab extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  const _ViewTab({required this.label, required this.subtitle, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.violet.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? AppTheme.violet.withValues(alpha: 0.3) : AppTheme.edge.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: isActive ? AppTheme.violet : AppTheme.textSecondary, fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isActive ? AppTheme.violet : AppTheme.textTertiary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(subtitle, style: TextStyle(color: isActive ? AppTheme.violet : AppTheme.textTertiary, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogTrackRow extends StatefulWidget {
  final Track track;
  final int rank;
  final bool isSelected;
  final VoidCallback onToggleSelect;

  const _CatalogTrackRow({
    required this.track,
    required this.rank,
    required this.isSelected,
    required this.onToggleSelect,
  });

  @override
  State<_CatalogTrackRow> createState() => _CatalogTrackRowState();
}

class _CatalogTrackRowState extends State<_CatalogTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppTheme.violet.withValues(alpha: 0.08)
              : _hovered
                  ? AppTheme.panelRaised
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: widget.isSelected
              ? Border.all(color: AppTheme.violet.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            // Checkbox
            GestureDetector(
              onTap: widget.onToggleSelect,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: widget.isSelected ? AppTheme.violet : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.isSelected ? AppTheme.violet : AppTheme.edge,
                    width: 1.5,
                  ),
                ),
                child: widget.isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Rank
            SizedBox(
              width: 28,
              child: Text(
                '${widget.rank}',
                style: TextStyle(
                  color: widget.rank <= 3 ? AppTheme.amber : AppTheme.textTertiary,
                  fontWeight: widget.rank <= 3 ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
            // Artwork
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: t.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: t.artworkUrl, width: 44, height: 44, fit: BoxFit.cover, errorWidget: (_, e, s) => _SmallArtPlaceholder())
                  : _SmallArtPlaceholder(),
            ),
            const SizedBox(width: 14),
            // Title + genre
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
            // BPM
            SizedBox(
              width: 55,
              child: Text('${formatBpm(t.bpm)} BPM', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 10),
            // Key
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.edge.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(5)),
              child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            // Region
            Text(t.leadRegion, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            const SizedBox(width: 12),
            // Score
            SizedBox(
              width: 36,
              child: Text('$score', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700, fontSize: 14), textAlign: TextAlign.right),
            ),
            const SizedBox(width: 8),
            // Play
            if (_bestUrl(t) != null)
              IconButton(
                icon: const Icon(Icons.play_circle_filled_rounded, color: AppTheme.cyan, size: 22),
                onPressed: () async {
                  final uri = Uri.tryParse(_bestUrl(t)!);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Play',
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pure helper functions
// ─────────────────────────────────────────────────────────────────────────────

String? _bestUrl(Track track) {
  const priority = ['spotify', 'apple', 'youtube', 'deezer', 'soundcloud', 'audius'];
  for (final key in priority) {
    final url = track.platformLinks[key];
    if (url != null && url.isNotEmpty) return url;
  }
  return track.platformLinks.values.firstOrNull;
}

/// Merge Spotify and Apple Music track lists into a single deduplicated list.
/// Tracks with matching names (case-insensitive) are combined into one entry.
List<_UnifiedTrack> _mergeToUnified(
  List<SpotifyTrackInfo> spotifyTracks,
  List<AppleMusicTrack> appleTracks,
) {
  final unified = <String, _UnifiedTrack>{};

  // Add Spotify tracks first
  for (final t in spotifyTracks) {
    final key = t.name.toLowerCase().trim();
    unified[key] = _UnifiedTrack(
      name: t.name,
      albumName: t.albumName,
      artworkUrl: t.albumArt,
      durationMs: t.durationMs,
      releaseDate: t.releaseDate,
      spotifyId: t.id,
      spotifyUrl: t.spotifyUrl,
      popularity: t.popularity,
      trackNumber: t.trackNumber,
      isTopTrack: t.isTopTrack,
    );
  }

  // Merge in Apple Music tracks
  for (final t in appleTracks) {
    final key = t.name.toLowerCase().trim();
    final existing = unified[key];
    if (existing != null) {
      // Enrich Spotify entry with Apple data
      unified[key] = _UnifiedTrack(
        name: existing.name,
        albumName: existing.albumName,
        artworkUrl: existing.artworkUrl ?? t.artworkUrl,
        durationMs: existing.durationMs > 0 ? existing.durationMs : t.durationMs,
        releaseDate: existing.releaseDate ?? t.releaseDate,
        spotifyId: existing.spotifyId,
        spotifyUrl: existing.spotifyUrl,
        popularity: existing.popularity,
        trackNumber: existing.trackNumber,
        isTopTrack: existing.isTopTrack,
        appleId: t.id,
        appleUrl: t.appleUrl,
        previewUrl: t.previewUrl,
      );
    } else {
      // Apple-only track
      unified[key] = _UnifiedTrack(
        name: t.name,
        albumName: t.albumName,
        artworkUrl: t.artworkUrl,
        durationMs: t.durationMs,
        releaseDate: t.releaseDate,
        appleId: t.id,
        appleUrl: t.appleUrl,
        previewUrl: t.previewUrl,
      );
    }
  }

  return unified.values.toList();
}
