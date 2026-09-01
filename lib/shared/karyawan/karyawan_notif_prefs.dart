import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Preferensi notifikasi lokal Karyawan.
///
/// Saat shift OPEN, SOP + shift dianggap nyala (override toggle).
class KaryawanNotifPrefs {
  KaryawanNotifPrefs._();

  static const keySop = 'notif_sop';
  static const keyShift = 'notif_shift';

  static Future<bool> wantSop({required bool onDuty}) async {
    if (onDuty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keySop) ?? true;
  }

  static Future<bool> wantShift({required bool onDuty}) async {
    if (onDuty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyShift) ?? true;
  }

  /// Absen masuk OPEN hari ini (Jakarta) untuk [karyawanId].
  static Future<bool> isOnDuty(String karyawanId, {SupabaseClient? client}) async {
    final kid = karyawanId.trim();
    if (kid.isEmpty) return false;
    final db = client ?? Supabase.instance.client;
    try {
      final row = await db
          .from('attendance_shifts')
          .select('id')
          .eq('karyawan_id', kid)
          .eq('status', 'OPEN')
          .limit(1)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }
}
