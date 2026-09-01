import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3 mode tampilan Admin. Frozen Lake (sekarang) tetap default.
enum AdminAppearanceMode {
  frozenLake,
  komboLight,
  komboDark,
}

class AdminSwatch {
  const AdminSwatch({
    required this.slate,
    required this.ice,
    required this.snow,
    required this.navy,
    required this.bg,
    required this.bgMid,
    required this.panel,
    required this.card,
    required this.cardElevated,
    required this.line,
    required this.lineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentDeep,
    required this.accentSoft,
    required this.bgGradient,
    required this.accentGradient,
    required this.cardSheenTop,
  });

  final Color slate;
  final Color ice;
  final Color snow;
  final Color navy;
  final Color bg;
  final Color bgMid;
  final Color panel;
  final Color card;
  final Color cardElevated;
  final Color line;
  final Color lineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentDeep;
  final Color accentSoft;
  final LinearGradient bgGradient;
  final LinearGradient accentGradient;
  final Color cardSheenTop;
}

/// Palet aktif + persist. Frozen Lake tidak dihapus — hanya ditambah 2 kombo.
class AdminAppearance extends ChangeNotifier {
  AdminAppearance._();
  static final AdminAppearance instance = AdminAppearance._();

  static const _prefKey = 'admin_appearance_mode';

  AdminAppearanceMode _mode = AdminAppearanceMode.frozenLake;
  AdminAppearanceMode get mode => _mode;
  bool get isDark => _mode == AdminAppearanceMode.komboDark;
  bool get isKombo =>
      _mode == AdminAppearanceMode.komboLight ||
      _mode == AdminAppearanceMode.komboDark;

  AdminSwatch get swatch => switch (_mode) {
        AdminAppearanceMode.frozenLake => frozenLake,
        AdminAppearanceMode.komboLight => komboLight,
        AdminAppearanceMode.komboDark => komboDark,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    final parsed = AdminAppearanceMode.values.where((m) => m.name == raw);
    if (parsed.isEmpty) return;
    _mode = parsed.first;
    notifyListeners();
  }

  Future<void> setMode(AdminAppearanceMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }

  /// Frozen Lake — tampilan sekarang (es + navy).
  static const frozenLake = AdminSwatch(
    slate: Color(0xFF6D8196),
    ice: Color(0xFFADD8E6),
    snow: Color(0xFFFFFAFA),
    navy: Color(0xFF000080),
    bg: Color(0xFFFFFAFA),
    bgMid: Color(0xFFF7FBFC),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFF4FAFC),
    line: Color(0x336D8196),
    lineStrong: Color(0x4D6D8196),
    textPrimary: Color(0xFF000080),
    textSecondary: Color(0xFF2A3F55),
    textMuted: Color(0xFF6D8196),
    accent: Color(0xFFADD8E6),
    accentDeep: Color(0xFF8EC4D6),
    accentSoft: Color(0xFFC9E7F1),
    bgGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFE8F5F9),
        Color(0xFFF3FAFC),
        Color(0xFFEEF7FA),
      ],
      stops: [0.0, 0.48, 1.0],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC5E8F2), Color(0xFFADD8E6), Color(0xFF8EC4D6)],
    ),
    cardSheenTop: Color(0xFFFFFFFF),
  );

  /// Kombo terang: 1 kanvas krim, 2 highlight biru, 3 garnish terracotta.
  /// [ice] = wash pucat dari highlight — bukan terracotta (itu [accent]).
  static const komboLight = AdminSwatch(
    slate: Color(0xFF6B7394),
    ice: Color(0xFFE2E6F2),
    snow: Color(0xFFFBF7F4),
    navy: Color(0xFF2945A2),
    bg: Color(0xFFFBF7F4),
    bgMid: Color(0xFFFBF7F4),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFF7F3EF),
    line: Color(0x242945A2),
    lineStrong: Color(0x3D2945A2),
    textPrimary: Color(0xFF2945A2),
    textSecondary: Color(0xFF3D4F7A),
    textMuted: Color(0xFF6B7394),
    accent: Color(0xFFCC6047),
    accentDeep: Color(0xFFA84C38),
    accentSoft: Color(0xFFF4D4CC),
    bgGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFBF7F4),
        Color(0xFFFBF7F4),
        Color(0xFFF6F1EC),
      ],
      stops: [0.0, 0.48, 1.0],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCC6047), Color(0xFF2945A2)],
    ),
    cardSheenTop: Color(0xFFFFFFFF),
  );

  /// Kombo gelap: 1 kanvas slate, 2 highlight krim, 3 garnish emas.
  /// [ice] = wash panel — bukan emas (itu [accent]).
  static const komboDark = AdminSwatch(
    slate: Color(0xFF8B9AAB),
    ice: Color(0xFF3E5670),
    snow: Color(0xFF31485F),
    navy: Color(0xFFE7DEC8),
    bg: Color(0xFF31485F),
    bgMid: Color(0xFF31485F),
    panel: Color(0xFF3A5470),
    card: Color(0xFF3A5470),
    cardElevated: Color(0xFF425C74),
    line: Color(0x14E7DEC8),
    lineStrong: Color(0x22E7DEC8),
    textPrimary: Color(0xFFE7DEC8),
    textSecondary: Color(0xFFC5D0DC),
    textMuted: Color(0xFF8B9AAB),
    accent: Color(0xFFCBAF87),
    accentDeep: Color(0xFFB89668),
    accentSoft: Color(0xFF8A7358),
    bgGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF31485F),
        Color(0xFF31485F),
        Color(0xFF2A3F54),
      ],
      stops: [0.0, 0.48, 1.0],
    ),
    accentGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFCBAF87), Color(0xFFE7DEC8)],
    ),
    cardSheenTop: Color(0xFF3A5470),
  );
}
