/// Role scope untuk UX Absensi Admin (monitor vs kiosk) + HR toko.
///
/// Absensi kiosk (QR + liveness/facematch) ada di **cabang** dan **Pusat**.
/// admin_toko hanya toko sendiri. Bukan semua cabang. Bukan merek lain.
/// toko_id PUSAT + role admin_toko ≠ operator pusat.
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

  static bool isSuperAdmin(Map<String, dynamic> profile) =>
      roleOf(profile) == 'super_admin';

  /// Owner / admin_pusat / super_admin — semua cabang di tenant sendiri.
  static bool isPusatOperator(Map<String, dynamic> profile) =>
      isOwner(profile) || isAdminPusat(profile) || isSuperAdmin(profile);

  /// Picker multi-toko. admin_toko (meski assigned PUSAT) = tidak.
  static bool canViewAllStores(Map<String, dynamic> profile) =>
      isPusatOperator(profile);

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

  /// Manajemen Karyawan: pusat semua toko; admin_toko toko sendiri.
  static bool canOpenKaryawanManagement(Map<String, dynamic> profile) {
    if (isPusatOperator(profile)) return true;
    return isAdminToko(profile) && tokoOf(profile).isNotEmpty;
  }

  /// Monitor absensi: pusat (scoped) atau admin_toko toko sendiri.
  static bool canOpenStoreMonitor(Map<String, dynamic> profile) =>
      canOpenKaryawanManagement(profile);

  /// Editor geofence: pusat semua toko; admin_toko hanya toko sendiri.
  static bool canManageGeofence(Map<String, dynamic> profile) =>
      canOpenKaryawanManagement(profile);

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
  /// - owner / super_admin: semua (cabang + pusat)
  /// - admin_pusat: hanya cabang (bukan absensi Pusat sendiri)
  /// - admin_toko: hanya toko sendiri
  static bool canAccessTokoAttendance(
    Map<String, dynamic> profile,
    String? tokoId,
  ) {
    if (isOwner(profile) || isSuperAdmin(profile)) return true;
    if (isAdminPusat(profile)) return !isPusatTokoId(tokoId);
    final own = tokoOf(profile);
    if (own.isEmpty) return false;
    return sameTokoId(own, tokoId);
  }

  /// Filter daftar toko untuk monitor:
  /// - owner / super_admin: semua termasuk Pusat
  /// - admin_pusat: semua cabang, exclude PUSAT / CABANG-PUSAT
  /// - admin_toko: toko sendiri saja
  static List<String> filterTokoForMonitor(
    List<String> allTokoIds,
    Map<String, dynamic> profile,
  ) {
    final cleaned = [
      for (final t in allTokoIds)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (isOwner(profile) || isSuperAdmin(profile)) return cleaned;
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

  /// Teks banner monitor — jangan samakan admin_toko dengan admin_pusat.
  static String monitorBannerHint(Map<String, dynamic> profile) {
    if (isAdminToko(profile)) {
      final own = tokoOf(profile);
      return own.isEmpty ? 'Toko sendiri' : 'Toko $own saja';
    }
    if (isOwner(profile) || isSuperAdmin(profile)) {
      return 'Semua toko termasuk Pusat';
    }
    return 'Cabang saja (tanpa absensi Pusat)';
  }

  /// Aksi Valid/Curang wajib bawa toko_id — jangan andalkan RLS saja.
  static String requireTokoId(String? tokoId) {
    final t = (tokoId ?? '').trim();
    if (t.isEmpty) {
      throw StateError('toko_id wajib untuk aksi monitor absensi.');
    }
    return t;
  }
}
