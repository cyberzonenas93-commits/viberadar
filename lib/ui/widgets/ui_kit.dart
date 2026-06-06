import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shared visual primitives for the elevated VibeRadar look. Build screens from
/// these so depth, glow, radii and motion stay consistent and tunable.

/// Scales its child down briefly on press — the standard tactile feedback for
/// any tappable surface (cards, buttons, pills).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _interactive => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (_interactive && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _interactive ? (_) => _set(true) : null,
      onTapUp: _interactive ? (_) => _set(false) : null,
      onTapCancel: _interactive ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A frosted, layered surface — the default container for content. Subtle
/// gradient fill, luminous hairline border, soft ambient lift, optional accent
/// [tint]/[glow], optional real backdrop [blur].
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s4),
    this.radius = AppTheme.rLg,
    this.onTap,
    this.onLongPress,
    this.tint,
    this.glow,
    this.blur = false,
    this.border,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? tint;
  final List<BoxShadow>? glow;
  final bool blur;
  final Color? border;
  final double? width;

  @override
  Widget build(BuildContext context) {
    Widget surface = Container(
      width: width,
      padding: padding,
      decoration: AppTheme.glass(
        radius: radius,
        tint: tint,
        glowShadow: glow,
        border: border,
      ),
      child: child,
    );

    if (blur) {
      surface = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: surface,
        ),
      );
    }

    if (onTap != null || onLongPress != null) {
      surface = PressableScale(
        onTap: onTap,
        onLongPress: onLongPress,
        child: surface,
      );
    }
    return surface;
  }
}

/// Primary call-to-action with the cyan→violet gradient and a soft glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = false,
    this.gradient,
    this.glow = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final Gradient? gradient;
  final bool glow;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PressableScale(
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: expand ? AppTheme.s4 : AppTheme.s6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.ctaGradient,
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            boxShadow: glow && enabled
                ? AppTheme.glow(AppTheme.violet, blur: 24, opacity: 0.45)
                : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: AppTheme.s2),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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

/// A rounded pill / filter chip that glows when selected.
class GlowPill extends StatelessWidget {
  const GlowPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
    this.color,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.cyan;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.s3,
          vertical: AppTheme.s2,
        ),
        decoration: BoxDecoration(
          color: selected ? null : AppTheme.panelRaised,
          gradient: selected
              ? LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.24),
                    accent.withValues(alpha: 0.10),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : AppTheme.hairline,
          ),
          boxShadow: selected
              ? AppTheme.glow(accent, blur: 16, opacity: 0.30)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: AppTheme.s1 + 2),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Consistent section header with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppTheme.cyan),
          const SizedBox(width: AppTheme.s2),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          PressableScale(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.s1,
                vertical: AppTheme.s1,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppTheme.cyan,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Animated radar-ping loading indicator (reuses the splash motif).
class RadarLoader extends StatefulWidget {
  const RadarLoader({super.key, this.size = 64, this.message});

  final double size;
  final String? message;

  @override
  State<RadarLoader> createState() => _RadarLoaderState();
}

class _RadarLoaderState extends State<RadarLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) =>
                CustomPaint(painter: _RadarLoaderPainter(_c.value)),
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: AppTheme.s4),
          Text(
            widget.message!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _RadarLoaderPainter extends CustomPainter {
  _RadarLoaderPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    canvas.drawCircle(center, 3.5, Paint()..color = AppTheme.cyan);
    for (final phase in const [0.0, 0.33, 0.66]) {
      final p = (t + phase) % 1.0;
      final r = maxR * p;
      final fade = 1.0 - p;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.lerp(AppTheme.cyan, AppTheme.violet, p)!
              .withValues(alpha: 0.5 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarLoaderPainter old) => old.t != t;
}

/// Empty-state placeholder with the radar motif, a message, and optional CTA.
class VibeEmptyState extends StatelessWidget {
  const VibeEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.radar,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.cyan.withValues(alpha: 0.18),
                    AppTheme.violet.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(color: AppTheme.hairline),
              ),
              child: Icon(icon, color: AppTheme.cyan, size: 30),
            ),
            const SizedBox(height: AppTheme.s5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppTheme.s2),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppTheme.s6),
              GradientButton(
                label: actionLabel!,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slowly-animated radar/grid hero backdrop — a living version of the static
/// VibeBackdrop, for hero headers. Drifts and pulses very subtly.
class AnimatedRadarHero extends StatefulWidget {
  const AnimatedRadarHero({
    super.key,
    this.height = 200,
    this.child,
    this.alignment = Alignment.bottomLeft,
  });

  final double height;
  final Widget? child;
  final Alignment alignment;

  @override
  State<AnimatedRadarHero> createState() => _AnimatedRadarHeroState();
}

class _AnimatedRadarHeroState extends State<AnimatedRadarHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) =>
                  CustomPaint(painter: _RadarHeroPainter(_c.value)),
            ),
          ),
          if (widget.child != null)
            Align(
              alignment: widget.alignment,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.s5),
                child: widget.child,
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarHeroPainter extends CustomPainter {
  _RadarHeroPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.82, size.height * 0.30);

    // Pulsing radar rings.
    for (var i = 0; i < 4; i++) {
      final phase = (t + i * 0.25) % 1.0;
      final radius = size.shortestSide * (0.18 + phase * 0.7);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppTheme.cyan.withValues(alpha: 0.16 * (1 - phase)),
      );
    }

    // Drifting waveform.
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..shader = const LinearGradient(
        colors: [AppTheme.cyan, AppTheme.violet],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final path = Path();
    final drift = t * 2 * math.pi;
    for (var i = 0; i <= 80; i++) {
      final tt = i / 80;
      final x = tt * size.width;
      final y = size.height * 0.72 +
          math.sin(tt * math.pi * 5 + drift) * 8 +
          math.sin(tt * math.pi * 13 + drift * 1.6) * 3;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      wavePaint..color = AppTheme.cyan.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarHeroPainter old) => old.t != t;
}
