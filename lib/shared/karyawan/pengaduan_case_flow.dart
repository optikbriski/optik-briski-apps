/// Aturan form + keputusan pengaduan (karyawan / admin → pusat).
/// Status: OPEN → IN_PROGRESS → DONE (approve, hijau) | REJECTED (reject, merah).
class PengaduanItemLine {
  const PengaduanItemLine({
    required this.sku,
    required this.nama,
    required this.qty,
    this.barcode,
  });

  final String sku;
  final String nama;
  final int qty;
  final String? barcode;

  PengaduanItemLine copyWith({int? qty}) => PengaduanItemLine(
        sku: sku,
        nama: nama,
        qty: qty ?? this.qty,
        barcode: barcode,
      );

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'nama': nama,
        'qty': qty,
        if ((barcode ?? '').trim().isNotEmpty) 'barcode': barcode!.trim(),
      };

  static PengaduanItemLine? tryParse(Map<dynamic, dynamic> raw) {
    final sku = (raw['sku'] ?? raw['barcode'] ?? '').toString().trim();
    if (sku.isEmpty) return null;
    final qty = _qtyOf(raw['qty'] ?? raw['jumlah']);
    if (qty <= 0) return null;
    final nama = (raw['nama'] ?? raw['name'] ?? sku).toString().trim();
    final barcode = (raw['barcode'] ?? '').toString().trim();
    return PengaduanItemLine(
      sku: sku,
      nama: nama.isEmpty ? sku : nama,
      qty: qty,
      barcode: barcode.isEmpty ? null : barcode,
    );
  }

  static int _qtyOf(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString().trim()) ??
        double.tryParse(raw.toString().trim())?.round() ??
        0;
  }
}

abstract final class PengaduanCaseFlow {
  static const kategoriKodes = <String>[
    'PRODUK',
    'TOKO',
    'CUSTOMER',
    'PARTNER',
    'SISTEM',
    'PELANGGARAN',
  ];

  /// Admin: bukan laporan partner / karyawan lain (itu privat APK Karyawan).
  static const kategoriKodesPublik = <String>[
    'PRODUK',
    'TOKO',
    'CUSTOMER',
    'SISTEM',
  ];

  static const staffPrivateKodes = <String>['PARTNER', 'PELANGGARAN'];

  static const sumberKaryawan = 'KARYAWAN';
  static const sumberAdmin = 'ADMIN';
  static const sumberMember = 'MEMBER';

  static const stokBuang = 'BUANG';
  static const stokBalik = 'BALIK';

  static bool canOpenCase(String status) {
    final s = status.trim().toUpperCase();
    return s.isEmpty || s == 'OPEN';
  }

  static bool isClosed(String status) {
    final s = status.trim().toUpperCase();
    return s == 'DONE' || s == 'REJECTED';
  }

  static bool isProduk(String? kode) =>
      (kode ?? '').trim().toUpperCase() == 'PRODUK';

  static bool isStaffPrivate(String? kode) =>
      staffPrivateKodes.contains((kode ?? '').trim().toUpperCase());

  static bool isAdminSumber(Map<String, dynamic> row) {
    final s = (row['sumber'] ?? '').toString().trim().toUpperCase();
    if (s == sumberAdmin) return true;
    if (s == sumberKaryawan || s == sumberMember) return false;
    final uid = (row['pelapor_user_id'] ?? '').toString().trim();
    final kid = (row['karyawan_id'] ?? '').toString().trim();
    return uid.isNotEmpty && kid.isEmpty;
  }

  static bool isNonKaryawanSumber(Map<String, dynamic> row) {
    final s = (row['sumber'] ?? '').toString().trim().toUpperCase();
    if (s == sumberAdmin || s == sumberMember) return true;
    return isAdminSumber(row);
  }

  static String sumberLabelKey(Map<String, dynamic> row) {
    final s = (row['sumber'] ?? '').toString().trim().toUpperCase();
    if (s == sumberAdmin || isAdminSumber(row)) {
      return 'pengaduan_admin_sumber_admin';
    }
    if (s == sumberMember) return 'pengaduan_admin_sumber_member';
    return 'pengaduan_admin_sumber';
  }

  static String pelaporNama(Map<String, dynamic> row) {
    final pelapor = (row['pelapor_nama'] ?? '').toString().trim();
    if (pelapor.isNotEmpty) return pelapor;
    final kary = row['karyawan'];
    if (kary is Map) {
      final n = (kary['nama'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
    }
    if (isAdminSumber(row)) return 'Admin';
    return '-';
  }

  static String pelaporKontak(Map<String, dynamic> row) {
    if (isNonKaryawanSumber(row)) {
      return (row['pelapor_kontak'] ?? '').toString().trim();
    }
    final kary = row['karyawan'];
    if (kary is Map) return (kary['nik'] ?? '').toString().trim();
    return '';
  }

  static String labelKey(String kode) {
    switch (kode.trim().toUpperCase()) {
      case 'PRODUK':
        return 'pengaduan_kat_produk';
      case 'TOKO':
        return 'pengaduan_kat_toko';
      case 'CUSTOMER':
        return 'pengaduan_kat_customer';
      case 'PARTNER':
        return 'pengaduan_kat_partner';
      case 'SISTEM':
        return 'pengaduan_kat_sistem';
      case 'PELANGGARAN':
        return 'pengaduan_kat_pelanggaran';
      default:
        return 'pengaduan_kat_lainnya';
    }
  }

  static String tapKey(String status) {
    switch (status.trim().toUpperCase()) {
      case 'IN_PROGRESS':
        return 'pengaduan_admin_tap_tindakan';
      case 'DONE':
      case 'REJECTED':
        return 'pengaduan_admin_tap_lihat';
      default:
        return 'pengaduan_admin_tap_pilih';
    }
  }

  static String kategoriKodeOf(Map<String, dynamic> row) {
    final kode = (row['kategori_kode'] ?? '').toString().trim().toUpperCase();
    if (kode.isNotEmpty) return kode;
    return inferKode((row['kategori'] ?? '').toString());
  }

  static String inferKode(String kategori) {
    final k = kategori.toLowerCase();
    if (k.contains('stok') ||
        k.contains('produk') ||
        k.contains('stock') ||
        k.contains('barang')) {
      return 'PRODUK';
    }
    if (k.contains('customer') ||
        k.contains('pelanggan') ||
        k.contains('member')) {
      return 'CUSTOMER';
    }
    if (k.contains('partner') || k.contains('mitra')) return 'PARTNER';
    if (k.contains('sistem') ||
        k.contains('aplikasi') ||
        k.contains('system') ||
        k.contains('app')) {
      return 'SISTEM';
    }
    if (k.contains('langgar') ||
        k.contains('violation') ||
        k.contains('rahasia')) {
      return 'PELANGGARAN';
    }
    if (k.contains('alat') ||
        k.contains('toko') ||
        k.contains('store') ||
        k.contains('equipment')) {
      return 'TOKO';
    }
    return '';
  }

  static List<PengaduanItemLine> parseItems(Object? raw) {
    if (raw is! List) return const [];
    final out = <PengaduanItemLine>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final line = PengaduanItemLine.tryParse(e);
      if (line != null) out.add(line);
    }
    return out;
  }

  /// Null = form siap dikirim.
  static String? submitBlocker({
    required String? kategoriKode,
    required String detail,
    required bool hasFoto,
    required List<PengaduanItemLine> items,
    List<String>? allowedKodes,
  }) {
    final kode = (kategoriKode ?? '').trim().toUpperCase();
    if (kode.isEmpty) return 'pengaduan_err_kategori';
    if (allowedKodes != null && !allowedKodes.contains(kode)) {
      return 'pengaduan_err_kategori_privat';
    }
    if (detail.trim().isEmpty) return 'pengaduan_err_penjelasan';
    if (!hasFoto) return 'pengaduan_err_foto';
    if (isProduk(kode)) {
      if (items.isEmpty) return 'pengaduan_err_barang';
      if (items.any((e) => e.qty <= 0 || e.sku.trim().isEmpty)) {
        return 'pengaduan_err_barang_qty';
      }
    }
    return null;
  }

  static bool canSubmit({
    required String? kategoriKode,
    required String detail,
    required bool hasFoto,
    required List<PengaduanItemLine> items,
    List<String>? allowedKodes,
  }) =>
      submitBlocker(
        kategoriKode: kategoriKode,
        detail: detail,
        hasFoto: hasFoto,
        items: items,
        allowedKodes: allowedKodes,
      ) ==
      null;

  /// Null = keputusan siap dikonfirmasi.
  static String? decideBlocker({
    required bool approve,
    required String alasan,
    required String kategoriKode,
    required String? stokTindakan,
    required bool tokoPusat,
  }) {
    if (alasan.trim().isEmpty) return 'pengaduan_admin_close_need_reply';
    if (!approve) return null;
    if (!isProduk(kategoriKode)) return null;
    final stok = (stokTindakan ?? '').trim().toUpperCase();
    if (stok != stokBuang && stok != stokBalik) {
      return 'pengaduan_admin_err_stok_tindakan';
    }
    if (stok == stokBalik && tokoPusat) {
      return 'pengaduan_admin_err_stok_balik_pusat';
    }
    return null;
  }

  /// PRODUK + approve harus lewat decide_pengaduan (write-off / retur).
  /// Jangan fallback ke reply_pengaduan — stok akan tidak tercatat.
  static bool canFallbackReplyForDecide({
    required bool approve,
    required String kategoriKode,
  }) {
    if (!approve) return true;
    return !isProduk(kategoriKode);
  }
}
