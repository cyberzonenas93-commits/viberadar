import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/streaming_provider.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmt(double seconds) {
  final s = seconds.toInt().clamp(0, 9999);
  final m = s ~/ 60;
  final sec = s % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

// ── Apple Music Mini-Player Bar ───────────────────────────────────────────────

class AppleMusicPlayerBar extends ConsumerWidget {
  const AppleMusicPlayerBar({super.key});

  static const double barHeight = 72.0;
  static const Color _amPink = Color(0xFFFC3C44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final am = ref.watch(appleMusicProvider);
    final notifier = ref.read(appleMusicProvider.notifier);

    if (am.currentTrack == null) return const SizedBox.shrink();

    final track = am.currentTrack!;
    final position = am.positionSeconds;
    final duration = am.durationSeconds;
    final progress = am.progress;

    return Container(
      height: barHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D14),
        border: Border(
          top: BorderSide(color: _amPink, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Artwork ──────────────────────────────────────────────────────
          SizedBox(
            width: barHeight,
            height: barHeight,
            child: _Artwork(url: track.artworkUrl),
          ),

          // ── Track info + progress ─────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title + artist
                  Row(
                    children: [
                      const Icon(Icons.music_note_rounded, color: _amPink, size: 11),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          track.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    track.artist,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Progress row
                  Row(
                    children: [
                      Text(
                        _fmt(position),
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _ProgressSlider(
                          progress: progress,
                          onSeek: duration > 0
                              ? (frac) => notifier.seek(frac * duration)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        duration > 0 ? '-${_fmt((duration - position).clamp(0, duration))}' : '--:--',
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Controls ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Play / Pause
                _ControlBtn(
                  onTap: () => notifier.togglePlayPause(),
                  child: am.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: _amPink,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          am.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),

                const SizedBox(width: 8),

                // Stop / close
                _ControlBtn(
                  onTap: () => notifier.stop(),
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Progress slider ───────────────────────────────────────────────────────────

class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({required this.progress, required this.onSeek});

  final double progress;
  final ValueChanged<double>? onSeek;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.progress).clamp(0.0, 1.0);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFFFC3C44),
        inactiveTrackColor: AppTheme.edge,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        trackHeight: 2,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      ),
      child: Slider(
        value: value,
        onChangeStart: (_) => setState(() => _dragging = value),
        onChanged: widget.onSeek != null
            ? (v) => setState(() => _dragging = v)
            : null,
        onChangeEnd: (v) {
          setState(() => _dragging = null);
          widget.onSeek?.call(v);
        },
      ),
    );
  }
}

// ── Artwork ───────────────────────────────────────────────────────────────────

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF1A1A2E),
        child: const Icon(Icons.music_note_rounded, color: Color(0xFFFC3C44), size: 28),
      );
}

// ── Small control button ──────────────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.edge,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: child),
      ),
    );
  }
}
