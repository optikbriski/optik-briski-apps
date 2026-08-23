import '../attendance/attendance_admin_scope.dart';
import 'inventory_stock_rules.dart';

/// Aturan Request Order — UI + tes harus sama dengan SQL 000033/000045.
abstract final class RequestOrderRules {
  static const openStatuses = <String>[
    'PENDING',
    'SENT_TO_HQ',
    'APPROVED',
    'PREPARING',
    'SHIPPING',
  ];

  static bool transisiOk(String? from, String? to) =>
      InventoryStockRules.roTransitionOk(from, to);

  static int _parseSigned(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final s = raw.toString().trim();
    if (s.isEmpty || s == '-') return 0;
    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
  }

  /// ID RO. `123.0` dan `123` sama; 0/negatif = tidak valid.
  static int? idOf(Object? raw) {
    final n = _parseSigned(raw);
    return n > 0 ? n : null;
  }

  /// Qty minta / reserved. `2.0` dan `2` sama. Bukan harga jual.
  static int qtyOf(Object? raw) {
    final n = _parseSigned(raw);
    if (n <= 0) return 0;
    return n > 999 ? 999 : n;
  }

  /// Antrian cabang + kirim ke Pusat. Kasir/admin toko sendiri. Bukan cabang orang.
  static bool bolehBukaCabang(Map<String, dynamic> profile) {
    final toko = AttendanceAdminScope.tokoOf(profile);
    return AttendanceAdminScope.canRequestRoToko(profile, toko);
  }

  /// Board Pusat: approve / siapkan / kirim. Bukan owner. Bukan admin cabang.
  static bool bolehProsesPusat(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventoryToko(profile, 'PUSAT');

  static bool bolehKirimKePusat({
    required Map<String, dynamic> profile,
    required String? tokoId,
    required String? status,
  }) {
    if (InventoryStockRules.normRo(status) != InventoryStockRules.roPending) {
      return false;
    }
    return AttendanceAdminScope.canRequestRoToko(profile, tokoId);
  }

  static bool bolehApprove({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s != InventoryStockRules.roPending &&
        s != InventoryStockRules.roSent &&
        s != InventoryStockRules.roApproved) {
      return false;
    }
    return bolehProsesPusat(profile);
  }

  static bool bolehTolak({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s == InventoryStockRules.roShipping ||
        s == InventoryStockRules.roSuccess) {
      return false;
    }
    return bolehApprove(profile: profile, status: status) ||
        (s == InventoryStockRules.roPreparing && bolehProsesPusat(profile));
  }

  static bool bolehKirim({
    required Map<String, dynamic> profile,
    required String? status,
  }) {
    final s = InventoryStockRules.normRo(status);
    if (s != InventoryStockRules.roPreparing &&
        s != InventoryStockRules.roApproved) {
      return false;
    }
    return bolehProsesPusat(profile);
  }
}
