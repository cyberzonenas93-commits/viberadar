import 'package:flutter/material.dart';

class AppTheme {
  static const Color ink = Color(0xFF080914);
  static const Color panel = Color(0xFF111425);
  static const Color panelRaised = Color(0xFF171B31);
  static const Color edge = Color(0xFF252B48);
  static const Color cyan = Color(0xFF3AD7FF);
  static const Color violet = Color(0xFF8F6CFF);
  static const Color pink = Color(0xFFFF4DA6);
  static const Color lime = Color(0xFF9AFFA1);

  static ThemeData darkTheme() {
    final bodyTextTheme = ThemeData.dark(useMaterial3: true).textTheme;
    final colorScheme = const ColorScheme.dark(
      primary: cyan,
      secondary: pink,
      surface: panel,
      surfaceContainerHighest: panelRaised,
      error: Color(0xFFFF7A7A),
      onPrimary: ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ink,
      colorScheme: colorScheme,
      textTheme: bodyTextTheme.copyWith(
        displayLarge: bodyTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.4,
        ),
        headlineMedium: bodyTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: bodyTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        titleMedium: bodyTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: bodyTextTheme.bodyMedium?.copyWith(height: 1.35),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: edge),
        ),
      ),
      dividerColor: edge,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: cyan),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panelRaised,
        selectedColor: cyan.withValues(alpha: 0.2),
        disabledColor: panelRaised.withValues(alpha: 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: const BorderSide(color: edge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: bodyTextTheme.labelLarge!,
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: cyan),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
    );
  }
}
