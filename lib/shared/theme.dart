import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

/// Design tokens — Karyawan **Charming Seaside** on white canvas
/// (same concept as Admin Frozen Lake).
///
/// | Admin Frozen Lake | Karyawan Charming Seaside |
/// |-------------------|---------------------------|
/// | snow canvas       | snow / white canvas       |
/// | ice `#ADD8E6`     | cyan `#85D1DB` (dominant) |
/// | navy (text/CTA)   | ink (text)                |
/// | slate (muted)     | muted                     |
///
/// Palette: `#B3EBF2` · `#85D1DB` · `#B6F2D1` · `#C9FDF2`
///
/// Fungsi warna:
/// - **ink** → judul, nilai data, teks primer
/// - **muted** → label, meta, hint
/// - **cyan / accent** → aksen UI dominan (border, badge, CTA, wash)
/// - **pale** → soft wash / border sekunder
/// - **mint / aqua** → aksen sangat ringan saja (bukan fill besar)
/// - **snow** → kanvas & kartu
abstract final class OptikKaryawanTokens {
  // Core palette (Charming Seaside) — exact hex
  static const Color pale = Color(0xFFB3EBF2);
  static const Color cyan = Color(0xFF85D1DB);
  static const Color mint = Color(0xFFB6F2D1);
  static const Color aqua = Color(0xFFC9FDF2);

  static const Color snow = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF0E4A56);
  static const Color muted = Color(0xFF5B7C84);

  /// Kanvas putih — cyan hanya aksen (seperti ice di Admin).
  static const Color bg = snow;
  static const Color bgMid = Color(0xFFF5FBFC);
  static const Color panel = snow;
  static const Color card = snow;
  static const Color cardElevated = Color(0xFFF3FAFC);
  static const Color line = Color(0x3385D1DB);
  static const Color lineStrong = Color(0x6685D1DB);
  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF2A4A52);
  static const Color textMuted = muted;
  static const Color accent = cyan;
  static const Color accentDeep = Color(0xFF6FCBD6);
  static const Color accentSoft = pale;

  static const Color success = Color(0xFF3D8F7A);
  static const Color danger = Color(0xFFE57373);
  static const Color warning = Color(0xFFE6C35C);

  // —— Legacy aliases (kode lama karyawan) ——
  static const Color seasidePale = pale;
  static const Color seasideMid = cyan;
  static const Color seasideMint = mint;
  static const Color seasideIce = aqua;
  static const Color seasideWash = bgMid;
  static const Color seasideWashDeep = Color(0xFFE0F3F7);
  static const Color navyDeep = ink;
  static const Color navyMid = cyan;
  static const Color navySoft = pale;
  static const Color gold = cyan;
  static const Color goldSoft = pale;
  static const Color goldLite = bgMid;
  static const Color scaffold = bg;
  static const Color surface = card;
  static const Color surfaceMuted = bgMid;
  static const Color border = pale;
  static const Color darkBg = bgMid;
  static const Color darkCard = card;
  static const Color darkLine = lineStrong;

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusGlass = 24;

  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 14;
  static const double spaceLg = 20;
  static const double spaceXl = 28;

  /// Soft white canvas wash — paralel Admin `bgGradient`.
  static LinearGradient get bgGradient => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFF5FBFC),
          Color(0xFFFFFFFF),
        ],
        stops: [0.0, 0.5, 1.0],
      );

  /// Auth / login — soft cyan wash di atas putih (paralel Admin ice wash).
  static const LinearGradient authBgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x3885D1DB), // cyan @ ~22%
      bg,
      bgMid,
    ],
    stops: [0.0, 0.42, 1.0],
  );

  static LinearGradient get registerBgGradient => authBgGradient;

  /// Hero / header — cyan dominant.
  static LinearGradient get navyGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accentSoft, cyan, accentDeep],
      );

  /// CTA — solid cyan family (role = Admin accentGradient, tapi cyan).
  static LinearGradient get goldGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFA8DDE5), cyan, accentDeep],
      );

  static LinearGradient get accentGradient => goldGradient;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: ink.withOpacity(0.04),
          blurRadius: 32,
          spreadRadius: -4,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: cyan.withOpacity(0.10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static BoxDecoration get premiumCard => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: cyan.withOpacity(0.45)),
        boxShadow: cardShadow,
      );

  static BoxDecoration get glassCard => BoxDecoration(
        color: snow.withOpacity(0.92),
        borderRadius: BorderRadius.circular(radiusGlass),
        border: Border.all(color: cyan.withOpacity(0.50)),
        boxShadow: cardShadow,
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

/// Seaside light shell for camera / OTP / absensi flows (white canvas).
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
        backgroundColor: OptikKaryawanTokens.surface,
        foregroundColor: OptikKaryawanTokens.ink,
        leading: leading,
        title: Text(
          title,
          style: const TextStyle(
            color: OptikKaryawanTokens.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
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

/// Karyawan Charming Seaside — light, cyan-dominant (paralel Admin ice-dominant).
/// Tipografi: Plus Jakarta Sans (UI) + Fraunces (display/judul besar).
ThemeData buildKaryawanTheme() {
  final ink = OptikKaryawanTokens.ink;
  final muted = OptikKaryawanTokens.muted;
  final secondary = OptikKaryawanTokens.textSecondary;

  final body = GoogleFonts.plusJakartaSansTextTheme().apply(
    bodyColor: ink,
    displayColor: ink,
  );

  final textTheme = body.copyWith(
    displayLarge: GoogleFonts.fraunces(
      color: ink,
      fontSize: 40,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      height: 1.05,
    ),
    displayMedium: GoogleFonts.fraunces(
      color: ink,
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.0,
      height: 1.05,
    ),
    displaySmall: GoogleFonts.fraunces(
      color: ink,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.8,
      height: 1.1,
    ),
    headlineLarge: GoogleFonts.fraunces(
      color: ink,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.12,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    ),
    titleLarge: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 16,
      fontWeight: FontWeight.w800,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 14.5,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: GoogleFonts.plusJakartaSans(
      color: secondary,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    bodyLarge: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      color: muted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.35,
    ),
    labelLarge: GoogleFonts.plusJakartaSans(
      color: ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    labelMedium: GoogleFonts.plusJakartaSans(
      color: secondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
    labelSmall: GoogleFonts.plusJakartaSans(
      color: muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
  );

  return base.copyWith(
    scaffoldBackgroundColor: OptikKaryawanTokens.bg,
    colorScheme: const ColorScheme.light(
      primary: OptikKaryawanTokens.cyan,
      secondary: OptikKaryawanTokens.pale,
      surface: OptikKaryawanTokens.card,
      error: OptikKaryawanTokens.danger,
      onPrimary: OptikKaryawanTokens.ink,
      onSecondary: OptikKaryawanTokens.ink,
      onSurface: OptikKaryawanTokens.ink,
      onError: OptikKaryawanTokens.snow,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: OptikKaryawanTokens.snow,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: OptikKaryawanTokens.ink,
      iconTheme: const IconThemeData(color: OptikKaryawanTokens.ink),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: OptikKaryawanTokens.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: OptikKaryawanTokens.snow,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusLg),
        side: const BorderSide(color: OptikKaryawanTokens.line, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: OptikKaryawanTokens.line,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: OptikKaryawanTokens.snow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusXl),
        side: const BorderSide(color: OptikKaryawanTokens.lineStrong),
      ),
      titleTextStyle: const TextStyle(
        color: OptikKaryawanTokens.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: const TextStyle(
        color: OptikKaryawanTokens.textSecondary,
        fontSize: 14,
        height: 1.4,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OptikKaryawanTokens.bgMid,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(color: OptikKaryawanTokens.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(color: OptikKaryawanTokens.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        borderSide: const BorderSide(
          color: OptikKaryawanTokens.cyan,
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
      prefixIconColor: OptikKaryawanTokens.cyan,
      suffixIconColor: OptikKaryawanTokens.muted,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OptikKaryawanTokens.cyan,
        foregroundColor: OptikKaryawanTokens.ink,
        elevation: 0,
        // Jangan pakai width infinity — pecah dialog cropper / ButtonBar (web).
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        ),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OptikKaryawanTokens.ink,
        side: const BorderSide(color: OptikKaryawanTokens.cyan),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        ),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: OptikKaryawanTokens.cyan,
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OptikKaryawanTokens.cyan,
      foregroundColor: OptikKaryawanTokens.ink,
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: OptikKaryawanTokens.snow,
      elevation: 12,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: OptikKaryawanTokens.cyan,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: OptikKaryawanTokens.ink,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: OptikKaryawanTokens.snow,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: OptikKaryawanTokens.cyan,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusMd),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OptikKaryawanTokens.cyan,
        foregroundColor: OptikKaryawanTokens.ink,
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: OptikKaryawanTokens.cyan,
      textColor: OptikKaryawanTokens.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        color: OptikKaryawanTokens.ink,
        fontWeight: FontWeight.w700,
        fontSize: 14.5,
      ),
      subtitleTextStyle: GoogleFonts.plusJakartaSans(
        color: OptikKaryawanTokens.muted,
        fontWeight: FontWeight.w500,
        fontSize: 12.5,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return OptikKaryawanTokens.cyan;
        }
        return OptikKaryawanTokens.muted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return OptikKaryawanTokens.cyan.withOpacity(0.35);
        }
        return OptikKaryawanTokens.line;
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: OptikKaryawanTokens.bgMid,
      selectedColor: OptikKaryawanTokens.cyan.withOpacity(0.28),
      labelStyle: GoogleFonts.plusJakartaSans(
        color: OptikKaryawanTokens.ink,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OptikKaryawanTokens.radiusSm),
        side: const BorderSide(color: OptikKaryawanTokens.lineStrong),
      ),
      side: const BorderSide(color: OptikKaryawanTokens.lineStrong),
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
