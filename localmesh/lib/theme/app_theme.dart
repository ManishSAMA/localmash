import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// LOCAL_MESH tactical dark palette (reference UI — #0D1117 / #00FF88).
abstract final class LocalMeshColors {
  static const Color background = Color(0xFF0D1117);
  static const Color accent = Color(0xFF00FF88);
  static const Color surfaceCard = Color(0xFF161B22);
  static const Color borderMuted = Color(0xFF30363D);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color emergency = Color(0xFFB42318);
  static const Color bubbleTheirs = Color(0xFF2E2E2E);
}

/// Space Grotesk (display / hero) + Inter (labels / body) — Modern Tactical ref.
ThemeData buildLocalMeshTheme() {
  const accent = LocalMeshColors.accent;
  const bg = LocalMeshColors.background;

  final seed = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: bg,
      primary: accent,
      onPrimary: const Color(0xFF0D1117),
      secondary: accent,
      error: const Color(0xFFFF6B6B),
    ),
  );

  final inter = GoogleFonts.interTextTheme(
    ThemeData.dark(useMaterial3: true).textTheme,
  );
  final display = inter.copyWith(
    displayLarge: GoogleFonts.spaceGrotesk(
      textStyle: inter.displayLarge,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      letterSpacing: -0.5,
    ),
    titleLarge: GoogleFonts.spaceGrotesk(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: Colors.white,
    ),
    headlineMedium: GoogleFonts.spaceGrotesk(
      fontSize: 36,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.1,
    ),
    headlineSmall: GoogleFonts.spaceGrotesk(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.4,
      color: LocalMeshColors.textSecondary,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 15,
      height: 1.45,
      color: const Color(0xFFE6EDF3),
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      height: 1.4,
      color: const Color(0xFFE6EDF3),
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 11,
      color: LocalMeshColors.textSecondary,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: seed.colorScheme,
  ).copyWith(
    textTheme: display,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: accent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.w700,
        fontSize: 18,
        letterSpacing: 1.2,
        color: accent,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF010409),
      indicatorColor: accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.spaceGrotesk(
          fontSize: 10,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w600,
          color: selected ? accent : LocalMeshColors.textSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? accent : LocalMeshColors.textSecondary,
          size: 22,
        );
      }),
    ),
    cardTheme: CardThemeData(
      color: LocalMeshColors.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: LocalMeshColors.borderMuted),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: LocalMeshColors.borderMuted,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LocalMeshColors.surfaceCard,
      hintStyle: GoogleFonts.inter(
        color: LocalMeshColors.textSecondary,
        letterSpacing: 0.5,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: LocalMeshColors.borderMuted),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: LocalMeshColors.borderMuted),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: const Color(0xFF0D1117),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    ),
  );
}
