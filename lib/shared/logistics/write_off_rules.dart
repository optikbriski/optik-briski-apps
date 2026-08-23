import '../attendance/attendance_admin_scope.dart';
import 'product_identity.dart';

/// Aturan stok rusak / write-off — UI + tes harus sama dengan SQL 000030/000042.
abstract final class WriteOffRules {
  static const int minAlasanChars = 3;

  static bool alasanCukup(String alasan) =>
      alasan.trim().length >= minAlasanChars;

  static bool qtyValid(int qty) => qty > 0;

  /// Qty form / RPC. `2.0` dan `2` sama; negatif jadi 0.
  static int qtyOf(Object? raw) {
    final n = _parseSigned(raw);
    return n > 0 ? n : 0;
  }

  /// `qty_delta` ledger WRITE_OFF: `-2.0` tetap −2.
  static int deltaOf(Object? raw) => _parseSigned(raw);

  static int _parseSigned(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final s = raw.toString().trim();
    if (s.isEmpty || s == '-') return 0;
    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
  }

  /// Rugi buku gudang = qty × modal. Bukan harga jual.
  static int nilaiModal(int qty, Map<String, dynamic> product) {
    if (qty <= 0) return 0;
    return qty * ProductIdentity.modalPriceOf(product);
  }

  static int nilaiModalFromLedger(Map<String, dynamic> row) {
    final meta = row['meta'];
    Map<String, dynamic> m = const {};
    if (meta is Map) {
      m = Map<String, dynamic>.from(meta);
      final fromMeta = ProductIdentity.modalPriceOf({
        'harga_modal': m['nilai_modal'],
      });
      if (fromMeta > 0) return fromMeta;
    }
    final qty = deltaOf(row['qty_delta']).abs();
    return nilaiModal(qty, {...row, ...m});
  }

  /// Tile hub: admin toko/pusat. Bukan owner etalase. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventory(profile);

  /// Write-off toko ini? admin_toko hanya toko sendiri. Bukan cabang orang.
  static bool bolehWriteOffToko(
    Map<String, dynamic> profile,
    String? tokoId,
  ) =>
      AttendanceAdminScope.canManageInventoryToko(profile, tokoId);

  static bool bolehWriteOff({
    required bool canManageInventoryToko,
  }) =>
      canManageInventoryToko;

  /// Hanya stok tersedia (real − reserved) yang boleh dihapus.
  static bool tersediaCukup({
    required int real,
    required int reserved,
    required int qty,
  }) {
    if (!qtyValid(qty)) return false;
    return (real - reserved) >= qty;
  }

  /// Write-off selalu mengurangi stok; tidak pernah positif.
  static int qtyDelta(int qty) => -qty.abs();
}
