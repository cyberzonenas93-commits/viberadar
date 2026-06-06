import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central design system for VibeRadar.
///
/// Beyond the raw palette, this exposes a token system the UI builds on:
/// a radius scale, a 4-pt spacing scale, gradients, glow/ambient shadows, and
/// a [glass] surface decoration. Prefer these tokens over hardcoded values so
/// the look stays consistent and is tunable from one place.
class AppTheme {
  // ---- Base palette ----
  static const Color ink = Color(0xFF06070B);
  static const Color panel = Color(0xFF101722);
  static const Color panelRaised = Color(0xFF172033);
  static const Color surface = Color(0xFF202A3D);
  static const Color edge = Color(0xFF2B394E);

  // ---- Accent palette ----
  static const Color cyan = Color(0xFF24C8DB);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color pink = Color(0xFFE84A7D);
  static const Color lime = Color(0xFF5EE89E);
  static const Color amber = Color(0xFFF7C948);
  static const Color orange = Color(0xFFFF8A3D);

  // ---- Text colors ----
  static const Color textPrimary = Color(0xFFF3F6FB);
  static const Color textSecondary = Color(0xFFA7B2C8);
  static const Color textTertiary = Color(0xFF6E7B93);
  static const Color sectionHeader = Color(0xFF8D99B3);

  // ---- Radius scale ----
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 20;
  static const double r2xl = 28;
  static const double rPill = 999;

  // ---- Spacing scale (4-pt grid) ----
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;

  // ---- Hairline borders (thin luminous edges on dark glass) ----
  static const Color hairline = Color(0x12FFFFFF); // white @ ~7%
  static const Color hairlineStrong = Color(0x24FFFFFF); // white @ ~14%

  // ---- Gradients ----
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, violet, pink, amber],
  );

  /// Primary call-to-action gradient — matches the radar logo's cyan→violet.
  static const LinearGradient ctaGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [cyan, violet],
  );

  /// Default frosted surface gradient for cards/sheets.
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF18222F), Color(0xFF0E141D)],
  );

  /// Backdrop wash for hero sections.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF111B2C), ink],
  );

  // ---- Shadows & glow ----
  /// Soft ambient drop shadow that lifts surfaces off the near-black canvas.
  static List<BoxShadow> get ambientShadow => const [
        BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
        BoxShadow(color: Color(0x2B000000), blurRadius: 6, offset: Offset(0, 2)),
      ];

  /// Colored neon glow — use on active/primary elements.
  static List<BoxShadow> glow(
    Color color, {
    double blur = 28,
    double spread = 0,
    double opacity = 0.38,
  }) =>
      [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];

  static List<BoxShadow> get cyanGlow => glow(cyan);
  static List<BoxShadow> get violetGlow => glow(violet);

  /// Frosted-glass surface decoration: a subtle vertical gradient, a luminous
  /// hairline border, soft ambient lift, and an optional colored [glowShadow].
  /// Pass a [tint] to bias the surface toward an accent (e.g. now-playing).
  static BoxDecoration glass({
    double radius = rLg,
    Color? tint,
    List<BoxShadow>? glowShadow,
    bool raised = true,
    Color? border,
  }) {
    return BoxDecoration(
      gradient: tint == null
          ? surfaceGradient
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  tint.withValues(alpha: 0.12),
                  const Color(0xFF18222F),
                ),
                const Color(0xFF0E141D),
              ],
            ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? hairline),
      boxShadow: [
        if (raised) ...ambientShadow,
        if (glowShadow != null) ...glowShadow,
      ],
    );
  }

  static ThemeData darkTheme() {
    final baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.dark(useMaterial3: true).textTheme,
    );

    final colorScheme = const ColorScheme.dark(
      primary: violet,
      secondary: cyan,
      tertiary: pink,
      surface: panel,
      surfaceContainerHighest: panelRaised,
      error: Color(0xFFFF6B6B),
      onPrimary: Colors.white,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: colorScheme,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1,
          color: textPrimary,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          color: textPrimary,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          height: 1.5,
          color: textPrimary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: textSecondary,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: textTertiary),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: textTertiary,
        ),
      ),
      cardTheme: CardThemeData(
        color: panelRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rLg),
          side: const BorderSide(color: hairline),
        ),
      ),
      dividerColor: hairline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: const BorderSide(color: cyan, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: s4,
          vertical: s3 + 2,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelRaised,
        selectedColor: violet.withValues(alpha: 0.22),
        disabledColor: panelRaised.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: s3, vertical: s2),
        side: const BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rPill),
        ),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: cyan),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel.withValues(alpha: 0.86),
        indicatorColor: cyan.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? textPrimary
                : textSecondary,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? cyan : textSecondary,
            size: 21,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: s5, vertical: s3 + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: s5, vertical: s3 + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: hairlineStrong),
          padding: const EdgeInsets.symmetric(horizontal: s5, vertical: s3 + 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: violet,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(edge.withValues(alpha: 0.5)),
        radius: const Radius.circular(4),
      ),
    );
  }
}
