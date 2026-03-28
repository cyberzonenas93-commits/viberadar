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

    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0F),
        border: Border(
          top: BorderSide(color: AppTheme.cyan, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Deck A (38%)
          Expanded(
            flex: 38,
            child: _DeckPanel(deckIndex: 0, accent: AppTheme.cyan),
          ),

          // Divider
          Container(width: 1, color: AppTheme.edge),

          // Center mixer (24%)
          Expanded(
            flex: 24,
            child: _CenterMixer(),
          ),

          // Divider
          Container(width: 1, color: AppTheme.edge),

          // Deck B (38%)
          Expanded(
            flex: 38,
            child: _DeckPanel(deckIndex: 1, accent: AppTheme.violet),
          ),
        ],
      ),
    );
  }
}

// ── Deck Panel ────────────────────────────────────────────────────────────────

class _DeckPanel extends ConsumerWidget {
  const _DeckPanel({required this.deckIndex, required this.accent});

  final int deckIndex;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dj = ref.watch(djPlayerProvider);
    final deck = deckIndex == 0 ? dj.deckA : dj.deckB;
    final notifier = ref.read(djPlayerProvider.notifier);

    if (!deck.hasTrack) {
      return _EmptyDeckPanel(deckIndex: deckIndex, accent: accent);
    }

    final track = deck.track!;
    final label = deckIndex == 0 ? 'A' : 'B';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: artwork + info + close
          Row(
            children: [
              // Deck label badge
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent, width: 1),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Artwork
              _ArtworkWidget(artworkUrl: track.artworkUrl, accent: accent, size: 44),
              const SizedBox(width: 8),
              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (track.bpm > 0) ...[
                          Text(
                            '${_fmtBpm(deck.effectiveBpm)} BPM',
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (track.key.isNotEmpty && track.key != '--')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              track.key,
                              style: TextStyle(
                                color: accent,
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (deck.isNearEnd) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'ENDING',
                              style: TextStyle(
                                color: AppTheme.amber,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Close button
              GestureDetector(
                onTap: () => notifier.hide(),
                child: const Icon(
                  Icons.close_rounded,
                  color: AppTheme.textTertiary,
                  size: 14,
                ),
              ),
            ],
          ),

          const SizedBox(height: 3),

          // Waveform
          GestureDetector(
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = details.localPosition;
              final frac = (local.dx / box.size.width).clamp(0.0, 1.0);
              notifier.seek(deckIndex, frac);
            },
            child: SizedBox(
              height: 28,
              child: CustomPaint(
                painter: _WaveformPainter(
                  progress: deck.progress,
                  color: accent,
                  trackId: track.id,
                ),
                size: Size.infinite,
              ),
            ),
          ),

          const SizedBox(height: 2),

          // Time row
          Row(
            children: [
              Text(
                _fmt(deck.position),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              Text(
                '-${_fmt(deck.remaining)}',
                style: TextStyle(
                  color: deck.isNearEnd ? AppTheme.amber : AppTheme.textTertiary,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Transport buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // CUE
              _DjButton(
                label: 'CUE',
                color: AppTheme.amber,
                active: deck.isCued,
                onTap: () => deck.isCued
                    ? notifier.jumpToCue(deckIndex)
                    : notifier.setCue(deckIndex),
              ),
              const SizedBox(width: 4),
              // Skip back
              _IconBtn(
                icon: Icons.skip_previous_rounded,
                onTap: () => notifier.seek(deckIndex, 0.0),
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              // Play/Pause
              _PlayBtn(
                isPlaying: deck.isPlaying,
                isLoading: deck.isLoading,
                accent: accent,
                onTap: () => notifier.togglePlayPause(deckIndex),
              ),
              const SizedBox(width: 4),
              // Skip forward 15s
              _IconBtn(
                icon: Icons.forward_10_rounded,
                onTap: () {
                  final pos = deck.position + const Duration(seconds: 15);
                  final frac = pos.inMilliseconds / (deck.duration.inMilliseconds > 0 ? deck.duration.inMilliseconds : 1);
                  notifier.seek(deckIndex, frac.clamp(0.0, 1.0));
                },
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              // LOOP
              _DjButton(
                label: 'LOOP',
                color: AppTheme.lime,
                active: deck.isLooping,
                onTap: () => notifier.toggleLoop(deckIndex),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Pitch slider row
          Row(
            children: [
              const Text(
                'PITCH',
                style: TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accent,
                    inactiveTrackColor: AppTheme.edge,
                    thumbColor: accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    trackHeight: 2,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: deck.pitch,
                    min: -8.0,
                    max: 8.0,
                    onChanged: (v) => notifier.setPitch(deckIndex, v),
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  '${deck.pitch >= 0 ? '+' : ''}${deck.pitch.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: deck.pitch == 0 ? AppTheme.textTertiary : accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),

          // EQ row
          Row(
            children: [
              _EqSlider(
                label: 'HI',
                value: deck.eqHigh,
                onChanged: (v) => notifier.setEq(deckIndex, high: v),
                color: accent,
              ),
              const SizedBox(width: 4),
              _EqSlider(
                label: 'MID',
                value: deck.eqMid,
                onChanged: (v) => notifier.setEq(deckIndex, mid: v),
                color: accent,
              ),
              const SizedBox(width: 4),
              _EqSlider(
                label: 'LOW',
                value: deck.eqLow,
                onChanged: (v) => notifier.setEq(deckIndex, low: v),
                color: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty deck placeholder ────────────────────────────────────────────────────

class _EmptyDeckPanel extends StatelessWidget {
  const _EmptyDeckPanel({required this.deckIndex, required this.accent});

  final int deckIndex;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final label = deckIndex == 0 ? 'A' : 'B';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: accent.withValues(alpha: 0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Deck $label — Drop track here',
            style: TextStyle(
              color: accent.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Center Mixer Panel ────────────────────────────────────────────────────────

class _CenterMixer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dj = ref.watch(djPlayerProvider);
    final notifier = ref.read(djPlayerProvider.notifier);

    final bpmA = dj.deckA.effectiveBpm;
    final bpmB = dj.deckB.effectiveBpm;
    final suggestion = notifier.nextSuggestion;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // BPM sync info
          if (dj.deckA.hasTrack && dj.deckB.hasTrack) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _fmtBpm(bpmA),
                  style: TextStyle(
                    color: dj.bpmSynced ? AppTheme.lime : AppTheme.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '→',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
                  ),
                ),
                Text(
                  _fmtBpm(bpmB),
                  style: TextStyle(
                    color: dj.bpmSynced ? AppTheme.lime : AppTheme.violet,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // SYNC button
            GestureDetector(
              onTap: () => notifier.syncBpm(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: dj.bpmSynced
                      ? AppTheme.lime.withValues(alpha: 0.15)
                      : AppTheme.edge,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: dj.bpmSynced ? AppTheme.lime : AppTheme.textTertiary,
                    width: 1,
                  ),
                ),
                child: Text(
                  dj.bpmSynced ? 'SYNCED' : 'SYNC BPM',
                  style: TextStyle(
                    color: dj.bpmSynced ? AppTheme.lime : AppTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
          ] else
            const SizedBox(height: 8),

          // Crossfader label
          Row(
            children: [
              const Text('A', style: TextStyle(color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w700)),
              const Expanded(
                child: Center(
                  child: Text('CROSSFADER', style: TextStyle(color: AppTheme.textTertiary, fontSize: 8, fontWeight: FontWeight.w600)),
                ),
              ),
              const Text('B', style: TextStyle(color: AppTheme.violet, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),

          // Crossfader slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.violet,
              inactiveTrackColor: AppTheme.cyan,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 4,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: dj.crossfader,
              onChanged: (v) => notifier.setCrossfader(v),
            ),
          ),

          const SizedBox(height: 3),

          // Auto-mix button
          GestureDetector(
            onTap: () => notifier.toggleAutoMix(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: dj.autoMix
                    ? AppTheme.lime.withValues(alpha: 0.2)
                    : AppTheme.edge,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: dj.autoMix ? AppTheme.lime : AppTheme.edge,
                  width: 1,
                ),
                boxShadow: dj.autoMix
                    ? [BoxShadow(color: AppTheme.lime.withValues(alpha: 0.25), blurRadius: 8)]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.autorenew_rounded,
                    color: dj.autoMix ? AppTheme.lime : AppTheme.textSecondary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dj.autoMix ? 'AUTO-MIX ON' : 'AUTO-MIX',
                    style: TextStyle(
                      color: dj.autoMix ? AppTheme.lime : AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 3),

          // AUTO-QUEUE button
          GestureDetector(
            onTap: () => notifier.toggleAutoQueue(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: dj.autoQueue
                    ? AppTheme.cyan.withValues(alpha: 0.2)
                    : AppTheme.edge,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: dj.autoQueue ? AppTheme.cyan : AppTheme.edge,
                  width: 1,
                ),
                boxShadow: dj.autoQueue
                    ? [BoxShadow(
                        color: AppTheme.cyan.withValues(alpha: 0.2),
                        blurRadius: 6,
                      )]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: dj.autoQueue
                        ? AppTheme.cyan
                        : AppTheme.textSecondary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dj.autoQueue ? 'AUTO-QUEUE ON' : 'AUTO-QUEUE',
                    style: TextStyle(
                      color: dj.autoQueue
                          ? AppTheme.cyan
                          : AppTheme.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 3),

          // Master volume
          Row(
            children: [
              const Icon(Icons.volume_up_rounded, color: AppTheme.textTertiary, size: 12),
              const SizedBox(width: 4),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.textSecondary,
                    inactiveTrackColor: AppTheme.edge,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    trackHeight: 2,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: dj.masterVolume,
                    onChanged: (v) => notifier.setMasterVolume(v),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Next suggestion chip — only when both decks aren't both active
          // (saves vertical space when the BPM sync row is shown)
          if (suggestion != null && (!dj.deckA.hasTrack || !dj.deckB.hasTrack || dj.autoQueue))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppTheme.panelRaised,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppTheme.edge, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'NEXT UP',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${suggestion.artist} – ${suggestion.title}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (suggestion.bpm > 0)
                    Text(
                      '${suggestion.bpm.toStringAsFixed(0)} BPM'
                      '${suggestion.key.isNotEmpty && suggestion.key != '--' ? ' · ${suggestion.key}' : ''}',
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 8),
                    ),
                ],
              ),
            ),
        ],
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
