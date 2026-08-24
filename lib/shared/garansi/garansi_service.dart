import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/sale_fulfillment_service.dart';
import '../tenant/tenant_service.dart';
import 'garansi_rules.dart';

/// Garansi frame + lensa:
/// - Kartu dibuat saat jual (status menunggu_ambil) — belum bisa klaim
/// - Clock mulai hari kalender **Asia/Jakarta** saat diambil (scan + foto)
/// - Window klaim: hari 0 … hari 7 inklusif (`tanggal_akhir = mulai + 7`)
/// - Hari ke-8+ → mati / tidak bisa klaim
/// - Klaim maksimal 1x per transaksi (sale)
class GaransiService {
  GaransiService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const int garansiHari = 7;
  static const String bucketFoto = 'garansi-photos';

  /// Offset tetap WIB (UTC+7). Sama sumber kebenaran dengan RPC SQL.
  static const Duration jakartaOffset = Duration(hours: 7);

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

  /// Hari kalender Asia/Jakarta dari [now] (default: wall clock saat ini).
  static DateTime jakartaDateOnly([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final jkt = utc.add(jakartaOffset);
    return DateTime(jkt.year, jkt.month, jkt.day);
  }

  /// Parse kolom `date` / instant ke hari kalender.
  /// - `YYYY-MM-DD` murni → komponen tanggal apa adanya (kolom `date`)
  /// - Instant / ISO bermuatan waktu → hari kalender Asia/Jakarta
  static DateTime? parseDateOnly(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) {
      final jkt = raw.toUtc().add(jakartaOffset);
      return DateTime(jkt.year, jkt.month, jkt.day);
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final pureDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (pureDate != null) {
      final y = int.tryParse(pureDate.group(1)!);
      final mo = int.tryParse(pureDate.group(2)!);
      final d = int.tryParse(pureDate.group(3)!);
      if (y == null || mo == null || d == null) return null;
      return DateTime(y, mo, d);
    }
    final dt = DateTime.tryParse(s);
    if (dt == null) return null;
    final jkt = dt.toUtc().add(jakartaOffset);
    return DateTime(jkt.year, jkt.month, jkt.day);
  }

  /// Akhir window inklusif: hari diambil + [garansiHari] (hari ke-7 masih aktif).
  static DateTime tanggalAkhirDariMulai(DateTime mulai) =>
      dateOnly(mulai).add(const Duration(days: garansiHari));

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

    final tokoId = GaransiRules.requireTokoId(sale['toko_id']);
    final tenantId = TenantService.instance.id;
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
            if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
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
    final tenantId = TenantService.instance.id;
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    if (tokoId != null &&
        tokoId.isNotEmpty &&
        !GaransiRules.isPusatToko(tokoId)) {
      q = q.inFilter('toko_id', GaransiRules.storeAliases(tokoId));
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
    final tenantId = TenantService.instance.id;
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      q = q.inFilter('toko_id', GaransiRules.storeAliases(tokoId));
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

  static bool isSaleLunas(Map<String, dynamic> sale) =>
      GaransiRules.isSaleLunas(sale);

  /// Legacy / dan halaman Garansi: serah terima item READY + sync line DIAMBIL.
  Future<Map<String, dynamic>> konfirmasiAmbil({
    required String noInvoice,
    String? fotoHasilUrl,
    String? tokoId,
    bool isPusat = false,
  }) async {
    final sale = await findSaleByInvoice(
      noInvoice,
      tokoId: tokoId,
      isPusat: isPusat,
    );
    if (sale == null) throw 'Invoice tidak ditemukan.';

    // Sinkron partial fulfillment: tandai line READY → DIAMBIL dulu.
    final fulfill = SaleFulfillmentService(client: _db);
    final lines = await fulfill.listItems(sale['id'].toString());
    final c = SaleFulfillmentService.counts(lines);

    if (c.ready == 0 && c.pendingRo > 0) {
      throw 'Masih ada item RO pending. '
          'Ambil item READY lewat scan QR LUNAS, atau tunggu RO selesai.';
    }

    List<String> ids = const [];
    if (c.ready > 0) {
      final taken = await fulfill.markReadyLinesDiambil(
        saleId: sale['id'].toString(),
      );
      ids = taken.map((e) => e['id'].toString()).toList();
    }

    if (ids.isEmpty) {
      // Nota lama tanpa kolom fulfillment — aktifkan semua kartu menunggu.
      return konfirmasiAmbilItems(
        noInvoice: noInvoice,
        saleItemIds: const [],
        fotoHasilUrl: fotoHasilUrl,
        tokoId: tokoId,
        isPusat: isPusat,
        activateAllWaiting: true,
      );
    }
    return konfirmasiAmbilItems(
      noInvoice: noInvoice,
      saleItemIds: ids,
      fotoHasilUrl: fotoHasilUrl,
      tokoId: tokoId,
      isPusat: isPusat,
    );
  }

  Map<String, dynamic> _aktifPatch({String? fotoHasilUrl, DateTime? now}) {
    final at = now ?? DateTime.now();
    final mulai = jakartaDateOnly(at);
    final akhir = tanggalAkhirDariMulai(mulai);
    final patch = <String, dynamic>{
      'status': 'aktif',
      'tanggal_mulai': formatDate(mulai),
      'tanggal_akhir': formatDate(akhir),
      'diambil_at': at.toUtc().toIso8601String(),
    };
    final foto = (fotoHasilUrl ?? '').trim();
    if (foto.isNotEmpty) patch['foto_hasil_url'] = foto;
    return patch;
  }

  /// Aktifkan kartu menunggu untuk [saleItemIds]. Return id kartu yang aktif.
  Future<List<String>> _activateWaitingKartu({
    required String saleId,
    required List<String> saleItemIds,
    String? fotoHasilUrl,
    bool activateAllWaiting = false,
  }) async {
    final patch = _aktifPatch(fotoHasilUrl: fotoHasilUrl);
    if (activateAllWaiting || saleItemIds.isEmpty) {
      final rows = await _db
          .from('garansi_kartu')
          .update(patch)
          .eq('sale_id', saleId)
          .eq('status', 'menunggu_ambil')
          .select('id');
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map)['id'].toString())
          .toList();
    }

    final activated = <String>[];
    for (final itemId in saleItemIds) {
      if (itemId.trim().isEmpty) continue;
      final rows = await _db
          .from('garansi_kartu')
          .update(patch)
          .eq('sale_id', saleId)
          .eq('sale_item_id', itemId)
          .eq('status', 'menunggu_ambil')
          .select('id');
      for (final raw in rows as List) {
        activated.add(Map<String, dynamic>.from(raw as Map)['id'].toString());
      }
    }
    return activated;
  }

  /// Pulihkan kartu yang macet: line sudah DIAMBIL tapi status masih menunggu_ambil.
  Future<int> syncAktifDariLineDiambil(String saleId) async {
    final items = await _db
        .from('sales_items')
        .select('id, nama_produk, fulfillment_status, diambil_at')
        .eq('sale_id', saleId);
    final diambil = (items as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((i) {
          final st = (i['fulfillment_status'] ?? '').toString().toUpperCase();
          return st == 'DIAMBIL' || i['diambil_at'] != null;
        })
        .toList();
    if (diambil.isEmpty) return 0;

    var n = await _db.from('garansi_kartu').select('id').eq('sale_id', saleId);
    if ((n as List).isEmpty) {
      await createKartuFromSale(saleId);
    }

    final diambilIds = diambil
        .map((i) => i['id'].toString())
        .where((id) => id.isNotEmpty)
        .toList();
    var activated = await _activateWaitingKartu(
      saleId: saleId,
      saleItemIds: diambilIds,
    );

    // Fallback: match nama produk jika sale_item_id di kartu tidak cocok.
    if (activated.isEmpty) {
      final names = diambil
          .map((i) => (i['nama_produk'] ?? '').toString().trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      final waiting = await _db
          .from('garansi_kartu')
          .select('id, nama_produk, sale_item_id')
          .eq('sale_id', saleId)
          .eq('status', 'menunggu_ambil');
      final patch = _aktifPatch();
      for (final raw in waiting as List) {
        final k = Map<String, dynamic>.from(raw as Map);
        final nama = (k['nama_produk'] ?? '').toString().trim().toLowerCase();
        if (!names.contains(nama)) continue;
        final rows = await _db
            .from('garansi_kartu')
            .update(patch)
            .eq('id', k['id'])
            .eq('status', 'menunggu_ambil')
            .select('id');
        for (final r in rows as List) {
          activated.add(Map<String, dynamic>.from(r as Map)['id'].toString());
        }
      }
    }
    return activated.length;
  }

  /// Partial: aktifkan garansi hanya untuk [saleItemIds] yang diserahkan.
  Future<Map<String, dynamic>> konfirmasiAmbilItems({
    required String noInvoice,
    required List<String> saleItemIds,
    String? fotoHasilUrl,
    String? tokoId,
    bool isPusat = false,
    bool activateAllWaiting = false,
  }) async {
    final sale = await findSaleByInvoice(
      noInvoice,
      tokoId: tokoId,
      isPusat: isPusat,
    );
    if (sale == null) throw 'Invoice tidak ditemukan.';

    if (!isSaleLunas(sale)) {
      throw 'Transaksi belum Lunas. Selesaikan pembayaran dulu.';
    }

    final foto = (fotoHasilUrl ?? '').trim();
    final saleId = sale['id'].toString();

    var n = await _db.from('garansi_kartu').select('id').eq('sale_id', saleId);
    if ((n as List).isEmpty) {
      await createKartuFromSale(saleId);
    }

    var activated = await _activateWaitingKartu(
      saleId: saleId,
      saleItemIds: saleItemIds,
      fotoHasilUrl: foto.isEmpty ? null : foto,
      activateAllWaiting: activateAllWaiting,
    );

    // Fallback: line sudah DIAMBIL / id kartu tidak cocok.
    if (activated.isEmpty && saleItemIds.isNotEmpty && !activateAllWaiting) {
      final n = await syncAktifDariLineDiambil(saleId);
      if (n > 0) {
        final rows = await _db
            .from('garansi_kartu')
            .select('id')
            .eq('sale_id', saleId)
            .eq('status', 'aktif')
            .inFilter('sale_item_id', saleItemIds);
        activated = (rows as List)
            .map((e) => Map<String, dynamic>.from(e as Map)['id'].toString())
            .toList();
      }
    }

    // Wajib aktifkan kartu frame/lensa untuk item terpilih (bila kartu ada).
    if (!activateAllWaiting && saleItemIds.isNotEmpty) {
      final waiting = await _db
          .from('garansi_kartu')
          .select('id, sale_item_id, nama_produk')
          .eq('sale_id', saleId)
          .eq('status', 'menunggu_ambil')
          .inFilter('sale_item_id', saleItemIds);
      if ((waiting as List).isNotEmpty) {
        throw 'Gagal aktifkan garansi untuk: '
            '${waiting.map((e) => (e as Map)['nama_produk'] ?? '?').join(', ')}. '
            'Coba lagi / cek kartu garansi.';
      }
    }

    final patch = _aktifPatch(fotoHasilUrl: foto.isEmpty ? null : foto);
    if (foto.isNotEmpty) {
      await _db.from('sales').update({
        'foto_hasil_url': foto,
      }).eq('id', saleId);
    }

    return {
      'sale_id': saleId,
      'no_invoice': sale['no_invoice'],
      'tanggal_mulai': patch['tanggal_mulai'],
      'tanggal_akhir': patch['tanggal_akhir'],
      'garansi_hari': garansiHari,
      'activated_item_ids': saleItemIds,
      'activated_kartu_ids': activated,
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
    final tenantId = TenantService.instance.id;
    if (tenantId != null && tenantId.isNotEmpty) {
      req = req.eq('tenant_id', tenantId);
    }

    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      req = req.inFilter('toko_id', GaransiRules.storeAliases(tokoId));
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
    final tenantId = TenantService.instance.id;
    if (tenantId != null && tenantId.isNotEmpty) {
      req = req.eq('tenant_id', tenantId);
    }

    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      req = req.inFilter('toko_id', GaransiRules.storeAliases(tokoId));
    }

    final rows = await req.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Pengajuan klaim dari Member app (`garansi_klaim_request`).
  Future<List<Map<String, dynamic>>> listClaimRequests({
    String? tokoId,
    bool isPusat = false,
    int limit = 100,
  }) async {
    var req = _db.from('garansi_klaim_request').select(
          '*, garansi_kartu:kartu_id(id, no_invoice, nama_pelanggan, no_wa, '
          'nama_produk, jenis_garansi, tanggal_akhir, status, toko_id)',
        );
    final tenantId = TenantService.instance.id;
    if (tenantId != null && tenantId.isNotEmpty) {
      req = req.eq('tenant_id', tenantId);
    }

    if (!isPusat && tokoId != null && tokoId.isNotEmpty) {
      req = req.inFilter('toko_id', GaransiRules.storeAliases(tokoId));
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
    final tenantId = TenantService.instance.id;

    var menungguQ = _db
        .from('garansi_kartu')
        .select('id')
        .eq('status', 'menunggu_ambil');
    var aktifQ = _db.from('garansi_kartu').select('id').eq('status', 'aktif');
    var klaimQ = _db
        .from('garansi_klaim')
        .select('id')
        .gte('created_at', monthStart.toUtc().toIso8601String());
    if (tenantId != null && tenantId.isNotEmpty) {
      menungguQ = menungguQ.eq('tenant_id', tenantId);
      aktifQ = aktifQ.eq('tenant_id', tenantId);
      klaimQ = klaimQ.eq('tenant_id', tenantId);
    }
    final menunggu = await menungguQ;
    final aktif = await aktifQ;
    final klaimBulan = await klaimQ;

    return {
      'menunggu_ambil': (menunggu as List).length,
      'kartu_aktif': (aktif as List).length,
      'klaim_bulan_ini': (klaimBulan as List).length,
    };
  }

  /// True jika kartu boleh diajukan klaim (aktif, belum dipakai, masih dalam 7 hari).
  static bool kartuBisaDiklaim(
    Map<String, dynamic> kartu, {
    DateTime? now,
  }) {
    return alasanTidakBisaKlaim(kartu, now: now) == null;
  }

  /// Hari kalender mulai window (diambil), atau null jika belum dimulai.
  static DateTime? tanggalMulaiKartu(Map<String, dynamic> kartu) {
    final dariMulai = parseDateOnly(kartu['tanggal_mulai']);
    if (dariMulai != null) return dariMulai;
    return parseDateOnly(kartu['diambil_at']);
  }

  /// Akhir inklusif window klaim (hari ke-7). Null jika belum bisa dihitung.
  /// Hard-cap `mulai + 7` meski `tanggal_akhir` di DB lebih panjang.
  static DateTime? tanggalAkhirKartu(Map<String, dynamic> kartu) {
    final mulai = tanggalMulaiKartu(kartu);
    final akhir = parseDateOnly(kartu['tanggal_akhir']);
    if (mulai != null) {
      final hard = tanggalAkhirDariMulai(mulai);
      if (akhir == null) return hard;
      return akhir.isBefore(hard) ? akhir : hard;
    }
    return akhir;
  }

  /// True jika [todayJkt] sudah lewat hari ke-7 sejak diambil.
  static bool isGaransiMati(
    Map<String, dynamic> kartu, {
    DateTime? now,
  }) {
    final today = jakartaDateOnly(now);
    final mulai = tanggalMulaiKartu(kartu);
    if (mulai != null && today.isAfter(tanggalAkhirDariMulai(mulai))) {
      return true;
    }
    final akhir = tanggalAkhirKartu(kartu);
    if (akhir == null) return false;
    return today.isAfter(akhir);
  }

  /// Null = boleh klaim. Selain itu = alasan singkat untuk UI Member/Admin.
  static String? alasanTidakBisaKlaim(
    Map<String, dynamic> kartu, {
    DateTime? now,
  }) {
    final status = (kartu['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'menunggu_ambil') {
      return 'Belum aktif — ambil barang di toko dulu.';
    }
    if (kartu['klaim_digunakan'] == true || status == 'diklaim') {
      return 'Klaim untuk transaksi ini sudah dipakai (maks. 1×).';
    }
    if (status == 'habis' || status == 'mati') {
      return 'Garansi mati — lebih dari 7 hari sejak diambil.';
    }
    if (status == 'batal') {
      return 'Garansi dibatalkan — tidak bisa klaim.';
    }
    if (status != 'aktif') {
      return 'Garansi tidak aktif.';
    }
    if (isGaransiMati(kartu, now: now)) {
      return 'Garansi mati — lebih dari 7 hari sejak diambil.';
    }
    final akhir = tanggalAkhirKartu(kartu);
    if (akhir == null) {
      return 'Tanggal akhir garansi tidak valid.';
    }
    return null;
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

    final blocked = alasanTidakBisaKlaim(kartu);
    if (blocked != null) {
      throw blocked;
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
    final tenantId = TenantService.instance.id;
    final row = await _db
        .from('garansi_klaim')
        .insert({
          'kartu_id': kartuId,
          'sale_id': saleId,
          'toko_id': tokoId,
          if (tenantId != null && tenantId.isNotEmpty) 'tenant_id': tenantId,
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

    try {
      await _db
          .from('garansi_klaim_request')
          .update({'status': 'selesai'})
          .eq('sale_id', saleId)
          .inFilter('status', const ['diajukan', 'diproses_toko']);
    } catch (_) {}

    if (keputusan == 'ditolak') {
      // Tetap tandai klaim dipakai, tapi kartu bisa ditandai diklaim/habis
      final statusAkhir =
          isGaransiMati(kartu) ? 'habis' : 'diklaim';
      await _db
          .from('garansi_kartu')
          .update({'status': statusAkhir, 'klaim_digunakan': true}).eq(
              'sale_id', saleId);
    }

    return Map<String, dynamic>.from(row);
  }

  static int sisaHari(Map<String, dynamic> kartu, {DateTime? now}) {
    final status = (kartu['status'] ?? '').toString().trim().toLowerCase();
    if (status == 'menunggu_ambil') return -999; // sentinel: belum mulai
    final akhir = tanggalAkhirKartu(kartu);
    if (akhir == null) return 0;
    return akhir.difference(jakartaDateOnly(now)).inDays;
  }

  static String statusLabel(Map<String, dynamic> kartu, {DateTime? now}) {
    final s = (kartu['status'] ?? '-').toString().trim().toLowerCase();
    if (s == 'menunggu_ambil') return 'Menunggu ambil';
    if (s == 'diklaim' || kartu['klaim_digunakan'] == true) {
      return 'Sudah diklaim';
    }
    if (s == 'batal') return 'Dibatalkan';
    if (s == 'habis' || s == 'mati' || isGaransiMati(kartu, now: now)) {
      return 'Mati';
    }
    if (s == 'aktif') {
      final sisa = sisaHari(kartu, now: now);
      return sisa >= 0 ? 'Aktif ($sisa hari lagi)' : 'Mati';
    }
    if (s.isEmpty || s == '-') return '-';
    return s;
  }

  /// Pengajuan masih terbuka (blok klaim baru untuk kartu yang sama).
  static bool isOpenClaimRequestStatus(String? status) {
    final st = (status ?? '').trim().toLowerCase();
    return st == 'diajukan' || st == 'diproses_toko';
  }

  /// Label status pengajuan klaim dari Member app (`garansi_klaim_request`).
  static String claimRequestStatusLabel(String? status) {
    return switch ((status ?? '').trim().toLowerCase()) {
      'diajukan' => 'Diajukan',
      'diproses_toko' => 'Diproses toko',
      'selesai' => 'Selesai',
      'dibatalkan' => 'Dibatalkan',
      '' => '-',
      final s => s,
    };
  }

  /// Kartu yang boleh dipilih di form klaim Member.
  /// [openRequestsKnown]=false → fail-closed (kosong).
  static List<Map<String, dynamic>> filterClaimableKartu({
    required List<Map<String, dynamic>> kartu,
    required Iterable<Map<String, dynamic>> requests,
    required bool openRequestsKnown,
    DateTime? now,
  }) {
    if (!openRequestsKnown) return const [];
    final openIds = <String>{};
    for (final r in requests) {
      if (!isOpenClaimRequestStatus(r['status']?.toString())) continue;
      final id = r['kartu_id']?.toString();
      if (id != null && id.isNotEmpty) openIds.add(id);
    }
    return kartu
        .where(
          (g) =>
              kartuBisaDiklaim(g, now: now) &&
              !openIds.contains(g['id']?.toString() ?? ''),
        )
        .toList(growable: false);
  }
}
