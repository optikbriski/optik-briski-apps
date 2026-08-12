import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Level warna api KPI — suhu api dunia nyata (dingin → panas).
///
/// Progres utama: [forKpiProgress] (0…1) dari skor tetap + fair share toko.
/// Legacy [forMonth] (hari streak) tetap ada untuk kompatibilitas riwayat lama.
class StreakFireLevel {
  const StreakFireLevel({
    required this.level,
    required this.days,
    required this.daysInMonth,
    required this.color,
    required this.glow,
    required this.labelKey,
    required this.tempHintKey,
  });

  final int level;
  final int days;
  final int daysInMonth;
  final Color color;
  final Color glow;
  final String labelKey;
  final String tempHintKey;

  int get fifth => level.clamp(0, 5);

  static const _palette = <_FirePalette>[
    _FirePalette(
      color: Color(0xFFE53935),
      glow: Color(0x66E53935),
      labelKey: 'streak_fire_merah',
      tempHintKey: 'streak_fire_merah_hint',
    ),
    _FirePalette(
      color: Color(0xFFFF6D00),
      glow: Color(0x66FF6D00),
      labelKey: 'streak_fire_oranye',
      tempHintKey: 'streak_fire_oranye_hint',
    ),
    _FirePalette(
      color: Color(0xFFFFC107),
      glow: Color(0x66FFC107),
      labelKey: 'streak_fire_kuning',
      tempHintKey: 'streak_fire_kuning_hint',
    ),
    _FirePalette(
      color: Color(0xFF2979FF),
      glow: Color(0x662979FF),
      labelKey: 'streak_fire_biru',
      tempHintKey: 'streak_fire_biru_hint',
    ),
    _FirePalette(
      color: Color(0xFFE8EEF5),
      glow: Color(0x66B0BEC5),
      labelKey: 'streak_fire_putih',
      tempHintKey: 'streak_fire_putih_hint',
    ),
  ];

  static double daysPerFifth(int daysInMonth) {
    final dim = daysInMonth < 1 ? 30 : daysInMonth;
    return dim / 5.0;
  }

  /// [daysInMonth] boleh kalender (28–31) atau skala KPI (mis. 1000).
  static int levelForDays(int days, int daysInMonth) {
    final dim = daysInMonth < 1 ? 30 : daysInMonth;
    if (days <= 0) return 0;
    final d = days.clamp(1, dim);
    final level = ((d * 5) + dim - 1) ~/ dim;
    return level.clamp(1, 5);
  }

  static int minDaysForLevel(int level, int daysInMonth) {
    final dim = daysInMonth < 1 ? 30 : daysInMonth;
    if (level <= 0) return 0;
    final lv = level.clamp(1, 5);
    final prevEnd = (dim * (lv - 1)) ~/ 5;
    return (prevEnd + 1).clamp(1, dim);
  }

  /// Api dari progres poin 0…1 (fifth = +20% tiap naik level).
  /// Poin 0 / progres 0 → level 1 (Red Flame) — titik start, sinkron dengan poin.
  static StreakFireLevel forKpiProgress(double progress) {
    final p = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    const scale = 1000;
    // Level 1 menutup band 0–20% (termasuk 0 poin).
    final level = p <= 0
        ? 1
        : (p >= 1.0 ? 5 : (p * 5).ceil().clamp(1, 5));
    final days = p <= 0 ? 0 : (p * scale).round().clamp(1, scale);
    final pal = _palette[level - 1];
    return StreakFireLevel(
      level: level,
      days: days,
      daysInMonth: scale,
      color: pal.color,
      glow: pal.glow,
      labelKey: pal.labelKey,
      tempHintKey: pal.tempHintKey,
    );
  }

  static StreakFireLevel forMonth({
    required int daysInMonthProgress,
    required int daysInMonth,
  }) {
    final dim = daysInMonth.clamp(28, 31);
    final days = daysInMonthProgress < 0 ? 0 : daysInMonthProgress;
    if (days <= 0) {
      return StreakFireLevel(
        level: 0,
        days: 0,
        daysInMonth: dim,
        color: const Color(0xFF9AA8AE),
        glow: const Color(0x339AA8AE),
        labelKey: 'streak_fire_none',
        tempHintKey: 'streak_fire_none_hint',
      );
    }
    final level = levelForDays(days, dim);
    final p = _palette[level - 1];
    return StreakFireLevel(
      level: level,
      days: days.clamp(0, dim),
      daysInMonth: dim,
      color: p.color,
      glow: p.glow,
      labelKey: p.labelKey,
      tempHintKey: p.tempHintKey,
    );
  }

  double get bandProgress {
    if (level <= 0) return 0;
    if (level >= 5) return 1;
    final start = minDaysForLevel(level, daysInMonth);
    final nextStart = minDaysForLevel(level + 1, daysInMonth);
    if (nextStart <= start) return 1;
    // Hari pertama fifth juga sudah sedikit naik.
    return ((days - start + 1) / (nextStart - start + 1)).clamp(0.0, 1.0);
  }

  double get monthProgress {
    if (daysInMonth <= 0) return 0;
    return (days / daysInMonth).clamp(0.0, 1.0);
  }

  Color get nextColor {
    if (level <= 0) return color;
    if (level >= 5) return _palette[4].color;
    return _palette[level].color;
  }

  Color get nextGlow {
    if (level <= 0) return glow;
    if (level >= 5) return _palette[4].glow;
    return _palette[level].glow;
  }

  /// Gradasi di tubuh api: warna berikutnya naik dari bawah.
  LinearGradient get riseGradient {
    final fill = level <= 0
        ? 0.0
        : level >= 5
            ? 1.0
            : bandProgress;
    final bottom = level >= 5 ? color : nextColor;
    final top = color;
    final t = fill.clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [bottom, bottom, top, top],
      stops: [0.0, t, t, 1.0],
    );
  }

  Color get blendedGlow {
    if (level <= 0 || level >= 5) return glow;
    return Color.lerp(glow, nextGlow, bandProgress) ?? glow;
  }

  Color get blendedColor {
    if (level <= 0) return color;
    if (level >= 5) return color;
    return Color.lerp(color, nextColor, bandProgress) ?? color;
  }

  static StreakFireLevel forDayInWindow({
    required int dayIndex,
    int daysInWindow = 30,
  }) {
    final dim = daysInWindow.clamp(28, 31);
    final day = (dayIndex + 1).clamp(0, dim);
    return forMonth(daysInMonthProgress: day, daysInMonth: dim);
  }

  static List<Color> get spectrumColors => [
        for (final p in _palette) p.color,
      ];

  static StreakFireLevel previewLevel(int level, {int daysInMonth = 30}) {
    final lv = level.clamp(1, 5);
    final dim = daysInMonth.clamp(28, 31);
    // Tengah-tengah fifth biar gradasi naik kelihatan di preview.
    final start = minDaysForLevel(lv, dim);
    final next = lv >= 5 ? dim : minDaysForLevel(lv + 1, dim);
    final mid = ((start + next) / 2).round().clamp(1, dim);
    return forMonth(daysInMonthProgress: mid, daysInMonth: dim);
  }

  static Color spectrumAt(double t) {
    final colors = spectrumColors;
    final x = t.clamp(0.0, 1.0) * (colors.length - 1);
    final i = x.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], x - i)!;
  }

  static Color spectrumDayColor(int dayIndex, {int daysInWindow = 30}) {
    if (daysInWindow <= 1) return spectrumColors.first;
    return spectrumAt(dayIndex / (daysInWindow - 1));
  }

  /// Gradasi spektrum di tubuh api untuk hari ke-[dayIndex].
  static LinearGradient spectrumFlameGradient(
    int dayIndex, {
    int daysInWindow = 30,
  }) {
    final t = daysInWindow <= 1 ? 0.0 : dayIndex / (daysInWindow - 1);
    final top = spectrumAt(t);
    final bottom = spectrumAt((t + 1 / 5).clamp(0.0, 1.0));
    final fill = ((t * 5) % 1.0);
    final f = fill < 0.08 ? 0.08 : fill;
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [bottom, bottom, top, top],
      stops: [0.0, f, f, 1.0],
    );
  }
}

/// Api dari asset foto referensi — bentuk asli, warna/gradasi per level.
class StreakFireFlame extends StatelessWidget {
  const StreakFireFlame({
    super.key,
    required this.fire,
    this.size = 28,
    this.solid = false,
    this.gradient,
    this.muted = false,
    this.dayIndex,
  });

  final StreakFireLevel fire;
  final double size;
  final bool solid;
  final Gradient? gradient;
  final bool muted;

  /// Kalau di-set, pakai asset spektrum harian `flame_dXX` (gradasi mulus).
  final int? dayIndex;

  /// Hari ke-[dayIndex] (0-based) dalam spektrum mulus 30 hari.
  factory StreakFireFlame.spectrumDay({
    Key? key,
    required int dayIndex,
    int daysInWindow = 30,
    double size = 22,
    bool muted = false,
  }) {
    final fire = StreakFireLevel.forDayInWindow(
      dayIndex: dayIndex,
      daysInWindow: daysInWindow,
    );
    return StreakFireFlame(
      key: key,
      fire: fire,
      size: size,
      muted: muted,
      dayIndex: dayIndex.clamp(0, 29),
    );
  }

  static String assetForLevel(int level) =>
      'assets/images/streak_flames/flame_l${level.clamp(1, 5)}.png';

  static String assetForDay(int dayIndex) =>
      'assets/images/streak_flames/flame_d${(dayIndex.clamp(0, 29) + 1).toString().padLeft(2, '0')}.png';

  /// Warna aksen UI — makin sangar: merah→oranye→emas→magenta→ungu.
  static ({Color bottom, Color mid, Color top, Color core}) levelPalette(
    int level,
  ) {
    switch (level.clamp(0, 5)) {
      case 1:
        return (
          bottom: const Color(0xFFFFECD2),
          mid: const Color(0xFFFF8C5A),
          top: const Color(0xFFDC302A),
          core: const Color(0xFFFFECD2),
        );
      case 2:
        return (
          bottom: const Color(0xFFFFF0C8),
          mid: const Color(0xFFFFAA46),
          top: const Color(0xFFFF5A00),
          core: const Color(0xFFFFF0C8),
        );
      case 3:
        return (
          bottom: const Color(0xFFFFFAD4),
          mid: const Color(0xFFFFD250),
          top: const Color(0xFFFFAA00),
          core: const Color(0xFFFFFAD4),
        );
      case 4:
        return (
          bottom: const Color(0xFFFFE6F2),
          mid: const Color(0xFFFF78B4),
          top: const Color(0xFFFF2878),
          core: const Color(0xFFFFE6F2),
        );
      case 5: // Puncak ungu sangar
        return (
          bottom: const Color(0xFFF0DCFF),
          mid: const Color(0xFFA050FF),
          top: const Color(0xFF5A14B4),
          core: const Color(0xFFF0DCFF),
        );
      default:
        return (
          bottom: const Color(0xFFCFD8DC),
          mid: const Color(0xFFB0BEC5),
          top: const Color(0xFF90A4AE),
          core: const Color(0xFFECEFF1),
        );
    }
  }

  /// Warna spektrum kontinyu 0..1 untuk border/teks grid 30 hari.
  static Color spectrumAccent(double t) {
    // Merah→oranye→emas→magenta→ungu. L4 masih magenta; ungu kuat di L5.
    const stops = <Color>[
      Color(0xFFDC302A), // merah
      Color(0xFFFF5A00), // oranye
      Color(0xFFFFAA00), // emas
      Color(0xFFFF2878), // magenta
      Color(0xFF5A14B4), // ungu puncak
    ];
    final x = t.clamp(0.0, 1.0) * (stops.length - 1);
    final i = x.floor().clamp(0, stops.length - 2);
    final f = x - i;
    // smoothstep — di segmen terakhir pelan ke ungu biar L4 tidak loncat.
    final s = i >= stops.length - 2
        ? (f * f * f) // ease-in: tahan magenta lebih lama
        : (f * f * (3 - 2 * f));
    return Color.lerp(stops[i], stops[i + 1], s)!;
  }

  @override
  Widget build(BuildContext context) {
    final level = fire.level <= 0 ? 1 : fire.level.clamp(1, 5);
    final next = level >= 5 ? 5 : level + 1;
    // Konsep asli: warna dari asset PNG (level / spektrum harian).
    // solid = jangan blend ke level berikutnya (hindari L3 kelihatan magenta).
    final blend = dayIndex != null ||
            muted ||
            solid ||
            fire.level <= 0 ||
            level >= 5
        ? 0.0
        : fire.bandProgress.clamp(0.0, 1.0);

    final h = size * (1.12 + level * 0.04);
    final w = size * (0.95 + level * 0.02);
    final pal = levelPalette(muted ? 0 : level);
    final primaryAsset = dayIndex != null
        ? assetForDay(dayIndex!)
        : assetForLevel(level);

    Widget flameImage(String asset, {double opacity = 1}) {
      final img = Image.asset(
        asset,
        width: w,
        height: h,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Icon(
          Icons.local_fire_department_rounded,
          size: size,
          color: pal.top,
        ),
      );
      if (opacity >= 0.99) return img;
      return Opacity(opacity: opacity, child: img);
    }

    Widget stack = Stack(
      alignment: Alignment.center,
      children: [
        flameImage(primaryAsset),
        if (blend > 0.04)
          flameImage(assetForLevel(next), opacity: blend),
      ],
    );

    if (muted) {
      stack = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.35, 0.45, 0.10, 0, 40,
          0.35, 0.45, 0.10, 0, 40,
          0.35, 0.45, 0.10, 0, 40,
          0, 0, 0, 0.55, 0,
        ]),
        child: stack,
      );
    } else {
      // Bayangan + bloom + tekstur asset — biar api terasa punya volume.
      stack = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Bayangan lembut di bawah api.
          Transform.translate(
            offset: Offset(size * 0.04, size * 0.14),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 3.2, sigmaY: 2.8),
              child: Opacity(
                opacity: 0.34,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF2A1208),
                    BlendMode.srcIn,
                  ),
                  child: flameImage(primaryAsset),
                ),
              ),
            ),
          ),
          // Bloom warna api (cahaya sekitar).
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 6.5, sigmaY: 6.5),
            child: Opacity(
              opacity: 0.38,
              child: flameImage(primaryAsset),
            ),
          ),
          // Inti api bertekstur (PNG).
          stack,
          // Kilau tipis di puncak — sedikit depth.
          IgnorePointer(
            child: Transform.translate(
              offset: Offset(0, -size * 0.06),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.6),
                child: Opacity(
                  opacity: 0.22,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      pal.core.withOpacity(0.95),
                      BlendMode.srcIn,
                    ),
                    child: flameImage(primaryAsset),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Room sedikit buat bayangan/bloom tidak terpotong.
    return SizedBox(
      width: w * 1.18,
      height: h * 1.22,
      child: Center(child: stack),
    );
  }
}

/// Progres premium: 5 api bertekstur.
/// [compact] = segmen tipis untuk kartu metrik sejajar (bukan flame step tinggi).
class StreakFireProgressBar extends StatelessWidget {
  const StreakFireProgressBar({
    super.key,
    required this.progress,
    this.height = 10,
    this.compact = false,
    this.trackColor,
    this.fillColor,
  });

  final double progress;
  final double height;
  final bool compact;

  /// Track kosong (default: border seaside). Pakai gelap di banner malam.
  final Color? trackColor;

  /// Override isi segmen (mis. putih di atas zona warna banner).
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    // Selaras forKpiProgress: 0 poin = level 1 (segmen 1 aktif tipis).
    final currentFifth = p <= 0 ? 1 : (p * 5).ceil().clamp(1, 5);
    final empty = trackColor ?? OptikKaryawanTokens.border.withOpacity(0.55);
    final atStart = p <= 0;

    if (compact) {
      // Banner: semua segmen terisi = warna api level sekarang (bukan spektrum campur).
      final barH = height.clamp(6.0, 12.0);
      final fill = fillColor ?? StreakFireFlame.levelPalette(currentFifth).mid;
      return SizedBox(
        height: barH,
        child: Row(
          children: [
            for (var i = 1; i <= 5; i++) ...[
              if (i > 1) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  height: barH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: i <= currentFifth
                        ? fill.withOpacity(
                            atStart
                                ? 0.35
                                : (i == currentFifth ? 0.95 : 0.62),
                          )
                        : empty,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      children: [
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: _FlameStep(
              level: i,
              active: i <= currentFifth,
              current: i == currentFifth,
              rise: atStart
                  ? 0.0
                  : i < currentFifth
                      ? 1.0
                      : i == currentFifth
                          ? ((p * 5) - (i - 1)).clamp(0.0, 1.0)
                          : 0.0,
            ),
          ),
        ],
      ],
    );
  }
}

class _FlameStep extends StatelessWidget {
  const _FlameStep({
    required this.level,
    required this.active,
    required this.current,
    required this.rise,
  });

  final int level;
  final bool active;
  final bool current;
  final double rise;

  @override
  Widget build(BuildContext context) {
    // Selalu api level slot ini — jangan naikkan ke level berikutnya lewat rise
    // (dulu bikin slot 3 terlihat magenta saat hampir penuh).
    final fire = StreakFireLevel.previewLevel(level);
    final pal = StreakFireFlame.levelPalette(level);
    final glow = 0.14 + (current ? 0.10 : 0.0) + rise * 0.08;

    final fill = !active
        ? const Color(0xFFF4F7F8)
        : Color.lerp(
            Colors.white,
            pal.bottom,
            current ? 0.92 : 0.55,
          )!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      height: current ? 58 : 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: fill,
        border: Border.all(
          color: current
              ? Color.lerp(pal.top, Colors.white, 0.35)!
              : OptikKaryawanTokens.border,
          width: current ? 1.4 : 1.0,
        ),
        boxShadow: current
            ? [
                BoxShadow(
                  color: Color.lerp(Colors.transparent, pal.mid, glow)!,
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ]
            : [
                BoxShadow(
                  color: OptikKaryawanTokens.ink.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Center(
        child: StreakFireFlame(
          fire: fire,
          size: current ? 26 : 20,
          muted: !active,
          solid: true,
        ),
      ),
    );
  }
}

/// Preview kelima warna — background netral, tekstur hanya di api.
class StreakFireSpectrumPreview extends StatelessWidget {
  const StreakFireSpectrumPreview({super.key});

  static const _labels = [
    'streak_fire_merah',
    'streak_fire_oranye',
    'streak_fire_kuning',
    'streak_fire_biru',
    'streak_fire_putih',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        OptikKaryawanTokens.seasidePale.withOpacity(0.45),
                      ],
                    ),
                    border: Border.all(
                      color: OptikKaryawanTokens.border.withOpacity(0.85),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: StreakFireFlame.levelPalette(i + 1)
                            .mid
                            .withOpacity(0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: StreakFireFlame(
                      fire: StreakFireLevel.previewLevel(i + 1),
                      size: 32 + i * 2.0,
                      solid: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${i + 1}/5',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: StreakFireFlame.levelPalette(i + 1)
                        .top
                        .withOpacity(0.95),
                  ),
                ),
                Text(
                  'kpi_level_band'.tr(args: ['${i * 20}', '${(i + 1) * 20}']),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: StreakFireFlame.levelPalette(i + 1)
                        .top
                        .withOpacity(0.80),
                  ),
                ),
                Text(
                  _labels[i].tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: OptikKaryawanTokens.muted.withOpacity(0.95),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FirePalette {
  const _FirePalette({
    required this.color,
    required this.glow,
    required this.labelKey,
    required this.tempHintKey,
  });

  final Color color;
  final Color glow;
  final String labelKey;
  final String tempHintKey;
}

class StreakFireMonthRecord {
  const StreakFireMonthRecord({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.daysAchieved,
    required this.fire,
  });

  final int year;
  final int month;
  final int daysInMonth;
  final int daysAchieved;
  final StreakFireLevel fire;

  String get monthKey =>
      '$year-${month.toString().padLeft(2, '0')}';
}
