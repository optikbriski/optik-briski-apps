/// ID toko: `PUSAT` hanya milik tenant Optik. UMKM lain memakai `{kode}-PUSAT`.
class TokoIds {
  TokoIds._();

  static const optikPusat = 'PUSAT';
  static const optikCabangPusat = 'CABANG-PUSAT';

  static bool isPusat(String? raw, {String? tenantPusatTokoId}) {
    final id = (raw ?? '').trim().toUpperCase();
    if (id.isEmpty) return false;
    final bound = (tenantPusatTokoId ?? '').trim().toUpperCase();
    if (bound.isNotEmpty && id == bound) return true;
    if (id == optikPusat || id == optikCabangPusat) return true;
    return id.endsWith('-PUSAT');
  }
}
