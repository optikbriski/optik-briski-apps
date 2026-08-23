import '../attendance/attendance_admin_scope.dart';
import 'logistics_tracking_rules.dart';

/// Kapan toko / hub boleh buka peta Google live — bukan garis lurus OSM.
///
/// Transit antar kota = teks saja. Peta Google hanya setelah kurir tiba di
/// kota tujuan, dan hanya untuk toko yang sedang giliran. Toko berikutnya
/// tidak melihat meski kurir sudah di kota yang sama. Toko yang sudah
/// verifikasi tidak melihat lagi.
abstract final class LogisticsLiveMapRules {
  static bool statusMasihJalan(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'TRANSIT':
      case 'PENDING':
        return true;
      default:
        return false;
    }
  }

  static bool statusSelesai(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'SUCCESS':
      case 'BATAL':
      case 'REJECTED':
        return true;
      default:
        return false;
    }
  }

  /// Sel ~15 km. Toko A/B/C di Bandung masuk ember yang sama.
  /// Satu trip: kurir sama + kota tujuan sama.
  static List<Map<String, dynamic>> tripSameCity({
    required Map<String, dynamic> move,
    required List<Map<String, dynamic>> allMoves,
    required String Function(String? keLokasi) kotaOf,
  }) {
    final kurir = '${move['kurir_karyawan_id'] ?? ''}'.trim();
    final kota = kotaOf(move['ke_lokasi']?.toString());
    if (kurir.isEmpty || kota.isEmpty) return [move];
    return [
      for (final m in allMoves)
        if ('${m['kurir_karyawan_id'] ?? ''}'.trim() == kurir &&
            kotaOf(m['ke_lokasi']?.toString()) == kota)
          m,
    ];
  }

  static String kotaBucket(double? lat, double? lng) {
    if (lat == null || lng == null) return '';
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return '';
    return '${(lat * 7).round()}_${(lng * 7).round()}';
  }

  static int _createdOrd(Map<String, dynamic> m) {
    final raw = m['created_at'];
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return DateTime.tryParse('$raw')?.millisecondsSinceEpoch ?? 0;
  }

  /// Stop terbuka, urut dibuat. Giliran = yang pertama belum selesai.
  static String? currentStopKe(List<Map<String, dynamic>> tripStops) {
    final open = tripStops
        .where((m) => !statusSelesai(m['status']?.toString()))
        .toList()
      ..sort((a, b) => _createdOrd(a).compareTo(_createdOrd(b)));
    if (open.isEmpty) return null;
    return (open.first['ke_lokasi'] ?? '').toString();
  }

  /// Sudah masuk kota tujuan: ditandai, atau ada stop di kota itu yang
  /// PENDING/SUCCESS (sudah sampai / sudah serah ke toko sebelumnya).
  static bool arrivedInDestCity({
    required Map<String, dynamic> move,
    required List<Map<String, dynamic>> tripSameCity,
  }) {
    final stamped = '${move['tiba_kota_at'] ?? ''}'.trim();
    if (stamped.isNotEmpty && stamped != 'null') return true;
    if ((move['status'] ?? '').toString().toUpperCase() == 'PENDING') {
      return true;
    }
    for (final s in tripSameCity) {
      switch ((s['status'] ?? '').toString().toUpperCase()) {
        case 'PENDING':
        case 'SUCCESS':
          return true;
      }
    }
    return false;
  }

  static bool _viewerIsKe({
    required Map<String, dynamic> profile,
    required String ke,
  }) {
    final my = AttendanceAdminScope.tokoOf(profile);
    if (AttendanceAdminScope.sameTokoId(my, ke)) return true;
    final aliases = AttendanceAdminScope.storeIdAliases(my)
        .map((e) => e.toUpperCase())
        .toSet();
    return aliases.contains(ke.trim().toUpperCase());
  }

  /// Hub boleh pantau Google untuk stop yang sedang giliran, setelah tiba kota.
  /// Toko hanya jika surat jalan ini menuju toko mereka dan giliran mereka.
  static bool bolehLihatPetaLive({
    required Map<String, dynamic> profile,
    required Map<String, dynamic> move,
    required List<Map<String, dynamic>> tripSameCity,
  }) {
    if (!statusMasihJalan(move['status']?.toString())) return false;
    if (!arrivedInDestCity(move: move, tripSameCity: tripSameCity)) {
      return false;
    }
    final ke = (move['ke_lokasi'] ?? '').toString();
    final current = currentStopKe(tripSameCity);
    if (current == null || current.trim().isEmpty) return false;
    if (!AttendanceAdminScope.sameTokoId(current, ke) &&
        current.trim().toUpperCase() != ke.trim().toUpperCase()) {
      return false;
    }
    if (LogisticsTrackingRules.isHub(profile)) return true;
    return _viewerIsKe(profile: profile, ke: ke);
  }

  static String alasanTertutup({
    required Map<String, dynamic> profile,
    required Map<String, dynamic> move,
    required List<Map<String, dynamic>> tripSameCity,
  }) {
    final st = (move['status'] ?? '').toString().toUpperCase();
    if (statusSelesai(st)) {
      return 'Pengiriman selesai. Peta Google ditutup.';
    }
    if (!statusMasihJalan(st)) {
      return 'Masih disiapkan. Tracking Google belum dibuka.';
    }
    if (!arrivedInDestCity(move: move, tripSameCity: tripSameCity)) {
      return 'Masih transit. Peta Google terbuka setelah kurir tiba di kota tujuan.';
    }
    final ke = (move['ke_lokasi'] ?? '').toString();
    final current = currentStopKe(tripSameCity);
    if (current != null &&
        current.trim().isNotEmpty &&
        !AttendanceAdminScope.sameTokoId(current, ke) &&
        current.trim().toUpperCase() != ke.trim().toUpperCase()) {
      return 'Giliran toko lain dulu. Peta Google hanya untuk toko yang sedang dituju.';
    }
    if (!LogisticsTrackingRules.isHub(profile) &&
        !_viewerIsKe(profile: profile, ke: ke)) {
      return 'Bukan tujuan toko Anda. Peta Google tidak dibuka.';
    }
    return 'Peta Google belum dibuka.';
  }
}
