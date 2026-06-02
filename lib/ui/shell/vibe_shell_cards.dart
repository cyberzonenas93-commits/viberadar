part of 'vibe_shell.dart';

/// Shared artwork grid card used by _RegionsView, _GenresView, _SetBuilderView.
class _ShellTrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final int score;
  final VoidCallback? onTap;
  final WidgetRef? ref;
  const _ShellTrackCard({
    required this.track,
    required this.rank,
    required this.score,
    this.onTap,
    this.ref,
  });

  @override
  State<_ShellTrackCard> createState() => _ShellTrackCardState();
}

class _ShellTrackCardState extends State<_ShellTrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final isTop3 = widget.rank <= 3;
    final rankColor = widget.rank == 1
        ? AppTheme.amber
        : widget.rank == 2
        ? const Color(0xFFC0C0C0)
        : widget.rank == 3
        ? const Color(0xFFCD7F32)
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          if (widget.onTap != null) {
            widget.onTap!();
          } else {
            // Direct play — open the best platform URL
            _openShellTrack(t);
            // Also activate in detail panel if ref available
            if (widget.ref != null) {
              widget.ref!
                  .read(workspaceControllerProvider.notifier)
                  .activateTrack(t.id);
            }
          }
        },
        onSecondaryTapDown: (details) {
          // Right-click shows the full action menu
          if (widget.ref != null) {
            showTrackActionMenu(
              context,
              widget.ref!,
              t,
              position: details.globalPosition,
            );
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.panelRaised : AppTheme.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isTop3
                  ? rankColor!.withValues(alpha: _hovered ? 0.5 : 0.3)
                  : AppTheme.edge.withValues(alpha: _hovered ? 0.6 : 0.35),
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
                                errorWidget: (_, _, _) =>
                                    _ShellArtPlaceholder(),
                              )
                            : _ShellArtPlaceholder(),
                      ),
                    ),
                    // Rank badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isTop3
                              ? rankColor!.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${widget.rank}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isTop3
                                ? FontWeight.w800
                                : FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Score badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.cyan.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${widget.score}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    // Play hover overlay
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
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          '${t.bpm}',
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

class _ShellArtPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.edge, AppTheme.panelRaised],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppTheme.textTertiary,
          size: 32,
        ),
      ),
    );
  }
}

Future<void> _openShellTrack(Track track) async {
  const priority = [
    'spotify',
    'apple',
    'youtube',
    'deezer',
    'soundcloud',
    'audius',
  ];
  String? url;
  for (final key in priority) {
    final u = track.platformLinks[key];
    if (u != null && u.isNotEmpty) {
      url = u;
      break;
    }
  }
  url ??= track.platformLinks.values.firstOrNull;
  if (url == null) return;
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Proxy to make Track fields accessible as dynamic properties for export manifest.
class _TrackExportProxy {
  final Track t;
  _TrackExportProxy(this.t);
  String get title => t.title;
  String get artist => t.artist;
  int get bpm => t.bpm;
  String get key => t.keySignature;
  String? get spotifyUrl => t.platformLinks['spotify'];
  String? get appleUrl => t.platformLinks['apple'];
  bool get resolved => t.platformLinks.isNotEmpty;
}
