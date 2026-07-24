import 'attendance_late_penalty.dart';

/// Aturan jadwal absen + kapan peringatan keluar geofence aktif.
///
/// **Absen masuk** (harus di dalam geo + ada jadwal hari ini):
/// - Boleh kapan saja **sebelum / sesudah** jam standby (tidak ada jam paling awal).
/// - Contoh: shift pagi absen jam 05:00 → sah; shift siang absen jam 09:00 → sah.
/// - Datang setelah jam standby → absen tetap bisa, tapi kena penalti telat.
///
/// **Standby / peringatan keluar area** (setelah sudah absen / shift OPEN):
/// - Shift pagi → **08:30** — harus di wilayah geo; keluar → notifikasi
/// - Shift siang → **13:00** — harus di wilayah geo; keluar → notifikasi
///
/// Keterlambatan dihitung dari `jam_masuk` jadwal (pagi 08:30 / siang 13:00).
abstract final class AttendanceScheduleRules {
  /// Jam standby + peringatan keluar geofence (shift pagi).
  static const String pagiExitMonitorStart = '08:30:00';

  /// Jam standby + peringatan keluar geofence (shift siang).
  static const String siangExitMonitorStart = '13:00:00';

  static String exitMonitorStartTimeForHour(int jamMasukHourJakarta) {
    return AttendanceLatePenalty.isMorningShift(jamMasukHourJakarta)
        ? pagiExitMonitorStart
        : siangExitMonitorStart;
  }

  static String exitMonitorStartLabel(int jamMasukHourJakarta) {
    final t = exitMonitorStartTimeForHour(jamMasukHourJakarta);
    return t.substring(0, 5);
  }

  static DateTime? exitMonitorStartUtc({
    required String tanggalKey,
    required int jamMasukHourJakarta,
  }) {
    return AttendanceLatePenalty.scheduledMasukUtc(
      tanggalKey: tanggalKey,
      jamMasuk: exitMonitorStartTimeForHour(jamMasukHourJakarta),
    );
  }

  /// True jika sekarang sudah waktunya peringatan keluar geofence (jam standby).
  static bool isExitMonitorActiveNow({
    required DateTime nowUtc,
    required String tanggalKey,
    required int jamMasukHourJakarta,
  }) {
    final start = exitMonitorStartUtc(
      tanggalKey: tanggalKey,
      jamMasukHourJakarta: jamMasukHourJakarta,
    );
    if (start == null) return true;
    return !nowUtc.isBefore(start);
  }

  /// Validasi: wajib ada jadwal hari ini (bukan libur) + jam_masuk terisi.
  /// Tidak membatasi jam absen — boleh sebelum jam standby.
  static void assertCanStartMasukNow({
    required Map<String, dynamic>? jadwal,
    required String tanggalKey,
  }) {
    if (jadwal == null) {
      throw 'Belum ada jadwal kerja hari ini ($tanggalKey). '
          'Absen hanya bisa saat dijadwalkan.';
    }
    if (jadwal['is_libur'] == true) {
      throw 'Hari ini libur menurut jadwal. Absen tidak tersedia.';
    }
    final jamMasuk = (jadwal['jam_masuk'] ?? '').toString().trim();
    if (jamMasuk.isEmpty) {
      throw 'Jam masuk jadwal kosong. Hubungi Admin untuk set shift.';
    }

    final parsed = AttendanceLatePenalty.parseSchedule(
      tanggalKey: tanggalKey,
      jamMasuk: jamMasuk,
    );
    if (parsed == null) {
      throw 'Format jam masuk jadwal tidak valid.';
    }
  }
}
