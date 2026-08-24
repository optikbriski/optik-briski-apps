import '../attendance/attendance_admin_scope.dart';
import '../logistics/product_identity.dart';

/// Aturan beranda Member: satu tenant, toko yang sama, uang JSON.
abstract final class MemberHomeRules {
  static const bannerFolder = 'banners';

  static int moneyOf(Object? raw) => ProductIdentity.moneyOf(raw);

  static int countOf(Object? raw) => ProductIdentity.countOf(raw);

  /// Kuota opsional. Kosong = tanpa batas, bukan 0.
  static int? optionalCount(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return ProductIdentity.countOf(raw);
  }

  static String storeChipLabel(String? tokoId) {
    final raw = (tokoId ?? '').trim();
    if (raw.isEmpty) return 'Belum dipilih';
    if (AttendanceAdminScope.isPusatTokoId(raw)) return 'Pusat';
    return raw.replaceFirst(RegExp(r'^CABANG-', caseSensitive: false), '');
  }

  /// Path Foto Frame: `{tenant}/banners/…` — merek tidak saling timpa.
  static String bannerObjectPath({
    required String tenantId,
    required String fileName,
    int? nowMs,
  }) {
    final tenant = tenantId.trim();
    if (tenant.isEmpty) {
      throw StateError('tenant wajib — banner tidak boleh ke folder bersama');
    }
    final safe = fileName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final name = safe.isEmpty ? 'banner.jpg' : safe;
    final ms = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return '$tenant/$bannerFolder/${ms}_$name';
  }

  static bool promoStillAvailable(
    Map<String, dynamic> p, {
    DateTime? now,
  }) {
    final left = optionalCount(p['quantity_remaining']);
    if (left != null && left <= 0) return false;
    final untilRaw = p['valid_until'];
    if (untilRaw == null) return true;
    final until = DateTime.tryParse(untilRaw.toString());
    if (until == null) return true;
    final today = now ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final end = DateTime(until.year, until.month, until.day);
    return !end.isBefore(todayDate);
  }
}
