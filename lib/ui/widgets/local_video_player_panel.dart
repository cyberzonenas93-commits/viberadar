import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../models/video_playback_item.dart';

/// Local video file player using the `video_player` package.
///
/// Supports .mp4, .mov, .m4v files. If the file cannot be played,
/// shows a fallback with "Open in Finder" option.
class LocalVideoPlayerPanel extends StatefulWidget {
  const LocalVideoPlayerPanel({
    super.key,
    required this.item,
    this.onClose,
  });

  final VideoPlaybackItem item;
  final VoidCallback? onClose;

  @override
  State<LocalVideoPlayerPanel> createState() => _LocalVideoPlayerPanelState();
}

class _LocalVideoPlayerPanelState extends State<LocalVideoPlayerPanel> {
  VideoPlayerController? _controller;
  bool _isInitializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final path = widget.item.localFilePath;
    if (path == null || !File(path).existsSync()) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = 'File not found: ${path ?? "unknown"}';
        });
      }
      return;
    }

    try {
      _controller = VideoPlayerController.file(File(path));
      await _controller!.initialize();
      await _controller!.play();
      if (mounted) setState(() => _isInitializing = false);

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = 'Unsupported format: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: AppTheme.panelRaised,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            const Icon(Icons.video_file_rounded,
                color: AppTheme.cyan, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.item.title ??
                    widget.item.localFilePath?.split('/').last ??
                    'Local Video',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Open in Finder
            if (widget.item.localFilePath != null)
              GestureDetector(
                onTap: () => Process.run('open', ['-R', widget.item.localFilePath!]),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.folder_open_rounded,
                      color: AppTheme.textSecondary, size: 14),
                ),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: widget.onClose,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded,
                    color: AppTheme.textSecondary, size: 16),
              ),
            ),
          ]),
        ),

        // Video area
        SizedBox(
          width: 400,
          height: 225,
          child: _error != null
              ? _ErrorView(
                  error: _error!,
                  filePath: widget.item.localFilePath,
                )
              : _isInitializing
                  ? const _LoadingView()
                  : _controller != null && _controller!.value.isInitialized
                      ? _VideoView(controller: _controller!)
                      : const _LoadingView(),
        ),

        // Controls
        if (_controller != null && _controller!.value.isInitialized)
          _ControlBar(controller: _controller!),
      ],
    );
  }
}

class _VideoView extends StatelessWidget {
  const _VideoView({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final position = controller.value.position;
    final duration = controller.value.duration;
    final isPlaying = controller.value.isPlaying;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: AppTheme.panelRaised,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(children: [
        // Play/pause
        GestureDetector(
          onTap: () => isPlaying ? controller.pause() : controller.play(),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: AppTheme.cyan,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        // Time
        Text(
          _formatTime(position),
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10),
        ),
        const SizedBox(width: 8),
        // Seek bar
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              activeTrackColor: AppTheme.cyan,
              inactiveTrackColor: AppTheme.edge,
              thumbColor: AppTheme.cyan,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            ),
            child: Slider(
              value: duration.inMilliseconds > 0
                  ? position.inMilliseconds / duration.inMilliseconds
                  : 0.0,
              onChanged: (v) {
                final target = Duration(
                    milliseconds: (v * duration.inMilliseconds).round());
                controller.seekTo(target);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatTime(duration),
          style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 10),
        ),
      ]),
    );
  }

  String _formatTime(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                color: AppTheme.cyan, strokeWidth: 2),
          ),
          SizedBox(height: 8),
          Text('Loading video...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, this.filePath});
  final String error;
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.textSecondary, size: 28),
          const SizedBox(height: 8),
          Text(error,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11),
              textAlign: TextAlign.center),
          if (filePath != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Process.run('open', ['-R', filePath!]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.cyan.withValues(alpha: 0.3)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open_rounded,
                      color: AppTheme.cyan, size: 14),
                  SizedBox(width: 6),
                  Text('Show in Finder',
                      style: TextStyle(
                          color: AppTheme.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
