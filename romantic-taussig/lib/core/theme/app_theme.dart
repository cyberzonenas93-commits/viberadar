import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Base palette
  static const Color ink = Color(0xFF080914);
  static const Color panel = Color(0xFF111425);
  static const Color panelRaised = Color(0xFF191D33);
  static const Color surface = Color(0xFF1E2340);
  static const Color edge = Color(0xFF272D4E);

  // Accent palette
  static const Color cyan = Color(0xFF3AD7FF);
  static const Color violet = Color(0xFF8F6CFF);
  static const Color pink = Color(0xFFFF4DA6);
  static const Color lime = Color(0xFF4ADE80);
  static const Color amber = Color(0xFFFBBF24);
  static const Color orange = Color(0xFFFB923C);

  // Text colors
  static const Color textPrimary = Color(0xFFEEF0F9);
  static const Color textSecondary = Color(0xFF9CA3C4);
  static const Color textTertiary = Color(0xFF636B8C);
  static const Color sectionHeader = Color(0xFF6B74A0);

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
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          color: textPrimary,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          color: textPrimary,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: textPrimary,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
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
          height: 1.4,
          color: textSecondary,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: textTertiary,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: textTertiary,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: edge.withValues(alpha: 0.6)),
        ),
      ),
      dividerColor: edge.withValues(alpha: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: edge.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: edge.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: violet, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelRaised,
        selectedColor: violet.withValues(alpha: 0.2),
        disabledColor: panelRaised.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: edge.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: violet),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
