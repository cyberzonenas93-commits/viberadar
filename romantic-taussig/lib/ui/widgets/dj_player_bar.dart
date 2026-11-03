import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/dj_player_provider.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _fmt(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

String _fmtBpm(double bpm) => bpm > 0 ? bpm.toStringAsFixed(1) : '--';

// ── Waveform painter ──────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.color,
    required this.trackId,
  });

  final double progress;
  final Color color;
  final String trackId;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 80;
    final barWidth = size.width / barCount;
    final seed = trackId.codeUnits.fold(0, (a, b) => a ^ b);
    final rng = math.Random(seed);

    final playedPaint = Paint()..color = color;
    final unplayedPaint = Paint()..color = color.withValues(alpha: 0.25);
    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;

    for (var i = 0; i < barCount; i++) {
      final heightFraction = 0.15 + rng.nextDouble() * 0.85;
      final barH = size.height * heightFraction;
      final x = i * barWidth;
      final y = (size.height - barH) / 2;
      final isPlayed = (i / barCount) < progress;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.5, y, barWidth - 1, barH),
          const Radius.circular(1),
        ),
        isPlayed ? playedPaint : unplayedPaint,
      );
    }

    // Playhead line
    final playX = progress * size.width;
    canvas.drawLine(
      Offset(playX, 0),
      Offset(playX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.trackId != trackId;
}

// ── Main DJ Player Bar ────────────────────────────────────────────────────────

class DjPlayerBar extends ConsumerWidget {
  const DjPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dj = ref.watch(djPlayerProvider);
    if (!dj.isVisible) return const SizedBox.shrink();

    // Show the active playing deck
    final activeDeck = dj.activeDeck == 0 ? dj.deckA : dj.deckB;
    final activeIdx = dj.activeDeck;
    final notifier = ref.read(djPlayerProvider.notifier);
    final suggestion = notifier.nextSuggestion;

    if (!activeDeck.hasTrack) return const SizedBox.shrink();
    final track = activeDeck.track!;

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F),
        border: const Border(top: BorderSide(color: AppTheme.cyan, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            // Artwork
            _ArtworkWidget(artworkUrl: track.artworkUrl, accent: AppTheme.cyan, size: 56),
            const SizedBox(width: 12),

            // Track info + waveform
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title + artist row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(track.artist,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      // Metadata badges
                      if (track.bpm > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text('${track.bpm.toStringAsFixed(0)} BPM',
                            style: const TextStyle(color: AppTheme.amber, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      if (track.key.isNotEmpty && track.key != '--')
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(track.key,
                            style: const TextStyle(color: AppTheme.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      if (activeDeck.isNearEnd)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                          child: const Text('ENDING', style: TextStyle(color: AppTheme.amber, fontSize: 8, fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Waveform + time
                  Row(
                    children: [
                      Text(_fmt(activeDeck.position),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontFamily: 'monospace')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTapDown: (details) {
                            final box = context.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            // Calculate fraction within the waveform area
                            final frac = (details.localPosition.dx / (box.size.width - 280)).clamp(0.0, 1.0);
                            notifier.seek(activeIdx, frac);
                          },
                          child: SizedBox(
                            height: 20,
                            child: CustomPaint(
                              painter: _WaveformPainter(progress: activeDeck.progress, color: AppTheme.cyan, trackId: track.id),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('-${_fmt(activeDeck.remaining)}',
                        style: TextStyle(
                          color: activeDeck.isNearEnd ? AppTheme.amber : AppTheme.textTertiary,
                          fontSize: 10, fontFamily: 'monospace')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Transport controls
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBtn(icon: Icons.skip_previous_rounded, onTap: () => notifier.seek(activeIdx, 0.0), color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                _PlayBtn(
                  isPlaying: activeDeck.isPlaying,
                  isLoading: activeDeck.isLoading,
                  accent: AppTheme.cyan,
                  onTap: () => notifier.togglePlayPause(activeIdx),
                ),
                const SizedBox(width: 6),
                _IconBtn(
                  icon: Icons.skip_next_rounded,
                  onTap: () {
                    // Skip to next track
                    if (suggestion != null) notifier.loadTrack(suggestion);
                  },
                  color: AppTheme.textSecondary,
                ),
              ],
            ),

            const SizedBox(width: 12),

            // Volume
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  const Icon(Icons.volume_up_rounded, color: AppTheme.textTertiary, size: 14),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.textSecondary,
                        inactiveTrackColor: AppTheme.edge,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                        trackHeight: 2,
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                      ),
                      child: Slider(value: dj.masterVolume, onChanged: (v) => notifier.setMasterVolume(v)),
                    ),
                  ),
                ],
              ),
            ),

            // Next up chip + queue count
            if (suggestion != null || dj.hasQueue)
              Container(
                width: 130,
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.panelRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: dj.hasQueue ? AppTheme.violet.withValues(alpha: 0.4) : AppTheme.edge),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Text(
                        dj.hasQueue ? 'QUEUE (${dj.queue.length})' : 'NEXT UP',
                        style: TextStyle(
                          color: dj.hasQueue ? AppTheme.violet : AppTheme.textTertiary,
                          fontSize: 7, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                      const Spacer(),
                      if (dj.hasQueue)
                        GestureDetector(
                          onTap: () => notifier.clearQueue(),
                          child: const Text('CLEAR', style: TextStyle(color: AppTheme.textTertiary, fontSize: 7, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    if (suggestion != null) ...[
                      Text(suggestion.title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 9, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(suggestion.artist, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 8),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),

            // Close
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => notifier.hide(),
              child: const Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Small utility widgets ─────────────────────────────────────────────────────

class _ArtworkWidget extends StatelessWidget {
  const _ArtworkWidget({
    required this.artworkUrl,
    required this.accent,
    required this.size,
  });

  final String? artworkUrl;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: artworkUrl != null && artworkUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: artworkUrl!,
                fit: BoxFit.cover,
                placeholder: (context2, url2) => _placeholder(),
                errorWidget: (context2, url2, err) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.6), accent.withValues(alpha: 0.2)],
          ),
        ),
        child: Icon(Icons.music_note_rounded, color: Colors.white, size: size * 0.4),
      );
}

class _DjButton extends StatelessWidget {
  const _DjButton({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.2) : AppTheme.edge,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : AppTheme.edge, width: 1),
          boxShadow: active
              ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : AppTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppTheme.edge,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({
    required this.isPlaying,
    required this.isLoading,
    required this.accent,
    required this.onTap,
  });

  final bool isPlaying;
  final bool isLoading;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 8)],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 18,
              ),
      ),
    );
  }
}

class _EqSlider extends StatelessWidget {
  const _EqSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.color,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 7,
              fontWeight: FontWeight.w700,
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: AppTheme.edge,
              thumbColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              trackHeight: 2,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: value,
              min: -12.0,
              max: 12.0,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
