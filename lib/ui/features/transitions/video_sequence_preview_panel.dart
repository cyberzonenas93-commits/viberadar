import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/track.dart';
import '../../../models/video_playback_item.dart';
import '../../../models/video_transition_score.dart';
import '../../../providers/video_transition_provider.dart';
import '../../../services/video_sequence_service.dart';
import 'video_transition_chip.dart';

/// Panel showing an ordered list of videos with transition score chips between
/// rows. Includes mode selector, reorder button, summary stats, and per-item
/// play buttons.
class VideoSequencePreviewPanel extends ConsumerStatefulWidget {
  const VideoSequencePreviewPanel({
    super.key,
    required this.tracks,
    required this.videoItems,
  });

  final List<Track> tracks;

  /// May be a subset of [tracks] — only tracks with a video item are shown
  /// in the sequence.
  final List<VideoPlaybackItem> videoItems;

  @override
  ConsumerState<VideoSequencePreviewPanel> createState() =>
      _VideoSequencePreviewPanelState();
}

class _VideoSequencePreviewPanelState
    extends ConsumerState<VideoSequencePreviewPanel> {
  VideoSequencePreview? _preview;
  bool _computing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Register all video items provided
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerItems();
      _buildPreview();
    });
  }

  @override
  void didUpdateWidget(VideoSequencePreviewPanel old) {
    super.didUpdateWidget(old);
    if (old.tracks != widget.tracks || old.videoItems != widget.videoItems) {
      _registerItems();
      _buildPreview();
    }
  }

  void _registerItems() {
    final notifier = ref.read(videoTransitionProvider.notifier);
    for (final item in widget.videoItems) {
      notifier.registerVideoItem(item.trackId, item);
    }
  }

  void _buildPreview() {
    if (!mounted) return;
    setState(() {
      _computing = true;
      _error = null;
    });

    try {
      final preview = ref
          .read(videoTransitionProvider.notifier)
          .buildPreviewForCrate(widget.tracks);

      if (mounted) {
        setState(() {
          _preview = preview;
          _computing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _computing = false;
        });
      }
    }
  }

  void _onModeChanged(VideoTransitionMode? newMode) {
    if (newMode == null) return;
    ref.read(videoTransitionProvider.notifier).setMode(newMode);
    _buildPreview();
  }

  Future<void> _playItem(VideoPlaybackItem item) async {
    if (item.sourceType == VideoSourceType.youtube &&
        item.youtubeVideoId != null) {
      final url = Uri.parse(item.youtubeWatchUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }
    // Local files: playback handled by the main audio flow — no action here.
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(videoTransitionModeProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.edge.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(mode),
          const Divider(color: AppTheme.edge, height: 1),
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(VideoTransitionMode mode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        spacing: 10,
        children: [
          const Icon(Icons.video_library_rounded,
              size: 16, color: AppTheme.violet),
          const Text(
            'Video Sequence',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Mode dropdown
          _ModeDropdown(value: mode, onChanged: _onModeChanged),
          const SizedBox(width: 6),
          // Reorder button
          _ReorderButton(
            onPressed: _computing ? null : _buildPreview,
            loading: _computing,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_computing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return _ErrorView(message: _error!);
    }

    if (widget.videoItems.isEmpty) {
      return const _EmptyVideoState();
    }

    final preview = _preview;
    if (preview == null || preview.orderedItems.isEmpty) {
      return const _EmptyVideoState();
    }

    return Column(
      children: [
        _buildSummaryBar(preview),
        const Divider(color: AppTheme.edge, height: 1),
        Flexible(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _listItemCount(preview),
            itemBuilder: (context, index) =>
                _buildListItem(context, index, preview),
          ),
        ),
      ],
    );
  }

  int _listItemCount(VideoSequencePreview preview) {
    // Each video = 1 row, each transition = 1 row between them
    final videos = preview.orderedItems.length;
    final transitions = preview.transitions.length;
    return videos + transitions;
  }

  Widget _buildListItem(
    BuildContext context,
    int index,
    VideoSequencePreview preview,
  ) {
    // Even indices → video items; odd indices → transition chips
    final isVideo = index % 2 == 0;
    final videoIndex = index ~/ 2;
    final transitionIndex = (index - 1) ~/ 2;

    if (isVideo) {
      if (videoIndex >= preview.orderedItems.length) return const SizedBox();
      final item = preview.orderedItems[videoIndex];
      final track = widget.tracks.firstWhere(
        (t) => t.id == item.trackId,
        orElse: () => widget.tracks.first,
      );
      return _VideoItemRow(
        item: item,
        track: track,
        index: videoIndex + 1,
        onPlay: () => _playItem(item),
      );
    } else {
      // Transition chip row
      if (transitionIndex >= preview.transitions.length) return const SizedBox();
      final transition = preview.transitions[transitionIndex];
      final fromItem = preview.orderedItems[transitionIndex];
      final toItem = preview.orderedItems[transitionIndex + 1];
      return _TransitionRow(
        score: transition,
        fromItem: fromItem,
        toItem: toItem,
      );
    }
  }

  Widget _buildSummaryBar(VideoSequencePreview preview) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          _StatBadge(
            label: 'Videos',
            value: '${preview.orderedItems.length}',
            color: AppTheme.cyan,
          ),
          _StatBadge(
            label: 'Avg Score',
            value: '${(preview.averageScore * 100).round()}%',
            color: preview.averageScore >= 0.65
                ? AppTheme.lime
                : preview.averageScore >= 0.50
                    ? AppTheme.amber
                    : AppTheme.pink,
          ),
          if (preview.riskyTransitions > 0)
            _StatBadge(
              label: 'Risky',
              value: '${preview.riskyTransitions}',
              color: AppTheme.pink,
            ),
          const Spacer(),
          Text(
            preview.mode.label,
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _VideoItemRow extends StatelessWidget {
  const _VideoItemRow({
    required this.item,
    required this.track,
    required this.index,
    required this.onPlay,
  });

  final VideoPlaybackItem item;
  final Track track;
  final int index;
  final VoidCallback onPlay;

  IconData get _sourceIcon => item.sourceType == VideoSourceType.youtube
      ? Icons.play_circle_filled_rounded
      : Icons.folder_open_rounded;

  Color get _sourceColor => item.sourceType == VideoSourceType.youtube
      ? AppTheme.pink
      : AppTheme.cyan;

  String get _typeLabel {
    if (item.isLivePerformance) return 'Live';
    if (item.isLyricVideo) return 'Lyric';
    if (item.isOfficialVideo) return 'Official';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        spacing: 10,
        children: [
          // Index badge
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Source icon
          Icon(_sourceIcon, size: 16, color: _sourceColor),
          // Title & track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title ?? track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [track.artist, if (_typeLabel.isNotEmpty) _typeLabel]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Play button (YouTube only opens browser; local is handled by main flow)
          if (item.sourceType == VideoSourceType.youtube &&
              item.youtubeVideoId != null)
            IconButton(
              onPressed: onPlay,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              tooltip: 'Open in browser',
              color: AppTheme.textSecondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

class _TransitionRow extends StatelessWidget {
  const _TransitionRow({
    required this.score,
    required this.fromItem,
    required this.toItem,
  });

  final VideoTransitionScore score;
  final VideoPlaybackItem fromItem;
  final VideoPlaybackItem toItem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        spacing: 6,
        children: [
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.only(left: 11),
            color: AppTheme.edge,
          ),
          const Spacer(),
          VideoTransitionChip(
            score: score,
            fromItem: fromItem,
            toItem: toItem,
            compact: true,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({required this.value, required this.onChanged});

  final VideoTransitionMode value;
  final ValueChanged<VideoTransitionMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.edge),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<VideoTransitionMode>(
          value: value,
          onChanged: onChanged,
          dropdownColor: AppTheme.panel,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 12,
          ),
          iconSize: 14,
          iconEnabledColor: AppTheme.textSecondary,
          items: VideoTransitionMode.values
              .map(
                (m) => DropdownMenuItem(
                  value: m,
                  child: Text(m.label),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _ReorderButton extends StatelessWidget {
  const _ReorderButton({required this.onPressed, required this.loading});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.violet.withValues(alpha: 0.15),
          foregroundColor: AppTheme.violet,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppTheme.violet.withValues(alpha: 0.4)),
          ),
          elevation: 0,
        ),
        icon: loading
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.shuffle_rounded, size: 14),
        label: const Text('Reorder', style: TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyVideoState extends StatelessWidget {
  const _EmptyVideoState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.video_library_outlined,
              size: 40, color: AppTheme.textTertiary),
          SizedBox(height: 12),
          Text(
            'No video items available',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Attach YouTube or local video files to tracks to use the '
            'video sequence feature.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 32, color: AppTheme.pink),
          const SizedBox(height: 8),
          const Text(
            'Failed to build sequence',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
