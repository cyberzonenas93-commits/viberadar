import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/video_playback_item.dart';

/// Embedded YouTube player using an iframe embed via webview_flutter.
///
/// Loads `youtube.com/embed/{videoId}` — the official YouTube embed endpoint.
/// No stream extraction, no youtube_explode, fully compliant.
class YouTubePlayerPanel extends StatefulWidget {
  const YouTubePlayerPanel({
    super.key,
    required this.item,
    this.onClose,
  });

  final VideoPlaybackItem item;
  final VoidCallback? onClose;

  @override
  State<YouTubePlayerPanel> createState() => _YouTubePlayerPanelState();
}

class _YouTubePlayerPanelState extends State<YouTubePlayerPanel> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (_) {
          if (mounted) setState(() { _isLoading = false; _hasError = true; });
        },
      ))
      ..loadRequest(Uri.parse(_embedUrl));
  }

  String get _embedUrl {
    final videoId = widget.item.youtubeVideoId ?? '';
    return 'https://www.youtube.com/embed/$videoId'
        '?autoplay=1&playsinline=1&rel=0&modestbranding=1';
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
            const Icon(Icons.play_circle_fill_rounded,
                color: Color(0xFFFF4B4B), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title ?? 'YouTube Video',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.item.channelName != null)
                    Text(
                      widget.item.channelName!,
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Open in browser
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(widget.item.youtubeWatchUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.open_in_new_rounded,
                    color: AppTheme.textSecondary, size: 14),
              ),
            ),
            const SizedBox(width: 4),
            // Close
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
          child: _hasError
              ? _ErrorFallback(
                  watchUrl: widget.item.youtubeWatchUrl,
                  thumbnail: widget.item.youtubeThumbnail,
                )
              : Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_isLoading)
                      _LoadingOverlay(
                          thumbnail: widget.item.youtubeThumbnail),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({this.thumbnail});
  final String? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Color(0xFFFF4B4B),
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Loading video...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback({required this.watchUrl, this.thumbnail});
  final String watchUrl;
  final String? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.textSecondary, size: 28),
            const SizedBox(height: 8),
            const Text(
              'Could not load embedded player',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(watchUrl),
                mode: LaunchMode.externalApplication,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4B4B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFFF4B4B).withValues(alpha: 0.4)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new_rounded,
                      color: Color(0xFFFF4B4B), size: 14),
                  SizedBox(width: 6),
                  Text('Open in YouTube',
                      style: TextStyle(
                          color: Color(0xFFFF4B4B),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
