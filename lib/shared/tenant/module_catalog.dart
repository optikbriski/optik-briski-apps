/// Modul etalase Rekasa. [key]/[label] dipakai admin tenant; sisanya untuk toko.
class StoreModuleDef {
  const StoreModuleDef({
    required this.key,
    required this.label,
    required this.summary,
    required this.body,
    this.videoUrl,
    this.addOnPriceIdr = 50000,
  });

  final String key;
  final String label;
  final String summary;
  final String body;
  final String? videoUrl;
  final int addOnPriceIdr;
}

/// Fallback jika migrasi 000009 belum di-apply.
const moduleCatalog = <StoreModuleDef>[
  StoreModuleDef(
    key: 'pos',
    label: 'POS / Kasir',
    summary: 'Nota cepat, DP, struk, dan antrian toko.',
    body:
        'Kasir untuk penjualan harian: pilih barang, hitung uang, cetak/kirim struk, '
        'catat DP, dan simpan nota per toko. Data sekat per usaha — bukan cabang Optik.',
    addOnPriceIdr: 50000,
  ),
  StoreModuleDef(
    key: 'master_data',
    label: 'Master data barang',
    summary: 'SKU, harga, stok awal, dan katalog toko.',
    body:
        'Pusat data barang: kode, nama, harga, foto, dan stok per toko. '
        'Jadi sumber kasir, member, dan pesanan online. Ganti paket tidak menghapus barang lama.',
    addOnPriceIdr: 50000,
  ),
  StoreModuleDef(
    key: 'member_app',
    label: 'Aplikasi Member',
    summary: 'Pelanggan lihat pesanan, poin, dan garansi.',
    body:
        'Aplikasi/web member: daftar, login, lihat status nota, klaim garansi, dan promo. '
        'Di paket C/B member pakai kulit Rekasa + kode usaha. Paket A bisa merek sendiri.',
    addOnPriceIdr: 75000,
  ),
  StoreModuleDef(
    key: 'history_dp',
    label: 'Riwayat DP / nota',
    summary: 'Lacak uang muka dan sisa tagihan pelanggan toko.',
    body:
        'Daftar DP dan pelunasan per nota. Bukan tagihan Rekasa ke UMKM — ini piutang toko ke pelanggan.',
    addOnPriceIdr: 40000,
  ),
  StoreModuleDef(
    key: 'logistics',
    label: 'Logistik / stok antar toko',
    summary: 'Pindah barang pusat ↔ cabang, stok real.',
    body:
        'Mutasi stok antar toko dalam satu usaha. Pusat dan cabang punya kode sendiri di dalam tenant, '
        'bukan CABANG milik merek lain.',
    addOnPriceIdr: 60000,
  ),
  StoreModuleDef(
    key: 'warranty',
    label: 'Garansi',
    summary: 'Klaim garansi frame/lensa dengan batas waktu.',
    body:
        'Syarat garansi, klaim, dan status ambil. Member bisa ajukan dari aplikasinya.',
    addOnPriceIdr: 50000,
  ),
  StoreModuleDef(
    key: 'attendance',
    label: 'Absensi & geofence',
    summary: 'Hadir di lokasi toko, jadwal, dan pantauan.',
    body:
        'Absen masuk/keluar dengan batas lokasi toko, jadwal kerja, dan monitor admin.',
    addOnPriceIdr: 60000,
  ),
  StoreModuleDef(
    key: 'finance',
    label: 'Keuangan / buku besar',
    summary: 'Jurnal, periode, dan laporan owner.',
    body:
        'Buku besar, periode fiskal, dan laporan untuk owner. Tidak mencampur uang antar merek.',
    addOnPriceIdr: 80000,
  ),
  StoreModuleDef(
    key: 'online_orders',
    label: 'Pesanan online',
    summary: 'Order dari member, ongkir, dan pengiriman.',
    body:
        'Keranjang member, checkout, hold stok, dan status kirim. '
        'Bukan marketplace Rekasa — ini toko Anda yang jualan ke pelanggan.',
    addOnPriceIdr: 80000,
  ),
];

String moduleLabel(String key) {
  for (final m in moduleCatalog) {
    if (m.key == key) return m.label;
  }
  return key;
}
