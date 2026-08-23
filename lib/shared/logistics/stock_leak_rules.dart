import '../attendance/attendance_admin_scope.dart';

/// Aturan cek kebocoran stok — UI + tes harus sama dengan SQL 000031/000043.
abstract final class StockLeakRules {
  static const int minAlasanChars = 3;

  static bool alasanCukup(String alasan) =>
      alasan.trim().length >= minAlasanChars;

  /// Stok rak / qty positif. `8.0` dan `8` sama; negatif jadi 0.
  static int stockOf(Object? raw) {
    final n = deltaOf(raw);
    return n > 0 ? n : 0;
  }

  /// `qty_delta` ledger: `-2.0` tetap −2 (WRITE_OFF tidak boleh jadi 0).
  static int deltaOf(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final s = raw.toString().trim();
    if (s.isEmpty || s == '-') return 0;
    return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
  }

  /// Pcs stok rusak dari Σ WRITE_OFF (selalu ≥ 0).
  static int writeOffPcs(Object? raw) => deltaOf(raw).abs();

  static int writeOffPcsOf(Map<String, int> byReason) =>
      writeOffPcs(byReason['WRITE_OFF']);

  /// PUSAT dan CABANG-PUSAT satu kunci, supaya ledger write-off tidak “bocor”.
  static String tokoKey(Object? raw) {
    final t = (raw ?? '').toString().trim().toUpperCase();
    if (t.isEmpty || t == 'NULL') return '';
    if (t == 'PUSAT' || t == 'CABANG-PUSAT') return 'PUSAT';
    return t;
  }

  static Map<String, int> reasonMapOf(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        e.key.toString().trim().toUpperCase(): deltaOf(e.value),
    };
  }

  /// Rumus toko: stok rak == Σ qty_delta (termasuk WRITE_OFF).
  static bool sinkron({required int stock, required int ledgerSum}) =>
      stock == ledgerSum;

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
