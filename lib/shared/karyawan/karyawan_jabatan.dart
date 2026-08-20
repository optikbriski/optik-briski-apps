/// Hierarki jabatan resmi tenant (nama merek dari app_brand).
///
/// Cabang (operasional toko): Frontliner, Backliner, Kepala Toko, Kepala Area.
/// Pusat (back-office web): Admin, Owner.
abstract final class KaryawanJabatan {
  static const frontliner = 'Frontliner';
  static const backliner = 'Backliner';
  static const kepalaToko = 'Kepala Toko';
  static const kepalaArea = 'Kepala Area';
  static const admin = 'Admin';
  static const owner = 'Owner';

  /// Urutan hierarki (rendah → tinggi). Termasuk Owner untuk HR/TOTP legacy.
  static const List<String> all = [
    frontliner,
    backliner,
    kepalaToko,
    kepalaArea,
    admin,
    owner,
  ];

  /// Self-register Karyawan — Owner tidak boleh dipilih (akun Owner diprovision Admin).
  static const List<String> registerable = [
    frontliner,
    backliner,
    kepalaToko,
    kepalaArea,
    admin,
  ];

  static String normalize(String? raw) => (raw ?? '').trim().toLowerCase();

  /// Digit pertama kode login Admin (6 angka).
  /// 1 Owner · 2 Admin · 3 Kepala Area · 4 Kepala Toko.
  static String? loginCodePrefix(String? jabatan) {
    switch (normalize(jabatan)) {
      case 'owner':
        return '1';
      case 'admin':
        return '2';
      case 'kepala area':
        return '3';
      case 'kepala toko':
        return '4';
      default:
        return null;
    }
  }

  /// Boleh tampilkan kode login Admin di APK.
  /// - PUSAT: hanya **Admin** / **Owner** (semua admin punya kode unik → ter-track)
  /// - Cabang: **Kepala Toko** / **Kepala Area** (wewenang akses web toko)
  /// - Frontliner / Backliner: tidak pernah (posisi karyawan toko cabang)
  static bool canShowAdminLoginCode({
    required String? tokoId,
    required String? jabatan,
  }) {
    final toko = (tokoId ?? '').trim().toUpperCase();
    final j = normalize(jabatan);
    if (j.isEmpty) return false;

    if (j == 'frontliner' || j == 'backliner') return false;

    if (toko == 'PUSAT') {
      return j == 'admin' || j == 'owner';
    }

    return j == 'kepala toko' || j == 'kepala area';
  }
}
