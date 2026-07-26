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

  /// Minimum gutters — jangan biarkan kontrol/kartu nempel.
  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 14;
  static const double spaceLg = 20;
  static const double spaceXl = 28;

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
    chipTheme: ChipThemeData(
      backgroundColor: OptikAdminTokens.card,
      selectedColor: OptikAdminTokens.accent.withOpacity(0.22),
      disabledColor: OptikAdminTokens.panel,
      labelStyle: const TextStyle(
        color: OptikAdminTokens.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: OptikAdminTokens.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        side: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      side: const BorderSide(color: OptikAdminTokens.lineStrong),
    ),
  );
}

/// Design tokens for Karyawan APK (navy–gold premium, login/register language).
abstract final class OptikKaryawanTokens {
  static const Color navyDeep = Color(0xFF0A1628);
  static const Color navyMid = Color(0xFF1E3C72);
  static const Color navySoft = Color(0xFF132F4C);
  static const Color gold = Color(0xFFD4AF37);
  static const Color goldSoft = Color(0xFFC4A35A);
  static const Color goldLite = Color(0xFFE8C872);
  static const Color scaffold = Color(0xFFF4F7FB);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF7FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color ink = Color(0xFF0B1220);
  static const Color muted = Color(0xFF64748B);
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);

  /// Dark surfaces (absensi / OTP / camera-heavy).
  static const Color darkBg = Color(0xFF0A1628);
  static const Color darkCard = Color(0xFF132F4C);
  static const Color darkLine = Color(0x24FFFFFF);

  static const double radiusSm = 14;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 22;
  static const double radiusGlass = 24;

  static LinearGradient get navyGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [navyMid, navyDeep],
      );

  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [goldLite, gold, goldSoft],
      );

  static LinearGradient get authBgGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF071018),
          navyDeep,
          navySoft,
          Color(0xFF1A3A5C),
        ],
      );

  static LinearGradient get registerBgGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0F2744),
          Color(0xFF163A5F),
          Color(0xFFE8EEF5),
          scaffold,
        ],
        stops: [0.0, 0.28, 0.55, 1.0],
      );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: navyDeep.withOpacity(0.07),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static BoxDecoration get premiumCard => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: border),
        boxShadow: cardShadow,
      );

  static BoxDecoration get glassCard => BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(radiusGlass),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      );
}

/// Light in-app shell: white AppBar + soft `#F4F7FB` body (register light zone).
class KaryawanPremiumScaffold extends StatelessWidget {
  const KaryawanPremiumScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.leading,
    this.centerTitle = true,
    this.eyebrow,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? leading;
  final bool centerTitle;
  final String? eyebrow;
  final bool extendBodyBehindAppBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final titleWidget = eyebrow == null || eyebrow!.isEmpty
        ? Text(title)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow!,
                style: const TextStyle(
                  color: OptikKaryawanTokens.goldSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: OptikKaryawanTokens.navyDeep,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: OptikKaryawanTokens.scaffold,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: centerTitle,
        backgroundColor: OptikKaryawanTokens.surface,
        foregroundColor: OptikKaryawanTokens.navyDeep,
        leading: leading,
        title: titleWidget,
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: OptikKaryawanTokens.border),
        ),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Dark brand shell for camera / OTP / absensi flows.
class KaryawanDarkScaffold extends StatelessWidget {
  const KaryawanDarkScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.centerTitle = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikKaryawanTokens.darkBg,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: centerTitle,
        backgroundColor: OptikKaryawanTokens.darkBg,
        foregroundColor: Colors.white,
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

/// Section title used on light premium pages.
class KaryawanSectionTitle extends StatelessWidget {
  const KaryawanSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: OptikKaryawanTokens.navyDeep,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

ThemeData buildKaryawanTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: OptikKaryawanTokens.scaffold,
    colorScheme: const ColorScheme.light(
      primary: OptikKaryawanTokens.navyMid,
      secondary: OptikKaryawanTokens.goldSoft,
      surface: OptikKaryawanTokens.surface,
      onPrimary: Colors.white,
      onSecondary: OptikKaryawanTokens.navyDeep,
      error: OptikKaryawanTokens.danger,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      backgroundColor: OptikKaryawanTokens.surface,
      foregroundColor: OptikKaryawanTokens.navyDeep,
      titleTextStyle: TextStyle(
        color: OptikKaryawanTokens.navyDeep,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: OptikKaryawanTokens.navyDeep),
    ),
    cardTheme: CardThemeData(
      color: OptikKaryawanTokens.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        side: const BorderSide(color: OptikKaryawanTokens.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OptikKaryawanTokens.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(color: OptikKaryawanTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(color: OptikKaryawanTokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(
          color: OptikKaryawanTokens.navyMid,
          width: 1.6,
        ),
      ),
      labelStyle: const TextStyle(
        color: OptikKaryawanTokens.muted,
        fontSize: 13,
      ),
      hintStyle: TextStyle(
        color: OptikKaryawanTokens.muted.withOpacity(0.75),
        fontSize: 13,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OptikKaryawanTokens.navyMid,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(double.infinity, 50),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OptikKaryawanTokens.navyMid,
        side: const BorderSide(color: OptikKaryawanTokens.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OptikKaryawanTokens.navyMid,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OptikKaryawanTokens.navyMid,
      foregroundColor: Colors.white,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: OptikKaryawanTokens.surface,
      elevation: 12,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OptikKaryawanTokens.gold,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: OptikKaryawanTokens.navyMid,
      textColor: OptikKaryawanTokens.ink,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return OptikKaryawanTokens.gold;
        }
        return OptikKaryawanTokens.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return OptikKaryawanTokens.goldSoft.withOpacity(0.45);
        }
        return OptikKaryawanTokens.border;
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OptikKaryawanTokens.surfaceMuted,
      selectedColor: OptikKaryawanTokens.goldSoft.withOpacity(0.28),
      labelStyle: const TextStyle(
        color: OptikKaryawanTokens.ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        side: const BorderSide(color: OptikKaryawanTokens.border),
      ),
      side: const BorderSide(color: OptikKaryawanTokens.border),
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
