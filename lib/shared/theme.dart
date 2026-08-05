import 'package:flutter/material.dart';

/// Design tokens — Admin **Frozen Lake** on white canvas
/// Canvas: snow/white · accents: ice `#ADD8E6` · slate · navy
///
/// Fungsi warna teks (wajib):
/// - **navy** → judul, nilai data, teks primer
/// - **slate** → label, meta, hint
/// - **ice** → aksen UI (border/badge/progress), bukan body text di putih
/// - **snow** → hanya di atas permukaan navy/gelap (tombol navy, hero navy, overlay)
/// - **success/warning/danger** → status semantik saja
abstract final class OptikAdminTokens {
  // Core palette (Frozen Lake) — exact hex
  static const Color slate = Color(0xFF6D8196);
  static const Color ice = Color(0xFFADD8E6);
  static const Color snow = Color(0xFFFFFAFA);
  static const Color navy = Color(0xFF000080);

  /// Kanvas putih — ice hanya aksen (badge, border, wash).
  static const Color bg = snow;
  static const Color bgMid = Color(0xFFF7FBFC);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardElevated = Color(0xFFF4FAFC);
  static const Color line = Color(0x336D8196);
  static const Color lineStrong = Color(0x4D6D8196);
  static const Color textPrimary = navy;
  static const Color textSecondary = Color(0xFF2A3F55);
  static const Color textMuted = slate;
  static const Color accent = ice;
  static const Color accentDeep = Color(0xFF8EC4D6);
  static const Color accentSoft = Color(0xFFC9E7F1);
  static const Color success = Color(0xFF3D8F7A);
  static const Color warning = Color(0xFF9A7B3C);
  static const Color danger = Color(0xFFA65D5D);
  static const Color training = Color(0xFF8B6914);
  static const Color trainingSoft = Color(0xFFC4A35A);

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

  /// Soft luxury depth — ambient + tight contact.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: navy.withOpacity(0.04),
          blurRadius: 32,
          spreadRadius: -4,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: slate.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get cardShadowHover => [
        BoxShadow(
          color: navy.withOpacity(0.055),
          blurRadius: 36,
          spreadRadius: -2,
          offset: const Offset(0, 18),
        ),
        BoxShadow(
          color: ice.withOpacity(0.28),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> glow(Color color) => [
        BoxShadow(
          color: color.withOpacity(0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static LinearGradient get bgGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFAFA),
          Color(0xFFF5FAFC),
          Color(0xFFFFFAFA),
        ],
        stops: [0.0, 0.5, 1.0],
      );

  static LinearGradient get accentGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFC5E8F2), ice, accentDeep],
      );

  static LinearGradient get cardSheen => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFFFFFF),
          Color.lerp(const Color(0xFFFFFFFF), ice, 0.04)!,
        ],
      );
}

/// Shared Frozen Lake theme (Admin / default) — light, ice-dominant.
ThemeData buildAdminTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: null,
  );

  return base.copyWith(
    scaffoldBackgroundColor: OptikAdminTokens.bg,
    colorScheme: const ColorScheme.light(
      primary: OptikAdminTokens.navy,
      secondary: OptikAdminTokens.ice,
      surface: OptikAdminTokens.card,
      error: OptikAdminTokens.danger,
      onPrimary: OptikAdminTokens.snow,
      onSecondary: OptikAdminTokens.navy,
      onSurface: OptikAdminTokens.navy,
      onError: OptikAdminTokens.snow,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: OptikAdminTokens.navy),
      titleTextStyle: TextStyle(
        color: OptikAdminTokens.navy,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: OptikAdminTokens.snow,
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
      backgroundColor: OptikAdminTokens.snow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusXl),
        side: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      titleTextStyle: const TextStyle(
        color: OptikAdminTokens.navy,
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
      backgroundColor: OptikAdminTokens.navy,
      contentTextStyle: const TextStyle(color: OptikAdminTokens.snow),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: OptikAdminTokens.slate,
      textColor: OptikAdminTokens.navy,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // bgMid di kanvas putih — snow membuat field “pucet” (hilang di kartu putih).
      fillColor: OptikAdminTokens.bgMid,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.navy, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        borderSide: const BorderSide(color: OptikAdminTokens.danger),
      ),
      labelStyle: const TextStyle(
        color: OptikAdminTokens.slate,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: OptikAdminTokens.slate.withOpacity(0.8),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      prefixIconColor: OptikAdminTokens.slate,
      suffixIconColor: OptikAdminTokens.slate,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OptikAdminTokens.navy,
        foregroundColor: OptikAdminTokens.snow,
        elevation: 0,
        shadowColor: OptikAdminTokens.navy.withOpacity(0.18),
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
        foregroundColor: OptikAdminTokens.navy,
        side: const BorderSide(color: OptikAdminTokens.slate),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OptikAdminTokens.navy,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OptikAdminTokens.navy,
      foregroundColor: OptikAdminTokens.snow,
      elevation: 2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OptikAdminTokens.navy,
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: OptikAdminTokens.navy,
      labelColor: OptikAdminTokens.navy,
      unselectedLabelColor: OptikAdminTokens.slate,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OptikAdminTokens.snow,
      selectedColor: OptikAdminTokens.ice,
      disabledColor: OptikAdminTokens.cardElevated,
      labelStyle: const TextStyle(
        color: OptikAdminTokens.navy,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: OptikAdminTokens.navy,
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

/// Member APK — putih–biru premium (konsisten semua halaman).
abstract final class OptikMemberTokens {
  static const Color blueDeep = Color(0xFF0B3D8C);
  static const Color blue = Color(0xFF1565C0);
  static const Color blueMid = Color(0xFF1E6FE0);
  static const Color blueSoft = Color(0xFFE8F1FF);
  static const Color blueMist = Color(0xFFF3F7FF);
  static const Color white = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF7FAFF);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSecondary = Color(0xFF475569);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color line = Color(0xFFD7E3F5);
  static const Color lineSoft = Color(0xFFE8EEF8);
  static const Color success = Color(0xFF0F766E);
  static const Color warning = Color(0xFFB45309);
  static const Color danger = Color(0xFFB91C1C);

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 24;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: blueDeep.withOpacity(0.06),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}

ThemeData buildMemberTheme() {
  const blue = OptikMemberTokens.blue;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: null,
    colorScheme: const ColorScheme.light(
      primary: OptikMemberTokens.blue,
      onPrimary: OptikMemberTokens.white,
      secondary: OptikMemberTokens.blueDeep,
      onSecondary: OptikMemberTokens.white,
      surface: OptikMemberTokens.white,
      onSurface: OptikMemberTokens.ink,
      error: OptikMemberTokens.danger,
      outline: OptikMemberTokens.line,
    ),
    scaffoldBackgroundColor: OptikMemberTokens.canvas,
    dividerColor: OptikMemberTokens.lineSoft,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: OptikMemberTokens.white,
      foregroundColor: OptikMemberTokens.blueDeep,
      titleTextStyle: TextStyle(
        color: OptikMemberTokens.blueDeep,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: OptikMemberTokens.blueDeep),
    ),
    cardTheme: CardThemeData(
      color: OptikMemberTokens.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        side: const BorderSide(color: OptikMemberTokens.lineSoft),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OptikMemberTokens.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: OptikMemberTokens.inkMuted),
      hintStyle: TextStyle(color: OptikMemberTokens.inkMuted.withOpacity(0.8)),
      prefixIconColor: OptikMemberTokens.blue,
      suffixIconColor: OptikMemberTokens.inkMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
        borderSide: const BorderSide(color: OptikMemberTokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
        borderSide: const BorderSide(color: OptikMemberTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
        borderSide: const BorderSide(color: blue, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OptikMemberTokens.blue,
        foregroundColor: OptikMemberTokens.white,
        disabledBackgroundColor: OptikMemberTokens.blueSoft,
        disabledForegroundColor: OptikMemberTokens.inkMuted,
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OptikMemberTokens.blueDeep,
        side: const BorderSide(color: OptikMemberTokens.line),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OptikMemberTokens.blue,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OptikMemberTokens.blueDeep,
      contentTextStyle: const TextStyle(color: OptikMemberTokens.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusSm),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: OptikMemberTokens.white,
      selectedItemColor: OptikMemberTokens.blue,
      unselectedItemColor: OptikMemberTokens.inkMuted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OptikMemberTokens.blue,
      foregroundColor: OptikMemberTokens.white,
      elevation: 2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OptikMemberTokens.blue,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OptikMemberTokens.blueSoft,
      selectedColor: OptikMemberTokens.blue,
      labelStyle: const TextStyle(
        color: OptikMemberTokens.blueDeep,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}
