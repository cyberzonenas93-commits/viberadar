part of 'greatest_of_screen.dart';

class _HeroCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _HeroCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final trendPct = (t.trendScore * 100).toInt();
    final greatestPct = (widget.greatestScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.amber.withValues(alpha: _hovered ? 0.18 : 0.12),
                AppTheme.panel,
                AppTheme.panel,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Background artwork (blurred)
              if (t.artworkUrl.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.6),
                        colorBlendMode: BlendMode.darken,
                        errorWidget: (_, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              // Content overlay
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    // Large artwork
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: t.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: t.artworkUrl,
                              width: 180,
                              height: 180,
                              fit: BoxFit.cover,
                              errorWidget: (_, e, s) => _ArtPlaceholder(size: 180),
                            )
                          : _ArtPlaceholder(size: 180),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Crown + rank badge
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.amber, Color(0xFFFF8C00)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.emoji_events_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('#1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.violet.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(t.genre, style: const TextStyle(color: AppTheme.violet, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 8),
                              SourceBadges(sources: t.effectiveSources, compact: true),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            t.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.artist,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          // Meta row
                          Row(
                            children: [
                              _MetaPill(icon: Icons.speed_rounded, text: formatBpm(t.bpm)),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.music_note_rounded, text: t.keySignature),
                              const SizedBox(width: 6),
                              _MetaPill(icon: Icons.public_rounded, text: t.leadRegion),
                              const Spacer(),
                              // Score pair
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                                  const SizedBox(height: 4),
                                  _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
                                  const SizedBox(height: 4),
                                  Text('$greatestPct / $trendPct',
                                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 9)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Play button overlay
              if (_bestUrl(t) != null)
                Positioned(
                  left: 24 + 180 - 20,
                  bottom: 24,
                  child: GestureDetector(
                    onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.cyan,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.cyan.withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunnerUpCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _RunnerUpCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_RunnerUpCard> createState() => _RunnerUpCardState();
}

class _RunnerUpCardState extends State<_RunnerUpCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final rank = widget.rank;
    final accent = rank == 2 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 124,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            border: Border.all(color: accent.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: _hovered ? 0.1 : 0.06),
                AppTheme.panel,
              ],
            ),
          ),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: t.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                        errorWidget: (_, e, s) => _ArtPlaceholder(size: 92),
                      )
                    : _ArtPlaceholder(size: 92),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('#$rank', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 10)),
                        ),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                            const SizedBox(height: 3),
                            _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.title,
                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.artist,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('${formatBpm(t.bpm)} BPM', style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 8),
                        Text(t.keySignature, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10)),
                        const SizedBox(width: 8),
                        Text(t.genre, style: TextStyle(color: AppTheme.violet.withValues(alpha: 0.7), fontSize: 10)),
                        const SizedBox(width: 8),
                        SourceBadges(sources: t.effectiveSources, compact: true),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid card for ranks 4+
// ─────────────────────────────────────────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final double greatestScore;
  final WidgetRef ref;
  const _TrackCard({required this.track, required this.rank, required this.greatestScore, required this.ref});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) => showTrackActionMenu(context, widget.ref, t, position: details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork with rank overlay
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _ArtPlaceholder(size: 120, rounded: false),
                              )
                            : _ArtPlaceholder(size: 120, rounded: false),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.rank}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10),
                        ),
                      ),
                    ),
                    // Score badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ScoreBadge(value: widget.greatestScore, color: AppTheme.amber, prefix: 'G'),
                          const SizedBox(height: 3),
                          _ScoreBadge(value: t.trendScore, color: AppTheme.cyan, prefix: 'T'),
                        ],
                      ),
                    ),
                    // Play button on hover
                    if (_hovered && _bestUrl(t) != null)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          ),
                          child: Center(
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.cyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: AppTheme.cyan.withValues(alpha: 0.5), blurRadius: 16),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Info section
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
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          formatBpm(t.bpm),
                          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.edge.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(t.keySignature, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        SourceBadges(sources: t.effectiveSources, compact: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _ScoreBar(label: 'G', value: widget.greatestScore, color: AppTheme.amber),
                    const SizedBox(height: 3),
                    _ScoreBar(label: 'T', value: t.trendScore, color: AppTheme.cyan),
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

// ─────────────────────────────────────────────────────────────────────────────
// Platform track row (for Spotify/Apple Music results)
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformTrackRow extends StatefulWidget {
  const _PlatformTrackRow({required this.track, required this.index});
  final PlatformTrackResult track;
  final int index;

  @override
  State<_PlatformTrackRow> createState() => _PlatformTrackRowState();
}

class _PlatformTrackRowState extends State<_PlatformTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? AppTheme.panelRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text('${widget.index + 1}', textAlign: TextAlign.right,
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: t.artworkUrl != null
                  ? CachedNetworkImage(imageUrl: t.artworkUrl!, width: 36, height: 36, fit: BoxFit.cover)
                  : Container(width: 36, height: 36, color: AppTheme.panelRaised,
                      child: const Icon(Icons.music_note_rounded, color: AppTheme.textTertiary, size: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(t.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (t.durationMs > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${t.durationMs ~/ 60000}:${((t.durationMs % 60000) ~/ 1000).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
              ),
            if (t.spotifyUrl != null)
              _PlayBtn(icon: Icons.graphic_eq_rounded, color: const Color(0xFF1ED760), url: t.spotifyUrl!, tip: 'Spotify'),
            if (t.appleUrl != null)
              _PlayBtn(icon: Icons.music_note_rounded, color: const Color(0xFFFF7AB5), url: t.appleUrl!, tip: 'Apple Music'),
          ],
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.icon, required this.color, required this.url, required this.tip});
  final IconData icon;
  final Color color;
  final String url;
  final String tip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Play on $tip',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            final uri = Uri.tryParse(url);
            if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      ),
    );
  }
}
