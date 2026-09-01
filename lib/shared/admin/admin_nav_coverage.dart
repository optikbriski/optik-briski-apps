/// Katalog navigasi Admin — 7 grup main, 25 sub, scope badge, detail nav.
class AdminNavCoverage {
  AdminNavCoverage._();

  /// 7 grup sidebar (tanpa latihan/platform opsional).
  static const mainGroupIds = [
    'dashboard',
    'tim',
    'jual',
    'stok',
    'uang',
    'toko',
    'platform',
  ];

  /// 25 sub-nav item (profil admin cabang penuh, tanpa platform/latihan).
  static const subNavIds25 = [
    'rangkuman_kerja',
    'karyawan',
    'pengaduan',
    'reimburse',
    'lembur',
    'chat_toko',
    'monitor_absensi',
    'absensi_kiosk',
    'tinjauan',
    'geofence',
    'jadwal',
    'pos',
    'dp',
    'online',
    'logistik',
    'master',
    'garansi',
    'keuangan',
    'payroll',
    'invoice',
    'export',
    'member_home',
    'update_apk',
    'scan_dokumen',
    'scan_qr',
  ];

  static const subNavByMainGroup = {
    'dashboard': ['rangkuman_kerja'],
    'tim': [
      'karyawan',
      'pengaduan',
      'reimburse',
      'lembur',
      'chat_toko',
      'monitor_absensi',
      'absensi_kiosk',
      'tinjauan',
      'geofence',
      'jadwal',
    ],
    'jual': ['pos', 'dp', 'online'],
    'stok': ['logistik', 'master', 'garansi'],
    'uang': ['keuangan', 'payroll', 'invoice', 'export'],
    'toko': ['member_home', 'update_apk', 'scan_dokumen', 'scan_qr'],
    'platform': ['etalase', 'umkm'],
  };

  /// Scope badge realtime — id sidebar = scope id.
  static const badgeScopes = [
    'karyawan',
    'pengaduan',
    'reimburse',
    'lembur',
    'chat_toko',
    'jadwal',
    'logistik',
    'online',
    'monitor_absensi',
    'tinjauan',
    'update_apk',
  ];

  static const noBadgeSubNav = [
    'rangkuman_kerja',
    'absensi_kiosk',
    'geofence',
    'pos',
    'dp',
    'master',
    'garansi',
    'keuangan',
    'payroll',
    'invoice',
    'export',
    'member_home',
    'scan_dokumen',
    'scan_qr',
  ];

  /// Halaman isi + detail nav yang wajib pakai badge service.
  static const badgePageFiles = {
    'karyawan': 'lib/shared/admin_approval_page.dart',
    'pengaduan': 'lib/apps/admin/pengaduan_inbox_page.dart',
    'reimburse': 'lib/apps/admin/reimburse_inbox_page.dart',
    'lembur': 'lib/apps/admin/lembur_inbox_page.dart',
    'chat_toko': 'lib/apps/karyawan/toko_chat_page.dart',
    'jadwal': 'lib/apps/admin/jadwal_kerja_page.dart',
    'jadwal_detail': 'lib/apps/admin/jadwal_pengajuan_approval_page.dart',
    'logistik': 'lib/apps/admin/inventory.dart',
    'logistik_detail': 'lib/apps/admin/verifikasi_terima.dart',
    'online': 'lib/apps/admin/online_orders_page.dart',
    'monitor_absensi': 'lib/apps/admin/attendance_monitor_page.dart',
    'tinjauan': 'lib/apps/admin/tinjauan_mencurigakan_page.dart',
    'update_apk': 'lib/shared/app_update/app_software_update_page.dart',
    'logistik_bell': 'lib/apps/admin/global_notification.dart',
  };
}
