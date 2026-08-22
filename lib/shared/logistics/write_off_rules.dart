import '../attendance/attendance_admin_scope.dart';

/// Aturan stok rusak / write-off — UI + tes harus sama dengan SQL 000030.
abstract final class WriteOffRules {
  static const int minAlasanChars = 3;

  static bool alasanCukup(String alasan) =>
      alasan.trim().length >= minAlasanChars;

  static bool qtyValid(int qty) => qty > 0;

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
