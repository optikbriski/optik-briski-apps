import 'package:flutter/material.dart';

/// Design tokens for Admin premium dark enterprise UI.
/// Prefer these over hardcoding slate colors in pages.
abstract final class OptikAdminTokens {
  static const Color bg = Color(0xFF0B1220);
  static const Color bgMid = Color(0xFF0F172A);
  static const Color panel = Color(0xFF152033);
  static const Color card = Color(0xFF1E293B);
  static const Color cardElevated = Color(0xFF243247);
  static const Color line = Color(0x14FFFFFF);
  static const Color lineStrong = Color(0x24FFFFFF);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color accent = Color(0xFF3B82F6);
  static const Color accentDeep = Color(0xFF2563EB);
  static const Color accentSoft = Color(0xFF60A5FA);
  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color training = Color(0xFFB45309);
  static const Color trainingSoft = Color(0xFFF59E0B);

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.35),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: accent.withOpacity(0.06),
          blurRadius: 32,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  static LinearGradient get bgGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0B1220),
          Color(0xFF0F172A),
          Color(0xFF111827),
        ],
        stops: [0.0, 0.55, 1.0],
      );

  static LinearGradient get accentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accentSoft, accent, accentDeep],
      );

  static LinearGradient get cardSheen => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.0),
        ],
      );
}

/// Shared dark enterprise theme (Admin / default).
ThemeData buildAdminTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: null,
  );

  return base.copyWith(
    scaffoldBackgroundColor: OptikAdminTokens.bgMid,
    colorScheme: const ColorScheme.dark(
      primary: OptikAdminTokens.accent,
      secondary: OptikAdminTokens.trainingSoft,
      surface: OptikAdminTokens.card,
      error: OptikAdminTokens.danger,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: OptikAdminTokens.textPrimary,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: OptikAdminTokens.textPrimary),
      titleTextStyle: TextStyle(
        color: OptikAdminTokens.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: OptikAdminTokens.card,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusLg),
        side: const BorderSide(color: OptikAdminTokens.line, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: OptikAdminTokens.line,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: OptikAdminTokens.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusXl),
        side: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      titleTextStyle: const TextStyle(
        color: OptikAdminTokens.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: const TextStyle(
        color: OptikAdminTokens.textSecondary,
        fontSize: 14,
        height: 1.4,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: OptikAdminTokens.panel,
      contentTextStyle: const TextStyle(color: OptikAdminTokens.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
        side: const BorderSide(color: OptikAdminTokens.line),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: OptikAdminTokens.textSecondary,
      textColor: OptikAdminTokens.textPrimary,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OptikAdminTokens.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.danger),
      ),
      labelStyle: const TextStyle(color: OptikAdminTokens.textMuted, fontSize: 13),
      hintStyle: TextStyle(
        color: OptikAdminTokens.textMuted.withOpacity(0.7),
        fontSize: 13,
      ),
      prefixIconColor: OptikAdminTokens.textMuted,
      suffixIconColor: OptikAdminTokens.textMuted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OptikAdminTokens.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: OptikAdminTokens.accent.withOpacity(0.4),
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          fontSize: 13,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OptikAdminTokens.textPrimary,
        side: const BorderSide(color: OptikAdminTokens.lineStrong),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OptikAdminTokens.accentSoft,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OptikAdminTokens.accent,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OptikAdminTokens.accentSoft,
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: OptikAdminTokens.accentSoft,
      labelColor: OptikAdminTokens.accentSoft,
      unselectedLabelColor: OptikAdminTokens.textMuted,
      indicatorSize: TabBarIndicatorSize.label,
    ),
  );
}

ThemeData buildKaryawanTheme() {
  const navy = Color(0xFF0A1628);
  const navyMid = Color(0xFF1E3C72);
  const gold = Color(0xFFC4A35A);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF4F7FB),
    colorScheme: const ColorScheme.light(
      primary: navyMid,
      secondary: gold,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: navy,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: navy,
      titleTextStyle: TextStyle(
        color: navy,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: navyMid,
      foregroundColor: Colors.white,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Colors.white,
      elevation: 12,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

ThemeData buildMemberTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: Color(0xFFF8FAFC),
      foregroundColor: Color(0xFF0F172A),
    ),
  );
}
