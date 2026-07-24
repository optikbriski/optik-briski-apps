/// Penalti keterlambatan + aturan jam paling awal absen pulang.
///
/// **Shift pagi** (`jam_masuk` 08:30):
/// - 08:30:01 … 09:00:00 → −1 poin / menit (dari 08:30)
/// - 09:00:01 … → hanya −20 / 15 menit dari 09:00
///   (09:00:01 → −20; 09:15:01 → −40; …) — tidak ditumpuk dengan −1/menit
///
/// **Shift siang** (`jam_masuk` 13:00):
/// - 13:00:01 … → −20 / 15 menit dari 13:00
///
/// **Pulang paling awal (scan QR):**
/// - Shift pagi → mulai 17:00
/// - Shift siang/malem → mulai 21:00
abstract final class AttendanceLatePenalty {
  static const int bracketMinutes = 15;
  static const int pointsPerBracket = 20;

  /// Jendela lunak shift pagi: datang 08:30 → buka 09:00.
  static const int morningSoftWindowMinutes = 30;
  static const int softPointsPerMinute = 1;

  /// `jam_masuk` jam lokal < 12 = pagi; ≥ 12 (13:00) = siang.
  static const int morningShiftHourBefore = 12;

  /// Jam lokal Jakarta paling awal boleh absen pulang.
  static const int pagiEarliestPulangHour = 17;
  static const int siangEarliestPulangHour = 21;

  static const String sumberPoinTelat = 'ABSEN_TELAT';

  static bool isMorningShift(int hourJakarta) =>
      hourJakarta < morningShiftHourBefore;

  /// Hitung penalti dari jam datang terjadwal + waktu clock-in.
  static LatePenaltyResult compute({
    required DateTime clockInUtc,
    required DateTime scheduledMasukUtc,
    int? scheduledMasukHourJakarta,
  }) {
    final lateSecs = lateSeconds(
      clockInUtc: clockInUtc,
      scheduledMasukUtc: scheduledMasukUtc,
    );
    if (lateSecs <= 0) {
      return const LatePenaltyResult(lateSeconds: 0, penaltyPoints: 0);
    }

    final hour = scheduledMasukHourJakarta ??
        scheduledMasukUtc.add(const Duration(hours: 7)).hour;

    if (!isMorningShift(hour)) {
      // Shift siang 13:00: −20 / 15 menit dari jam_masuk.
      final hard = pointsForHardLate(Duration(seconds: lateSecs));
      return LatePenaltyResult(
        lateSeconds: lateSecs,
        penaltyPoints: hard,
        softPenaltyPoints: 0,
        hardPenaltyPoints: hard,
      );
    }

    final softEnd = scheduledMasukUtc.add(
      Duration(minutes: morningSoftWindowMinutes),
    ); // 09:00:00
    final clock = clockInUtc.toUtc();

    // Sampai 09:00:00 inklusif: hanya −1 / menit.
    if (!clock.isAfter(softEnd)) {
      final mins = _ceilMinutes(lateSecs);
      final soft = -(mins * softPointsPerMinute);
      return LatePenaltyResult(
        lateSeconds: lateSecs,
        penaltyPoints: soft,
        softPenaltyPoints: soft,
        hardPenaltyPoints: 0,
      );
    }

    // Dari 09:00:01: hanya −20 / 15 menit dari jam buka (tanpa numpuk soft).
    final afterOpenSecs = clock.difference(softEnd).inSeconds;
    final hard = pointsForHardLate(Duration(seconds: afterOpenSecs));
    return LatePenaltyResult(
      lateSeconds: lateSecs,
      penaltyPoints: hard,
      softPenaltyPoints: 0,
      hardPenaltyPoints: hard,
    );
  }

  /// Setiap 15 menit −20 (kelipatan): 1 dtk–15:00 → −20; 15:01–30:00 → −40; …
  static int pointsForHardLate(Duration late) {
    if (late <= Duration.zero) return 0;
    final bracketSecs = bracketMinutes * 60;
    // ceil(detik / 900) × 20  →  −20 + −20 + −20 …
    final brackets = (late.inSeconds + bracketSecs - 1) ~/ bracketSecs;
    if (brackets <= 0) return 0;
    return -(brackets * pointsPerBracket);
  }

  static int lateSeconds({
    required DateTime clockInUtc,
    required DateTime scheduledMasukUtc,
  }) {
    final diff = clockInUtc.toUtc().difference(scheduledMasukUtc.toUtc());
    if (diff.isNegative) return 0;
    return diff.inSeconds;
  }

  static int _ceilMinutes(int seconds) {
    if (seconds <= 0) return 0;
    return (seconds + 59) ~/ 60;
  }

  /// Jam paling awal absen pulang (UTC) untuk tanggal Jakarta [tanggalKey].
  static DateTime earliestPulangUtc({
    required String tanggalKey,
    required int jamMasukHourJakarta,
  }) {
    final hour = isMorningShift(jamMasukHourJakarta)
        ? pagiEarliestPulangHour
        : siangEarliestPulangHour;
    final parsed = _parseJakartaTime(
      tanggalKey: tanggalKey,
      jam: '${hour.toString().padLeft(2, '0')}:00:00',
    );
    // Fallback aman: siang 21:00 hari itu sebagai UTC kasar.
    return parsed?.utc ??
        DateTime.now().toUtc().subtract(const Duration(hours: 7));
  }

  static String earliestPulangLabel(int jamMasukHourJakarta) {
    final h = isMorningShift(jamMasukHourJakarta)
        ? pagiEarliestPulangHour
        : siangEarliestPulangHour;
    return '${h.toString().padLeft(2, '0')}:00';
  }

  static DateTime? scheduledMasukUtc({
    required String tanggalKey,
    required String jamMasuk,
  }) {
    return _parseJakartaTime(tanggalKey: tanggalKey, jam: jamMasuk)?.utc;
  }

  static ({DateTime utc, int hour, int minute})? _parseJakartaTime({
    required String tanggalKey,
    required String jam,
  }) {
    final day = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(tanggalKey);
    if (day == null) return null;
    final y = int.parse(day.group(1)!);
    final mo = int.parse(day.group(2)!);
    final d = int.parse(day.group(3)!);

    final raw = jam.trim();
    if (raw.isEmpty) return null;
    final timePart = raw.split(RegExp(r'[T\s]')).last;
    final bits = timePart.split(':');
    if (bits.length < 2) return null;
    final h = int.tryParse(bits[0]);
    final mi = int.tryParse(bits[1]);
    if (h == null || mi == null) return null;
    final secRaw = bits.length > 2 ? bits[2] : '0';
    final s = int.tryParse(secRaw.split('.').first.split('+').first) ?? 0;

    final utc =
        DateTime.utc(y, mo, d, h, mi, s).subtract(const Duration(hours: 7));
    return (utc: utc, hour: h, minute: mi);
  }

  static ({DateTime utc, int hourJakarta})? parseSchedule({
    required String tanggalKey,
    required String jamMasuk,
  }) {
    final p = _parseJakartaTime(tanggalKey: tanggalKey, jam: jamMasuk);
    if (p == null) return null;
    return (utc: p.utc, hourJakarta: p.hour);
  }

  static String refIdForLog(String logId) => 'absen-telat-$logId';
}

class LatePenaltyResult {
  const LatePenaltyResult({
    required this.lateSeconds,
    required this.penaltyPoints,
    this.softPenaltyPoints = 0,
    this.hardPenaltyPoints = 0,
  });

  final int lateSeconds;
  final int penaltyPoints;
  final int softPenaltyPoints;
  final int hardPenaltyPoints;

  bool get isLate => lateSeconds > 0 && penaltyPoints < 0;

  String get summary {
    if (!isLate) return '';
    final m = lateSeconds ~/ 60;
    final s = lateSeconds % 60;
    final parts = <String>[
      'Terlambat ${m}m ${s}s → poin $penaltyPoints',
    ];
    if (softPenaltyPoints < 0) {
      parts.add('(−1/menit s/d jam buka)');
    } else if (hardPenaltyPoints < 0) {
      final n =
          (-hardPenaltyPoints) ~/ AttendanceLatePenalty.pointsPerBracket;
      parts.add('(setiap 15 mnt −20 × $n)');
    }
    return parts.join(' ');
  }
}
