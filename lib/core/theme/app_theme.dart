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
  static const Color ink = Color(0xFF07090D);
  static const Color panel = Color(0xFF11161C);
  static const Color panelRaised = Color(0xFF182028);
  static const Color surface = Color(0xFF202934);
  static const Color edge = Color(0xFF33404B);

  // ---- Accent palette ----
  static const Color cyan = Color(0xFF34D8D0);
  static const Color violet = Color(0xFF7C8CFF);
  static const Color pink = Color(0xFFFF6F8F);
  static const Color lime = Color(0xFF92F2B4);
  static const Color amber = Color(0xFFFFCA5C);
  static const Color orange = Color(0xFFFF9B57);

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
  static const Color hairline = Color(0x0FFFFFFF); // white @ ~6%
  static const Color hairlineStrong = Color(0x1FFFFFFF); // white @ ~12%

  // ---- Gradients ----
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, lime, amber],
  );

  /// Primary call-to-action gradient — signal green for the production UI.
  static const LinearGradient ctaGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [cyan, lime],
  );

  /// Default frosted surface gradient for cards/sheets.
  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF172029), Color(0xFF0C1015)],
  );

  /// Backdrop wash for hero sections.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF121D24), ink],
  );

  // ---- Shadows & glow ----
  /// Soft ambient drop shadow that lifts surfaces off the near-black canvas.
  static List<BoxShadow> get ambientShadow => const [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x22000000), blurRadius: 5, offset: Offset(0, 2)),
  ];

  /// Colored neon glow — use on active/primary elements.
  static List<BoxShadow> glow(
    Color color, {
    double blur = 28,
    double spread = 0,
    double opacity = 0.22,
  }) => [
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
                  const Color(0xFF172029),
                ),
                const Color(0xFF0C1015),
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
      primary: cyan,
      secondary: lime,
      tertiary: amber,
      surface: panel,
      surfaceContainerHighest: panelRaised,
      error: Color(0xFFFF6B6B),
      onPrimary: ink,
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
          letterSpacing: 0,
          color: textPrimary,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: textPrimary,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: textPrimary,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: textPrimary,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
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
        selectedColor: cyan.withValues(alpha: 0.18),
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
        indicatorColor: lime.withValues(alpha: 0.16),
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
            color: states.contains(WidgetState.selected) ? lime : textSecondary,
            size: 21,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cyan,
          foregroundColor: ink,
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
          backgroundColor: cyan,
          foregroundColor: ink,
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
          foregroundColor: cyan,
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
