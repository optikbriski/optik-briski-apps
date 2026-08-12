import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_mode.dart';
import 'attendance_service.dart';

/// Gate POS / Logistics / scan NIK admin: hanya karyawan yang sedang bertugas.
///
/// Syarat keras (semua harus terpenuhi):
/// - `status_approval` aktif (dicek pemanggil),
/// - jadwal hari ini bukan libur,
/// - ada `attendance_shifts` status `OPEN` = **sudah absen masuk** dan belom pulang.
///
/// Jadwal shift pagi/siang + masih di jam kerja **tidak cukup** bila belom absen masuk.
abstract final class PosDutyGate {
  /// Key i18n jika diblokir; `null` = boleh.
  static Future<String?> blockReason({
    required String karyawanId,
    String? nik,
  }) async {
    final n = (nik ?? '').trim().toUpperCase();
    // Mode latihan / NIK training: jangan blokir absensi-shift.
    if (n == 'TRAINING01' || TrainingMode.instance.isActive) return null;

    final svc = AttendanceService();
    final jadwal = await svc.fetchJadwalHariIni(karyawanId);
    if (jadwal != null && jadwal['is_libur'] == true) {
      return 'pos_duty_libur';
    }

    // Satu-satunya bukti "sedang kerja": shift OPEN (hasil absen masuk).
    final open = await svc.fetchOpenShift(karyawanId);
    if (open != null) return null;

    final sudahPulang = await svc.hasAttendanceLogToday(
      karyawanId: karyawanId,
      tipe: 'PULANG',
    );
    if (sudahPulang) return 'pos_duty_sudah_pulang';

    // Termasuk: ada jadwal shift & masih jam kerja, tapi belom absen masuk.
    return 'pos_duty_belum_masuk';
  }

  /// ID karyawan yang shift-nya masih OPEN.
  /// `tokoId` kosong = semua cabang. `null` return = jangan filter (mode training).
  static Future<Set<String>?> openShiftIdsForToko(String tokoId) async {
    if (TrainingMode.instance.isActive) return null;

    final tid = tokoId.trim();
    var q = Supabase.instance.client
        .from('attendance_shifts')
        .select('karyawan_id')
        .eq('status', 'OPEN');
    if (tid.isNotEmpty) {
      q = q.eq('toko_id', tid);
    }
    final rows = await q;
    return {
      for (final r in List<dynamic>.from(rows as List))
        if ((r as Map)['karyawan_id'] != null)
          r['karyawan_id'].toString(),
    };
  }
}
