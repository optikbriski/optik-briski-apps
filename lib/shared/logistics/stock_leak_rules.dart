import '../attendance/attendance_admin_scope.dart';

/// Aturan cek kebocoran stok — UI + tes harus sama dengan SQL 000031.
abstract final class StockLeakRules {
  static const int minAlasanChars = 3;

  static bool alasanCukup(String alasan) =>
      alasan.trim().length >= minAlasanChars;

  /// Tile hub: admin toko/pusat. Bukan owner etalase. Bukan kasir.
  static bool bolehBuka(Map<String, dynamic> profile) =>
      AttendanceAdminScope.canManageInventory(profile);

  /// Catat selisih toko ini? admin_toko hanya toko sendiri. Bukan cabang orang.
  static bool bolehRecognizeToko(
    Map<String, dynamic> profile,
    String? tokoId,
  ) =>
      AttendanceAdminScope.canManageInventoryToko(profile, tokoId);

  /// Hub pusat lihat semua cabang tenant. Cabang hanya toko sendiri.
  static bool scanSemuaToko(Map<String, dynamic> profile) =>
      AttendanceAdminScope.isAdminPusat(profile) ||
      AttendanceAdminScope.isSuperAdmin(profile);

  /// Rekognisi hanya melengkapi jejak. Stok rak tidak boleh berubah.
  static bool stokTetap({
    required int stockBefore,
    required int stockAfter,
  }) =>
      stockBefore == stockAfter;

  static bool adaSelisih(int delta) => delta != 0;
}
