import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'zentho_colors.dart';

abstract final class ZenthoTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: ZenthoColors.tealDeep,
        onPrimary: Colors.white,
        secondary: ZenthoColors.amber,
        onSecondary: ZenthoColors.ink,
        surface: Colors.white,
        onSurface: ZenthoColors.ink,
        error: ZenthoColors.coral,
        outline: ZenthoColors.line,
      ),
      scaffoldBackgroundColor: ZenthoColors.creamMist,
    );

    final display = GoogleFonts.frauncesTextTheme(base.textTheme);
    final body = GoogleFonts.dmSansTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: body.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
        ),
        displayMedium: display.displayMedium?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.8,
        ),
        displaySmall: display.displaySmall?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
        ),
        headlineLarge: display.headlineLarge?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: display.headlineSmall?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: body.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: ZenthoColors.ink,
        ),
        titleMedium: body.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: ZenthoColors.ink,
        ),
        bodyLarge: body.bodyLarge?.copyWith(color: ZenthoColors.ink),
        bodyMedium: body.bodyMedium?.copyWith(color: ZenthoColors.inkMuted),
        labelLarge: body.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ZenthoColors.ink,
        titleTextStyle: display.titleLarge?.copyWith(
          color: ZenthoColors.ink,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ZenthoColors.tealDeep,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ZenthoColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ZenthoColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ZenthoColors.teal, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        indicatorColor: ZenthoColors.mint,
        labelTextStyle: WidgetStatePropertyAll(
          body.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: ZenthoColors.line, thickness: 1),
    );
  }
}
