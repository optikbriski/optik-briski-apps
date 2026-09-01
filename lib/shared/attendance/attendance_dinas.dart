import 'package:supabase_flutter/supabase_flutter.dart';

/// Dinas luar APPROVED hari ini (kalender Asia/Jakarta)
/// → absen boleh di luar geofence (GPS tetap wajib).
abstract final class AttendanceDinas {
  static String todayKey([DateTime? now]) {
    final wall = nowWall(now);
    final m = wall.month.toString().padLeft(2, '0');
    final d = wall.day.toString().padLeft(2, '0');
    return '${wall.year}-$m-$d';
  }

  /// Jam dinding Asia/Jakarta (tanpa DST), untuk UI & filter kalender toko.
  static DateTime nowWall([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final jkt = utc.add(const Duration(hours: 7));
    return DateTime(
      jkt.year,
      jkt.month,
      jkt.day,
      jkt.hour,
      jkt.minute,
      jkt.second,
      jkt.millisecond,
    );
  }

  static Future<bool> isApprovedToday(
    String karyawanId, {
    SupabaseClient? client,
  }) async {
    if (karyawanId.isEmpty) return false;
    final today = todayKey();
    try {
      final row = await (client ?? Supabase.instance.client)
          .from('jadwal_pengajuan')
          .select('id')
          .eq('karyawan_id', karyawanId)
          .eq('status', 'APPROVED')
          .eq('tipe', 'DINAS')
          .eq('tanggal', today)
          .limit(1)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }
}
