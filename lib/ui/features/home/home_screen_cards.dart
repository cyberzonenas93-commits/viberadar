part of 'home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Hero #1 card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatefulWidget {
  final Track track;
  final WidgetRef ref;
  const _HeroCard({required this.track, required this.ref});
  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    final compact = MediaQuery.sizeOf(context).width < 700;
    final cardHeight = compact ? 210.0 : 240.0;
    final artSize = compact ? 98.0 : 170.0;
    final contentPadding = compact ? 16.0 : 22.0;
    final gap = compact ? 14.0 : 22.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(
          context,
          widget.ref,
          t,
          position: d.globalPosition,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.amber.withValues(alpha: _hovered ? 0.15 : 0.08),
                AppTheme.panel,
                AppTheme.panel,
              ],
            ),
          ),
          child: Stack(
            children: [
              if (t.artworkUrl.isNotEmpty)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ShaderMask(
                      shaderCallback: (b) => LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ).createShader(b),
                      blendMode: BlendMode.dstIn,
                      child: CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.5),
                        colorBlendMode: BlendMode.darken,
                        errorWidget: (_, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(contentPadding),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: t.artworkUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: t.artworkUrl,
                              width: artSize,
                              height: artSize,
                              fit: BoxFit.cover,
                              errorWidget: (_, e, s) =>
                                  _ArtPlaceholder(artSize),
                            )
                          : _ArtPlaceholder(artSize),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.amber, Color(0xFFFF8C00)],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.emoji_events_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '#1 TRENDING',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (t.genre.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.violet.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t.genre,
                                    style: const TextStyle(
                                      color: AppTheme.violet,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              SourceBadges(
                                sources: t.effectiveSources,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: compact ? 18 : 20,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.artist,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: compact ? 13 : 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Pill('${formatBpm(t.bpm)} BPM'),
                              _Pill(t.keySignature),
                              _Pill(t.leadRegion),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.cyan.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$score',
                                  style: const TextStyle(
                                    color: AppTheme.cyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
// Runner-up card (#2, #3)
// ─────────────────────────────────────────────────────────────────────────────

class _RunnerCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  final Color accent;
  const _RunnerCard({
    required this.track,
    required this.rank,
    required this.ref,
    required this.accent,
  });
  @override
  State<_RunnerCard> createState() => _RunnerCardState();
}

class _RunnerCardState extends State<_RunnerCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(
          context,
          widget.ref,
          t,
          position: d.globalPosition,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 114,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.accent.withValues(alpha: _hovered ? 0.1 : 0.05),
                AppTheme.panel,
              ],
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: t.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: t.artworkUrl,
                        width: 86,
                        height: 86,
                        fit: BoxFit.cover,
                        errorWidget: (_, e, s) => _ArtPlaceholder(86),
                      )
                    : _ArtPlaceholder(86),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '#${widget.rank}',
                            style: TextStyle(
                              color: widget.accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$score',
                          style: const TextStyle(
                            color: AppTheme.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      t.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard track grid card
// ─────────────────────────────────────────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final WidgetRef ref;
  const _TrackCard({
    required this.track,
    required this.rank,
    required this.ref,
  });
  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(
          context,
          widget.ref,
          t,
          position: d.globalPosition,
        ),
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
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _ArtPlaceholderFull(),
                              )
                            : _ArtPlaceholderFull(),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _Badge(
                        '#${widget.rank}',
                        Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Badge(
                        '$score',
                        AppTheme.cyan.withValues(alpha: 0.9),
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
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          formatBpm(t.bpm),
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 4),
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
                            t.keySignature,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        SourceBadges(
                          sources: t.effectiveSources,
                          compact: true,
                        ),
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
// Rising fast horizontal card
// ─────────────────────────────────────────────────────────────────────────────

class _RisingCard extends StatefulWidget {
  final Track track;
  final WidgetRef ref;
  const _RisingCard({required this.track, required this.ref});
  @override
  State<_RisingCard> createState() => _RisingCardState();
}

class _RisingCardState extends State<_RisingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final score = (t.trendScore * 100).toInt();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (d) => showTrackActionMenu(
          context,
          widget.ref,
          t,
          position: d.globalPosition,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 170,
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.pink.withValues(alpha: _hovered ? 0.4 : 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Artwork top
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13),
                      ),
                      child: SizedBox.expand(
                        child: t.artworkUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: t.artworkUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, e, s) => _ArtPlaceholderFull(),
                              )
                            : _ArtPlaceholderFull(),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.pink.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.trending_up_rounded,
                              color: Colors.white,
                              size: 10,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'RISING',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Badge(
                        '$score',
                        AppTheme.cyan.withValues(alpha: 0.9),
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
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    SourceBadges(sources: t.effectiveSources, compact: true),
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
