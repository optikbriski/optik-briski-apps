import 'module_catalog.dart';

/// Bidang usaha (paket industri, pola Odoo). Satu codebase, spesifikasi beda.
class StoreIndustryDef {
  const StoreIndustryDef({
    required this.key,
    required this.label,
    required this.blurb,
    required this.planModules,
    required this.copy,
  });

  final String key;
  final String label;
  final String blurb;

  /// Modul yang termasuk tiap paket (C/B/A). Lainnya = add-on jika ada di [copy].
  final Map<String, List<String>> planModules;

  /// Label + penjelasan per modul untuk bidang ini. Key tidak ada = disembunyikan.
  final Map<String, StoreModuleDef> copy;

  List<String> get allowedKeys => copy.keys.toList();

  List<String> modulesFor(String planKey) =>
      List<String>.from(planModules[planKey] ?? const []);
}

/// Fallback etalase per bidang. SQL 000010 menimpa jika sudah di-apply.
final industryCatalog = <StoreIndustryDef>[
  StoreIndustryDef(
    key: 'optik',
    label: 'Optik / kacamata',
    blurb: 'Kasir frame-lensa, resep, garansi, member.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'member_app'],
      'paket_b': [
        'pos',
        'master_data',
        'member_app',
        'logistics',
        'warranty',
        'attendance',
        'history_dp',
      ],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'logistics',
        'warranty',
        'attendance',
        'history_dp',
        'finance',
        'online_orders',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'POS / Kasir optik',
        summary: 'Nota frame, lensa, DP, dan struk.',
        body:
            'Kasir khusus alur optik: barang + jasa, DP, sisa, struk. Data sekat per usaha — bukan cabang merek lain.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Master frame & lensa',
        summary: 'SKU, harga, stok per toko.',
        body: 'Katalog frame, lensa, aksesoris. Sumber kasir, member, dan order online.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi member optik',
        summary: 'Pelanggan lihat nota, resep, garansi.',
        body: 'Member login, status pesanan, klaim garansi. Paket A bisa merek sendiri.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'Riwayat DP / nota',
        summary: 'Uang muka frame/lensa.',
        body: 'Piutang toko ke pelanggan, bukan tagihan Rekasa.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar cabang',
        summary: 'Pindah barang pusat ↔ cabang.',
        body: 'Mutasi stok dalam satu usaha optik.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi frame/lensa',
        summary: 'Klaim dengan batas waktu.',
        body: 'Syarat garansi optik dan status ambil dari app member.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi toko',
        summary: 'Hadir di lokasi cabang.',
        body: 'Geofence, jadwal, monitor admin.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan / buku besar',
        summary: 'Jurnal dan laporan owner.',
        body: 'Laporan per usaha. Tidak campur uang merek lain.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Pesanan online',
        summary: 'Order member + ongkir.',
        body: 'Keranjang dan hold stok untuk toko ini, bukan marketplace Rekasa.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'retail',
    label: 'Toko retail / fashion',
    blurb: 'Kasir barang, stok cabang, member, jualan online. Bukan wajib optik.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'member_app'],
      'paket_b': [
        'pos',
        'master_data',
        'member_app',
        'logistics',
        'history_dp',
        'attendance',
      ],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'logistics',
        'history_dp',
        'attendance',
        'finance',
        'online_orders',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir toko',
        summary: 'Scan, struk, tunai/non-tunai.',
        body: 'Kasir retail umum. Bisa dipakai fashion, kelontong, aksesoris — bukan hanya kacamata.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Master barang',
        summary: 'SKU, harga, stok etalase.',
        body: 'Katalog produk toko. Ganti paket tidak menghapus barang.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi pelanggan',
        summary: 'Poin, riwayat belanja, promo.',
        body: 'Pelanggan toko, bukan pasien optik. Paket A = merek sendiri.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'DP / indent',
        summary: 'Pesan barang dengan uang muka.',
        body: 'Cocok pre-order atau barang indent.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar toko',
        summary: 'Transfer gudang ↔ cabang.',
        body: 'Satu usaha, banyak titik. Bukan cabang merek lain.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi barang',
        summary: 'Klaim retur / garansi toko.',
        body: 'Add-on jika produk Anda bergaransi. Boleh dimatikan.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi staff',
        summary: 'Hadir di lokasi toko.',
        body: 'Geofence dan jadwal per cabang.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan',
        summary: 'Buku besar toko.',
        body: 'Laporan owner per usaha.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Order online',
        summary: 'Pesan antar / ambil di toko.',
        body: 'Kanal jualan toko Anda, bukan marketplace Rekasa.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'fnb',
    label: 'Kafe / resto / F&B',
    blurb: 'Kasir menu, stok bahan antar outlet, pelanggan. Bukan POS kacamata.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'member_app'],
      'paket_b': [
        'pos',
        'master_data',
        'member_app',
        'attendance',
        'history_dp',
        'logistics',
      ],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'attendance',
        'history_dp',
        'logistics',
        'finance',
        'online_orders',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir / meja',
        summary: 'Pesanan, bayar, struk.',
        body: 'Mesin kasir F&B. Menu dan pembayaran. Bukan alur resep kacamata.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Menu & bahan',
        summary: 'Daftar menu, harga, stok.',
        body: 'Item jualan kafe/resto. Nanti bisa ditambah resep dapur — intinya katalog milik usaha ini.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Pelanggan / loyalty',
        summary: 'Poin dan riwayat pesan.',
        body: 'Aplikasi pelanggan resto, bukan member optik.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'Reservasi / DP acara',
        summary: 'Uang muka catering atau booking.',
        body: 'DP meja/acara, bukan DP frame.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar outlet',
        summary: 'Pindah bahan pusat ↔ cabang.',
        body: 'Satu merek F&B, banyak outlet.',
        addOnPriceIdr: 60000,
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi kru',
        summary: 'Hadir di outlet.',
        body: 'Shift dan lokasi cabang.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan outlet',
        summary: 'Laporan omzet dan buku besar.',
        body: 'Per usaha F&B, tidak campur merek lain.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Pesan antar / pickup',
        summary: 'Order dari app pelanggan.',
        body: 'Kanal milik resto Anda.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'jasa',
    label: 'Jasa (salon, laundry, studio)',
    blurb: 'Transaksi layanan, daftar jasa, klien, DP booking. Boleh tanpa stok barang.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'member_app'],
      'paket_b': ['pos', 'master_data', 'member_app', 'history_dp', 'attendance'],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'history_dp',
        'attendance',
        'finance',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Transaksi jasa',
        summary: 'Catat layanan dan bayar.',
        body: 'Kasir untuk jasa, bukan wajib barang fisik.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Daftar layanan',
        summary: 'Jenis jasa dan harga.',
        body: 'Paket treatment, cuci, sewa studio, dll.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi klien',
        summary: 'Riwayat treatment / order.',
        body: 'Klien jasa, bukan member optik.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'DP / booking',
        summary: 'Uang muka janji temu.',
        body: 'Reservasi salon, laundry kiloan berlangganan, sewa jam.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok cabang (opsional)',
        summary: 'Kalau Anda juga jual produk.',
        body: 'Add-on. Banyak usaha jasa tidak butuh ini.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi layanan',
        summary: 'Klaim hasil kerja.',
        body: 'Add-on. Misal retouch atau garansi cuci.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi kru',
        summary: 'Hadir di lokasi.',
        body: 'Geofence studio/salon.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan',
        summary: 'Laporan omzet jasa.',
        body: 'Buku besar per usaha.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Booking online',
        summary: 'Pesan layanan dari app.',
        body: 'Add-on kanal klien.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'bengkel',
    label: 'Bengkel / otomotif',
    blurb: 'Kasir servis, sparepart, DP, garansi pengerjaan, stok antar bengkel.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'history_dp'],
      'paket_b': [
        'pos',
        'master_data',
        'history_dp',
        'warranty',
        'attendance',
        'logistics',
      ],
      'paket_a': [
        'pos',
        'master_data',
        'history_dp',
        'warranty',
        'attendance',
        'logistics',
        'member_app',
        'finance',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir servis',
        summary: 'Work order + sparepart + bayar.',
        body: 'Transaksi bengkel, bukan kasir kacamata.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Sparepart & jasa',
        summary: 'Part, oli, jasa servis.',
        body: 'Katalog bengkel per usaha.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi pelanggan',
        summary: 'Riwayat servis kendaraan.',
        body: 'Pelanggan bengkel. Add-on di paket bawah.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'DP pengerjaan',
        summary: 'Uang muka servis / part indent.',
        body: 'Sisa tagihan pelanggan bengkel.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar bengkel',
        summary: 'Pindah part cabang.',
        body: 'Satu pemilik, banyak workshop.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi servis',
        summary: 'Klaim pengerjaan / part.',
        body: 'Bukan garansi frame optik — garansi kerja bengkel.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi mekanik',
        summary: 'Hadir di workshop.',
        body: 'Lokasi dan shift.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan bengkel',
        summary: 'Omzet servis dan part.',
        body: 'Laporan owner.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Booking servis online',
        summary: 'Janji temu dari app.',
        body: 'Add-on.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'klinik',
    label: 'Klinik / praktik',
    blurb: 'Kasir tindakan, daftar layanan, rekam klien, DP. Bukan rumah sakit penuh.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'member_app'],
      'paket_b': ['pos', 'master_data', 'member_app', 'history_dp', 'attendance'],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'history_dp',
        'attendance',
        'finance',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir klinik',
        summary: 'Bayar tindakan / produk.',
        body: 'Pembayaran praktik. Bukan EMR rumah sakit — spesifikasi ringan.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Layanan & item',
        summary: 'Tindakan, obat/item jual.',
        body: 'Daftar layanan klinik atau estetik.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi klien',
        summary: 'Riwayat kunjungan (ringan).',
        body: 'Klien/praktik, bukan member optik. Bukan rekam medis lengkap.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'DP tindakan',
        summary: 'Paket treatment berjangka.',
        body: 'Uang muka paket klinik.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar cabang',
        summary: 'Item antar klinik.',
        body: 'Add-on jika multi cabang.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi tindakan',
        summary: 'Follow-up paket.',
        body: 'Add-on, bukan garansi frame.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi staf',
        summary: 'Hadir di lokasi praktik.',
        body: 'Geofence cabang.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan praktik',
        summary: 'Laporan omzet.',
        body: 'Per badan usaha klinik.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Janji temu online',
        summary: 'Booking dari app klien.',
        body: 'Add-on.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'grosir',
    label: 'Grosir / distributor',
    blurb: 'Kasir partai, stok gudang antar titik, piutang, keuangan. Fokus barang, bukan etalase optik.',
    planModules: {
      'paket_c': ['pos', 'master_data', 'logistics'],
      'paket_b': [
        'pos',
        'master_data',
        'logistics',
        'history_dp',
        'attendance',
        'finance',
      ],
      'paket_a': [
        'pos',
        'master_data',
        'logistics',
        'history_dp',
        'attendance',
        'finance',
        'member_app',
        'online_orders',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir / nota grosir',
        summary: 'Jual partai, nota tempo.',
        body: 'Transaksi distributor. Bukan kasir ecer kacamata.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Master SKU gudang',
        summary: 'Barang, satuan, harga partai.',
        body: 'Katalog grosir per usaha.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Portal pelanggan toko',
        summary: 'Langganan melihat nota.',
        body: 'Add-on untuk toko langganan Anda.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'Piutang / tempo',
        summary: 'Sisa tagihan pembeli.',
        body: 'Bukan DP frame — piutang grosir.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Mutasi gudang',
        summary: 'Pindah stok antar titik.',
        body: 'Inti paket grosir.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Retur / klaim',
        summary: 'Barang rusak / salah kirim.',
        body: 'Add-on.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi gudang',
        summary: 'Hadir di titik stok.',
        body: 'Lokasi gudang/depo.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan distributor',
        summary: 'Buku besar dan periode.',
        body: 'Di paket B ke atas.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Order dari toko langganan',
        summary: 'Pesan restock.',
        body: 'Add-on kanal B2B ringan.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
  StoreIndustryDef(
    key: 'umum',
    label: 'Usaha umum',
    blurb: 'Belum masuk kategori di atas. Paket tipis, fitur dinyalakan sesuai kebutuhan.',
    planModules: {
      'paket_c': ['pos', 'master_data'],
      'paket_b': ['pos', 'master_data', 'member_app', 'attendance', 'history_dp'],
      'paket_a': [
        'pos',
        'master_data',
        'member_app',
        'attendance',
        'history_dp',
        'finance',
        'logistics',
        'online_orders',
      ],
    },
    copy: {
      'pos': StoreModuleDef(
        key: 'pos',
        label: 'Kasir / transaksi',
        summary: 'Catat jual-beli harian.',
        body: 'Mesin transaksi generik. Nyalakan modul lain sesuai bidang Anda.',
      ),
      'master_data': StoreModuleDef(
        key: 'master_data',
        label: 'Master item',
        summary: 'Barang atau jasa.',
        body: 'Katalog milik usaha ini.',
      ),
      'member_app': StoreModuleDef(
        key: 'member_app',
        label: 'Aplikasi pelanggan',
        summary: 'Akun klien / member.',
        body: 'Opsional.',
        addOnPriceIdr: 75000,
      ),
      'history_dp': StoreModuleDef(
        key: 'history_dp',
        label: 'DP / piutang',
        summary: 'Sisa bayar pelanggan.',
        body: 'Opsional.',
        addOnPriceIdr: 40000,
      ),
      'logistics': StoreModuleDef(
        key: 'logistics',
        label: 'Stok antar lokasi',
        summary: 'Kalau punya lebih dari satu titik.',
        body: 'Opsional.',
        addOnPriceIdr: 60000,
      ),
      'warranty': StoreModuleDef(
        key: 'warranty',
        label: 'Garansi / klaim',
        summary: 'Jika produk/jasa bergaransi.',
        body: 'Add-on.',
      ),
      'attendance': StoreModuleDef(
        key: 'attendance',
        label: 'Absensi',
        summary: 'Hadir staf.',
        body: 'Opsional.',
        addOnPriceIdr: 60000,
      ),
      'finance': StoreModuleDef(
        key: 'finance',
        label: 'Keuangan',
        summary: 'Buku besar.',
        body: 'Paket atas.',
        addOnPriceIdr: 80000,
      ),
      'online_orders': StoreModuleDef(
        key: 'online_orders',
        label: 'Order online',
        summary: 'Kanal pelanggan.',
        body: 'Add-on.',
        addOnPriceIdr: 80000,
      ),
    },
  ),
];

StoreIndustryDef? industryByKey(String? key) {
  final k = (key ?? '').trim().toLowerCase();
  if (k.isEmpty) return null;
  for (final i in industryCatalog) {
    if (i.key == k) return i;
  }
  return null;
}
