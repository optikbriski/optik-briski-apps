import '../tenant/tenant_service.dart';

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

  /// Filter query toko: PUSAT dan CABANG-PUSAT harus ikut bersama.
  static List<String> storeIdAliases(String? tokoId) {
    final t = (tokoId ?? '').trim();
    if (t.isEmpty) return const [];
    if (isPusatTokoId(t)) return const ['PUSAT', 'CABANG-PUSAT'];
    return [t];
  }

  static List<String> expandStoreIds(Iterable<String> ids) {
    final out = <String>{};
    for (final id in ids) {
      out.addAll(storeIdAliases(id));
    }
    return out.toList();
  }

  /// Tinjauan: pending → aman | mencurigakan. Mencurigakan → aman | curang.
  static bool canFlagMencurigakan(String? status) =>
      (status ?? '').trim() == 'pending_review';

  static bool canResolveAman(String? status) {
    final s = (status ?? '').trim();
    return s == 'pending_review' || s == 'mencurigakan';
  }

  static bool canResolveCurang(String? status) =>
      (status ?? '').trim() == 'mencurigakan';

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

  /// Tenant sesi monitor. Kulit Rekasa / Optik tidak mengganti ini.
  /// Kosong = belum terikat usaha → jangan baca merek lain.
  static String? tenantIdOf(Map<String, dynamic>? profile) {
    final fromProfile = (profile?['tenant_id'] ?? '').toString().trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    return boundTenantIdOrNull();
  }

  /// UUID usaha yang sudah di-resolve. Null jika belum — jangan panggil boundId.
  static String? boundTenantIdOrNull() {
    if (!TenantService.instance.isBound) return null;
    final id = (TenantService.instance.id ?? '').trim();
    return id.isEmpty ? null : id;
  }

  /// Baris absensi vs tenant sesi yang sudah terikat. Belum terikat = jangan lolos.
  static bool matchesBoundTenant(String? rowTenantId) {
    final bound = boundTenantIdOrNull();
    final row = (rowTenantId ?? '').trim();
    if (bound == null || bound.isEmpty || row.isEmpty) return false;
    return bound == row;
  }

  /// Clock-in/out: karyawan harus usaha yang sama. Belum terikat = lewati
  /// (RLS `current_tenant_id()` tetap memegang).
  static void assertKaryawanTenant(Map<String, dynamic> karyawan) {
    final bound = boundTenantIdOrNull();
    if (bound == null) return;
    final k = (karyawan['tenant_id'] ?? '').toString().trim();
    if (k.isEmpty || k != bound) {
      throw StateError('Akun karyawan bukan milik usaha ini.');
    }
  }

  /// Baris absensi milik usaha yang sama. Bukan sekat kulit.
  static bool sameTenant(Map<String, dynamic> profile, String? rowTenantId) {
    final a = tenantIdOf(profile);
    final b = (rowTenantId ?? '').trim();
    if (a == null || a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  /// Boleh lihat/nilai absensi toko ini?
  /// - owner / super_admin: semua (cabang + pusat) **di tenant sendiri**
  /// - admin_pusat: hanya cabang (bukan absensi Pusat sendiri)
  /// - admin_toko: hanya toko sendiri
  static bool canAccessTokoAttendance(
    Map<String, dynamic> profile,
    String? tokoId, {
    String? rowTenantId,
  }) {
    if (rowTenantId != null && !sameTenant(profile, rowTenantId)) {
      return false;
    }
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
        if (canAccessTokoAttendance(
          profile,
          r['toko_id']?.toString(),
          rowTenantId: r['tenant_id']?.toString(),
        ))
          r,
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
