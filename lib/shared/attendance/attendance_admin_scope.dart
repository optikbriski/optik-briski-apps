/// Role scope untuk UX Absensi Admin (monitor vs kiosk).
///
/// Absensi kiosk (QR + liveness/facematch) ada di **cabang** dan **Pusat**.
/// Monitor Absensi Pusat hanya **owner** yang boleh lihat/validasi.
class AttendanceAdminScope {
  AttendanceAdminScope._();

  static String roleOf(Map<String, dynamic> profile) =>
      (profile['role'] ?? '').toString().trim();

  static String tokoOf(Map<String, dynamic> profile) =>
      (profile['toko_id'] ?? '').toString().trim();

  static bool isOwner(Map<String, dynamic> profile) =>
      roleOf(profile) == 'owner';

  static bool isAdminPusat(Map<String, dynamic> profile) =>
      roleOf(profile) == 'admin_pusat';

  static bool isAdminToko(Map<String, dynamic> profile) =>
      roleOf(profile) == 'admin_toko';

  /// Meta / operasional toko pusat.
  static bool isPusatTokoId(String? tokoId) {
    final t = (tokoId ?? '').trim();
    return t == 'PUSAT' || t == 'CABANG-PUSAT';
  }

  /// Samakan PUSAT ↔ CABANG-PUSAT untuk cek toko kiosk / hak akses.
  static bool sameTokoId(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    return isPusatTokoId(x) && isPusatTokoId(y);
  }

  /// Boleh buka monitor multi-toko (drill-down).
  static bool canOpenStoreMonitor(Map<String, dynamic> profile) =>
      isOwner(profile) || isAdminPusat(profile);

  /// Editor geofence toko: hanya owner / admin_pusat (bukan admin_toko cabang).
  static bool canManageGeofence(Map<String, dynamic> profile) =>
      isOwner(profile) || isAdminPusat(profile);

  /// Kiosk QR + face match di perangkat toko.
  /// - admin_toko: ya (toko cabang / toko sendiri)
  /// - owner: ya (kiosk Absensi Pusat)
  /// - admin_pusat: ya (kiosk Absensi Pusat — operasi perangkat;
  ///   monitor/validasi absensi Pusat tetap owner-only)
  static bool canOpenStoreKiosk(Map<String, dynamic> profile) {
    if (isOwner(profile) || isAdminPusat(profile)) return true;
    return isAdminToko(profile);
  }

  /// Label tile/AppBar: "Absensi Pusat" untuk owner, admin_pusat, atau
  /// admin_toko yang assigned ke toko Pusat.
  static bool isPusatKioskLabel(Map<String, dynamic> profile) {
    if (isOwner(profile) || isAdminPusat(profile)) return true;
    return isPusatTokoId(tokoOf(profile));
  }

  /// Apakah kiosk harus memakai toko Pusat (bukan cabang)?
  /// Owner & admin_pusat → Pusat; admin_toko hanya jika assigned PUSAT/CABANG-PUSAT.
  static bool usesPusatKioskToko(Map<String, dynamic> profile) {
    if (isOwner(profile) || isAdminPusat(profile)) return true;
    return isPusatTokoId(tokoOf(profile));
  }

  /// Boleh lihat/nilai absensi toko ini?
  /// - owner: semua (cabang + pusat)
  /// - admin_pusat: hanya cabang (bukan absensi Pusat sendiri)
  /// - cabang: hanya toko sendiri (kiosk; bukan antrean multi-toko)
  static bool canAccessTokoAttendance(
    Map<String, dynamic> profile,
    String? tokoId,
  ) {
    if (isOwner(profile)) return true;
    if (isAdminPusat(profile)) return !isPusatTokoId(tokoId);
    final own = tokoOf(profile);
    if (own.isEmpty) return false;
    return sameTokoId(own, tokoId);
  }

  /// Filter daftar toko untuk monitor:
  /// - owner: semua termasuk Pusat
  /// - admin_pusat: semua cabang, exclude PUSAT / CABANG-PUSAT
  static List<String> filterTokoForMonitor(
    List<String> allTokoIds,
    Map<String, dynamic> profile,
  ) {
    final cleaned = [
      for (final t in allTokoIds)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (isOwner(profile)) return cleaned;
    if (isAdminPusat(profile)) {
      return [
        for (final t in cleaned)
          if (!isPusatTokoId(t)) t,
      ];
    }
    final own = tokoOf(profile);
    if (own.isEmpty) return const [];
    return [own];
  }

  /// Saring baris verifikasi/antrean sesuai hak akses role.
  static List<Map<String, dynamic>> filterVerificationRows(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> profile,
  ) {
    return [
      for (final r in rows)
        if (canAccessTokoAttendance(profile, r['toko_id']?.toString())) r,
    ];
  }
}
