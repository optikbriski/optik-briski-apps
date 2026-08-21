import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palet etalase = Figma Cobalt sky. Bukan navy/es Optik.
abstract final class RekasaTokens {
  static const Color sky = Color(0xFF8BB4E8);
  static const Color inkSoft = Color(0xFF2B6BC4);
  static const Color ink = Color(0xFF0047AB);
  static const Color inkDeep = Color(0xFF001F4D);
  static const Color canvas = Color(0xFFD6E5F7);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF4E7BB8);
  static const Color line = Color(0x668BB4E8);
  static const Color lineStrong = Color(0x998BB4E8);
  static const Color wash = Color(0x4D8BB4E8);
  static const Color danger = Color(0xFFA65D5D);
  static const Color warning = Color(0xFF9A7B3C);

  static const double radiusCard = 22;
  static const double maxWidth = 1040;

  static List<BoxShadow> get lift => [
        BoxShadow(
          color: ink.withOpacity(0.07),
          blurRadius: 28,
          spreadRadius: -8,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: ink.withOpacity(0.045),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static LinearGradient get badgeFill => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [sky, inkSoft, ink],
        stops: [0.0, 0.52, 1.0],
      );
}

ThemeData buildRekasaStoreTheme() {
  final body = GoogleFonts.plusJakartaSansTextTheme().apply(
    bodyColor: RekasaTokens.ink,
    displayColor: RekasaTokens.ink,
  );
  final text = body.copyWith(
    headlineMedium: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.7,
      height: 1.12,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
    ),
    titleLarge: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 16.5,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.45,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.muted,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.45,
    ),
    labelLarge: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
    labelSmall: GoogleFonts.plusJakartaSans(
      color: RekasaTokens.muted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    textTheme: text,
    scaffoldBackgroundColor: RekasaTokens.canvas,
    colorScheme: const ColorScheme.light(
      primary: RekasaTokens.inkSoft,
      secondary: RekasaTokens.sky,
      surface: RekasaTokens.paper,
      error: RekasaTokens.danger,
      onPrimary: RekasaTokens.paper,
      onSecondary: RekasaTokens.paper,
      onSurface: RekasaTokens.ink,
      onError: RekasaTokens.paper,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: RekasaTokens.ink,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: RekasaTokens.ink,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    ),
    dividerTheme: const DividerThemeData(color: RekasaTokens.line, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: RekasaTokens.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: RekasaTokens.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RekasaTokens.ink,
      contentTextStyle: GoogleFonts.plusJakartaSans(color: RekasaTokens.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RekasaTokens.canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RekasaTokens.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RekasaTokens.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: RekasaTokens.ink, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: RekasaTokens.inkSoft,
        foregroundColor: RekasaTokens.paper,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: RekasaTokens.ink,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected) ? RekasaTokens.paper : RekasaTokens.paper;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        return s.contains(WidgetState.selected)
            ? RekasaTokens.ink
            : RekasaTokens.lineStrong;
      }),
    ),
  );
}
