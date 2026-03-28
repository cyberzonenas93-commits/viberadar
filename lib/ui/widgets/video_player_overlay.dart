import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/video_playback_item.dart';
import '../../providers/video_player_provider.dart';
import 'local_video_player_panel.dart';
import 'youtube_player_panel.dart';

/// Floating video player overlay that appears in the bottom-right of the app.
///
/// Switches between [YouTubePlayerPanel] and [LocalVideoPlayerPanel] based on
/// the current [VideoPlayerState.item.sourceType].
///
/// Draggable, dismissible, and non-blocking — does not interfere with the
/// existing audio player or any navigation.
class VideoPlayerOverlay extends ConsumerStatefulWidget {
  const VideoPlayerOverlay({super.key});

  @override
  ConsumerState<VideoPlayerOverlay> createState() => _VideoPlayerOverlayState();
}

class _VideoPlayerOverlayState extends ConsumerState<VideoPlayerOverlay> {
  Offset _position = const Offset(double.infinity, double.infinity);
  bool _positioned = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoPlayerProvider);
    if (!state.isVisible) return const SizedBox.shrink();

    // Default position: bottom-right with padding
    if (!_positioned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final size = MediaQuery.of(context).size;
        setState(() {
          _position = Offset(size.width - 424, size.height - 320);
          _positioned = true;
        });
      });
    }

    return Positioned(
      left: _position.dx.isFinite ? _position.dx : null,
      top: _position.dy.isFinite ? _position.dy : null,
      right: !_position.dx.isFinite ? 24 : null,
      bottom: !_position.dy.isFinite ? 80 : null,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _position = Offset(
              _position.dx + d.delta.dx,
              _position.dy + d.delta.dy,
            );
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 400,
            decoration: BoxDecoration(
              color: AppTheme.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.edge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildContent(state),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(VideoPlayerState state) {
    final onClose = () => ref.read(videoPlayerProvider.notifier).close();

    // Loading state
    if (state.isLoading) {
      return _LoadingPanel(
        track: state.track,
        onClose: onClose,
      );
    }

    // Error state
    if (state.error != null) {
      return _ErrorPanel(
        error: state.error!,
        onClose: onClose,
      );
    }

    // Playing state
    final item = state.item;
    if (item == null) return const SizedBox.shrink();

    if (item.sourceType == VideoSourceType.youtube) {
      return YouTubePlayerPanel(item: item, onClose: onClose);
    } else {
      return LocalVideoPlayerPanel(item: item, onClose: onClose);
    }
  }
}

// ── Loading panel ─────────────────────────────────────────────────────────────

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel({this.track, required this.onClose});
  final dynamic track;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: AppTheme.panelRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(children: [
          const Icon(Icons.videocam_rounded,
              color: Color(0xFFFF4B4B), size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Finding video...',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close_rounded,
                color: AppTheme.textSecondary, size: 16),
          ),
        ]),
      ),
      const SizedBox(
        width: 400,
        height: 225,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    color: Color(0xFFFF4B4B), strokeWidth: 2),
              ),
              SizedBox(height: 10),
              Text('Searching YouTube...',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ── Error panel ───────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onClose});
  final String error;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: AppTheme.panelRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(children: [
          const Icon(Icons.videocam_off_rounded,
              color: AppTheme.textSecondary, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Video Not Found',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close_rounded,
                color: AppTheme.textSecondary, size: 16),
          ),
        ]),
      ),
      SizedBox(
        width: 400,
        height: 120,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
