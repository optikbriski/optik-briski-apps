import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Garansi frame + lensa:
/// - Kartu dibuat saat jual (status menunggu_ambil)
/// - Aktif 7 hari sejak kasir scan barcode invoice + foto hasil (customer ambil)
/// - Klaim maksimal 1x per transaksi (sale)
class GaransiService {
  GaransiService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const int garansiHari = 7;
  static const String bucketFoto = 'garansi-photos';

  static bool isGaransiEligible(String? tipeProduk, String? namaProduk) {
    return jenisFromItem(tipeProduk, namaProduk) != null;
  }

  static String? jenisFromItem(String? tipeProduk, String? namaProduk) {
    final t = (tipeProduk ?? '').toLowerCase().trim();
    final n = (namaProduk ?? '').toLowerCase();
    if (t == 'frame' || t.contains('frame') || n.contains('frame')) {
      return 'frame';
    }
    if (t == 'lensa' ||
        t.contains('lensa') ||
        n.contains('lensa') ||
        n.contains('progresif')) {
      return 'lensa';
    }
    return null;
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Ringkas spek/fitur dari baris produk + nama item (untuk klaim ganti sesuai spek).
  static String buildSpesifikasi({
    String? namaProduk,
    String? tipeProduk,
    Map<String, dynamic>? product,
  }) {
    final parts = <String>[];
    final nama = (namaProduk ?? '').trim();
    if (nama.isNotEmpty) parts.add(nama);
    final tipe = (tipeProduk ?? '').trim();
    if (tipe.isNotEmpty) parts.add('Tipe: $tipe');
    if (product != null) {
      final jl = product['jenis_lensa']?.toString().trim();
      if (jl != null && jl.isNotEmpty) parts.add('Jenis lensa: $jl');
      final merk = product['merk']?.toString().trim();
      if (merk != null && merk.isNotEmpty) parts.add('Merk: $merk');
      final sku = product['sku']?.toString().trim();
      if (sku != null && sku.isNotEmpty) parts.add('SKU: $sku');
    }
    final joined = parts.join(' · ');
    final lower = joined.toLowerCase();
    final fitur = <String>[];
    if (lower.contains('anti') && lower.contains('baret')) {
      fitur.add('Anti-baret');
    } else if (lower.contains('anti baret') || lower.contains('antibaret')) {
      fitur.add('Anti-baret');
    }
    if (lower.contains('bluechromic') || lower.contains('blue chromic')) {
      fitur.add('Bluechromic (berubah warna)');
    }
    if (lower.contains('anti radiasi') || lower.contains('blueray') ||
        lower.contains('blue ray')) {
      fitur.add('Anti radiasi');
    }
    if (lower.contains('elastis')) fitur.add('Frame elastis');
    if (fitur.isEmpty) return joined;
    return '$joined · Fitur: ${fitur.join(', ')}';
  }

  /// Buat kartu menunggu ambil (belum jalan garansi).
  Future<int> createKartuFromSale(String saleId) async {
    final sale = await _db.from('sales').select().eq('id', saleId).single();
    final items =
        await _db.from('sales_items').select().eq('sale_id', saleId) as List;

    final tokoId = sale['toko_id']?.toString() ?? 'PUSAT';
    var created = 0;

    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final tipe = item['tipe_produk']?.toString();
      final nama = item['nama_produk']?.toString();
      final jenis = jenisFromItem(tipe, nama);
      if (jenis == null) continue;

      final saleItemId = item['id']?.toString();
      if (saleItemId == null || saleItemId.isEmpty) continue;

      Map<String, dynamic>? product;
      final pid = item['product_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        try {
          final p = await _db
              .from('products')
              .select('nama, jenis_lensa, merk, sku, kategori')
              .eq('id', pid)
              .maybeSingle();
          if (p != null) product = Map<String, dynamic>.from(p);
        } catch (_) {}
      }

      try {
        await _db.from('garansi_kartu').upsert(
          {
            'sale_id': saleId,
            'sale_item_id': saleItemId,
            'toko_id': tokoId,
            'no_invoice': sale['no_invoice'],
            'nama_pelanggan': sale['nama_pelanggan'],
            'no_wa': sale['no_wa'],
            'product_id': item['product_id'],
            'nama_produk': nama,
            'jenis_garansi': jenis,
            'resep_awal': item['detail_resep']?.toString(),
            'spesifikasi_produk': buildSpesifikasi(
              namaProduk: nama,
              tipeProduk: tipe,
              product: product,
            ),
            'tanggal_mulai': null,
            'tanggal_akhir': null,
            'status': 'menunggu_ambil',
            'klaim_digunakan': false,
          },
          onConflict: 'sale_item_id',
        );
        created++;
      } catch (_) {}
    }
    return created;
  }

  Future<int> generateFromInvoice(String noInvoice, {String? tokoId}) async {
    var q = _db.from('sales').select('id').eq('no_invoice', noInvoice);
    if (tokoId != null &&
        tokoId.isNotEmpty &&
        tokoId.toUpperCase() != 'PUSAT' &&
        tokoId.toUpperCase() != 'CABANG-PUSAT') {
      q = q.eq('toko_id', tokoId);
    }
    final sale = await q.maybeSingle();
    if (sale == null) throw 'Invoice tidak ditemukan.';
    return createKartuFromSale(sale['id'].toString());
  }

  Future<Map<String, dynamic>?> findSaleByInvoice(
    String noInvoice, {
    String? tokoId,
    bool isPusat = false,
  }) async {
    var q = _db.from('sales').select().eq('no_invoice', noInvoice.trim());
    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId);
    }
    final row = await q.maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<String> uploadFotoHasil({
    required String saleId,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    final path =
        'hasil/$saleId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage.from(bucketFoto).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );
    return _db.storage.from(bucketFoto).getPublicUrl(path);
  }

  Future<String> uploadFotoHasilFile({
    required String saleId,
    required File file,
  }) async {
    final bytes = await file.readAsBytes();
    final name = file.path.toLowerCase();
    final ext = name.endsWith('.png') ? 'png' : 'jpg';
    return uploadFotoHasil(saleId: saleId, bytes: bytes, ext: ext);
  }

  /// Kasir scan barcode invoice + foto hasil → customer sudah ambil, garansi 7 hari mulai.
  Future<Map<String, dynamic>> konfirmasiAmbil({
    required String noInvoice,
    required String fotoHasilUrl,
    String? tokoId,
    bool isPusat = false,
  }) async {
    final sale = await findSaleByInvoice(
      noInvoice,
      tokoId: tokoId,
      isPusat: isPusat,
    );
    if (sale == null) throw 'Invoice tidak ditemukan.';

    final statusBayar = sale['status_pembayaran']?.toString() ?? '';
    if (statusBayar.toLowerCase() != 'lunas') {
      throw 'Transaksi belum Lunas. Selesaikan pembayaran dulu.';
    }
    if (sale['diambil_at'] != null) {
      throw 'Barang sudah dikonfirmasi diambil sebelumnya.';
    }
    if (fotoHasilUrl.trim().isEmpty) {
      throw 'Foto hasil pengerjaan wajib diunggah sebagai bukti.';
    }

    // Pastikan ada kartu frame/lensa
    var n = await _db
        .from('garansi_kartu')
        .select('id')
        .eq('sale_id', sale['id']);
    if ((n as List).isEmpty) {
      await createKartuFromSale(sale['id'].toString());
    }

    final now = DateTime.now();
    final mulai = dateOnly(now);
    final akhir = mulai.add(const Duration(days: garansiHari));
    final uid = _db.auth.currentUser?.id;

    await _db.from('sales').update({
      'diambil_at': now.toUtc().toIso8601String(),
      'foto_hasil_url': fotoHasilUrl,
      'diambil_oleh': uid,
      'tracking_status': 'DIAMBIL',
    }).eq('id', sale['id']);

    await _db.from('garansi_kartu').update({
      'status': 'aktif',
      'tanggal_mulai': formatDate(mulai),
      'tanggal_akhir': formatDate(akhir),
      'diambil_at': now.toUtc().toIso8601String(),
      'foto_hasil_url': fotoHasilUrl,
    }).eq('sale_id', sale['id']).eq('status', 'menunggu_ambil');

    // Juga aktifkan yang mungkin masih null tanggal
    await _db
        .from('garansi_kartu')
        .update({
          'status': 'aktif',
          'tanggal_mulai': formatDate(mulai),
          'tanggal_akhir': formatDate(akhir),
          'diambil_at': now.toUtc().toIso8601String(),
          'foto_hasil_url': fotoHasilUrl,
        })
        .eq('sale_id', sale['id'])
        .isFilter('tanggal_mulai', null);

    return {
      'sale_id': sale['id'],
      'no_invoice': sale['no_invoice'],
      'tanggal_mulai': formatDate(mulai),
      'tanggal_akhir': formatDate(akhir),
      'garansi_hari': garansiHari,
    };
  }

  Future<List<Map<String, dynamic>>> searchKartu({
    required String query,
    String? tokoId,
    bool isPusat = false,
    int limit = 80,
  }) async {
    final q = query.trim();
    var req = _db.from('garansi_kartu').select();

    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      req = req.eq('toko_id', tokoId);
    }

    if (q.isNotEmpty) {
      final like = '%$q%';
      req = req.or(
        'no_invoice.ilike.$like,nama_pelanggan.ilike.$like,no_wa.ilike.$like,nama_produk.ilike.$like',
      );
    }

    final rows = await req.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listKlaim({
    String? tokoId,
    bool isPusat = false,
    int limit = 100,
  }) async {
    var req = _db.from('garansi_klaim').select(
          '*, garansi_kartu:kartu_id(id, no_invoice, nama_pelanggan, no_wa, '
          'nama_produk, jenis_garansi, tanggal_akhir, status, toko_id)',
        );

    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      req = req.eq('toko_id', tokoId);
    }

    final rows = await req.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> klaimForKartu(String kartuId) async {
    final rows = await _db
        .from('garansi_klaim')
        .select()
        .eq('kartu_id', kartuId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<Map<String, int>> statsPusat() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final menunggu = await _db
        .from('garansi_kartu')
        .select('id')
        .eq('status', 'menunggu_ambil');
    final aktif =
        await _db.from('garansi_kartu').select('id').eq('status', 'aktif');
    final klaimBulan = await _db
        .from('garansi_klaim')
        .select('id')
        .gte('created_at', monthStart.toUtc().toIso8601String());

    return {
      'menunggu_ambil': (menunggu as List).length,
      'kartu_aktif': (aktif as List).length,
      'klaim_bulan_ini': (klaimBulan as List).length,
    };
  }

  bool kartuBisaDiklaim(Map<String, dynamic> kartu) {
    final status = kartu['status']?.toString() ?? '';
    if (status != 'aktif') return false;
    if (kartu['klaim_digunakan'] == true) return false;
    final akhir = DateTime.tryParse(kartu['tanggal_akhir']?.toString() ?? '');
    if (akhir == null) return false;
    return !dateOnly(DateTime.now()).isAfter(akhir);
  }

  Future<bool> saleSudahPunyaKlaim(String saleId) async {
    final rows = await _db
        .from('garansi_klaim')
        .select('id')
        .eq('sale_id', saleId)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  /// Klaim 1x per transaksi.
  /// - Fitur gagal (anti-baret baret, bluechromic mati, frame elastis patah) → ganti spek sama
  /// - Kelalaian customer biasa (baret pada lensa non anti-baret) → tolak
  /// - Ukuran lensa: cocok beli + resep recheck harus beda
  Future<Map<String, dynamic>> ajukanDanPutuskan({
    required String kartuId,
    required String tokoId,
    required String alasan,
    required String keputusan,
    required String kategoriMasalah,
    String? catatan,
    String? fotoUrl,
    bool? ukuranSesuaiBeli,
    String? resepRecheck,
    bool? resepBerbeda,
    String? spesifikasiPengganti,
  }) async {
    final alasanTrim = alasan.trim();
    if (alasanTrim.isEmpty) throw 'Alasan klaim wajib diisi.';

    final kartu =
        await _db.from('garansi_kartu').select().eq('id', kartuId).single();
    final saleId = kartu['sale_id']?.toString();
    if (saleId == null) throw 'Kartu tidak terhubung ke transaksi.';

    if (!kartuBisaDiklaim(kartu)) {
      throw 'Garansi tidak aktif, sudah habis, belum diambil, atau klaim sudah dipakai.';
    }

    if (await saleSudahPunyaKlaim(saleId)) {
      throw 'Klaim garansi untuk transaksi ini sudah pernah dipakai (maksimal 1x).';
    }

    final jenis = kartu['jenis_garansi']?.toString() ?? '';
    final spekKartu = kartu['spesifikasi_produk']?.toString().trim() ?? '';
    var keputusanFinal = keputusan;
    var spekGanti = (spesifikasiPengganti ?? '').trim();

    // Fitur yang dijanjikan gagal → customer dapat barang baru spek sama
    if (kategoriMasalah == 'fitur_tidak_berfungsi') {
      if (keputusanFinal == 'ditolak') {
        throw 'Fitur produk yang dibeli gagal berfungsi — harus diganti barang baru sesuai spek, bukan ditolak.';
      }
      keputusanFinal = 'selesai_ganti';
      if (spekGanti.isEmpty) spekGanti = spekKartu;
      if (spekGanti.isEmpty) {
        throw 'Isi spesifikasi barang pengganti (sama dengan yang dibeli).';
      }
      if (catatan == null || catatan.trim().isEmpty) {
        throw 'Catatan wajib: sebutkan fitur yang gagal (anti-baret / bluechromic / elastis / dll).';
      }
    }

    // Kelalaian customer (bukan kegagalan fitur) tidak dijamin
    if (kategoriMasalah == 'kelalaian_customer') {
      if (keputusanFinal != 'ditolak') {
        throw 'Kelalaian customer (mis. baret pada lensa biasa) tidak dijamin — pilih Ditolak. '
            'Jika yang gagal adalah fitur anti-baret/bluechromic/elastis, pilih kategori Fitur tidak berfungsi.';
      }
      if (catatan == null || catatan.trim().isEmpty) {
        throw 'Catatan wajib untuk penolakan kelalaian customer.';
      }
    }

    if (keputusanFinal == 'ditolak' &&
        (catatan == null || catatan.trim().isEmpty)) {
      throw 'Catatan wajib diisi jika klaim ditolak.';
    }

    // Aturan lensa: kenyamanan/ukuran
    if (jenis == 'lensa' && kategoriMasalah == 'ukuran_lensa') {
      if (ukuranSesuaiBeli != true) {
        throw 'Untuk klaim ukuran lensa: pastikan ukuran fisik sesuai yang dibeli dulu.';
      }
      if (resepRecheck == null || resepRecheck.trim().isEmpty) {
        throw 'Hasil cek mata ulang (resep recheck) wajib diisi.';
      }
      if (resepBerbeda != true) {
        throw 'Hasil cek mata harus berbeda dari resep awal. Jika sama, klaim tidak valid.';
      }
    }

    // Cacat pabrik / ganti → catat spek pengganti
    if (keputusanFinal == 'selesai_ganti' && spekGanti.isEmpty) {
      spekGanti = spekKartu.isNotEmpty
          ? spekKartu
          : (kartu['nama_produk']?.toString() ?? '');
    }

    final uid = _db.auth.currentUser?.id;
    final row = await _db
        .from('garansi_klaim')
        .insert({
          'kartu_id': kartuId,
          'sale_id': saleId,
          'toko_id': tokoId,
          'diajukan_oleh': uid,
          'alasan': alasanTrim,
          'catatan': catatan?.trim(),
          'foto_url': fotoUrl,
          'keputusan': keputusanFinal,
          'kategori_masalah': kategoriMasalah,
          'ukuran_sesuai_beli': ukuranSesuaiBeli,
          'resep_awal': kartu['resep_awal'],
          'resep_recheck': resepRecheck?.trim(),
          'resep_berbeda': resepBerbeda,
          'spesifikasi_pengganti':
              spekGanti.isEmpty ? null : spekGanti,
          'diputuskan_oleh': uid,
          'diputuskan_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();

    // Tandai semua kartu transaksi: klaim sudah dipakai
    await _db
        .from('garansi_kartu')
        .update({'klaim_digunakan': true, 'status': 'diklaim'}).eq(
            'sale_id', saleId);

    if (keputusan == 'ditolak') {
      // Tetap tandai klaim dipakai, tapi kartu bisa ditandai diklaim/habis
      final akhir = DateTime.tryParse(kartu['tanggal_akhir']?.toString() ?? '');
      final statusAkhir = (akhir != null &&
              dateOnly(DateTime.now()).isAfter(akhir))
          ? 'habis'
          : 'diklaim';
      await _db
          .from('garansi_kartu')
          .update({'status': statusAkhir, 'klaim_digunakan': true}).eq(
              'sale_id', saleId);
    }

    return Map<String, dynamic>.from(row);
  }

  static int sisaHari(Map<String, dynamic> kartu) {
    final status = kartu['status']?.toString() ?? '';
    if (status == 'menunggu_ambil') return -999; // sentinel: belum mulai
    final akhir = DateTime.tryParse(kartu['tanggal_akhir']?.toString() ?? '');
    if (akhir == null) return 0;
    return dateOnly(akhir).difference(dateOnly(DateTime.now())).inDays;
  }

  static String statusLabel(Map<String, dynamic> kartu) {
    final s = kartu['status']?.toString() ?? '-';
    if (s == 'menunggu_ambil') return 'Menunggu ambil';
    if (s == 'aktif') {
      final sisa = sisaHari(kartu);
      return sisa >= 0 ? 'Aktif ($sisa hari lagi)' : 'Habis';
    }
    return s;
  }
}
