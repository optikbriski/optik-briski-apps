import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../garansi/garansi_service.dart';
import '../qr/obr_codes.dart';
import 'invoice_link.dart';

/// Siklus QR pelanggan sekali pakai: DP → LUNAS → CLAIM.
class InvoiceLifecycleService {
  InvoiceLifecycleService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static final _rng = Random.secure();

  static String newToken([int bytes = 16]) {
    final buf = List<int>.generate(bytes, (_) => _rng.nextInt(256));
    return buf.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Payload QR pelanggan sesuai status sale saat ini (null jika token habis).
  static String? customerQrPayload(Map<String, dynamic> sale) {
    final encoded = InvoiceLink.encodeFromSale(sale);
    if (encoded.isEmpty || encoded.startsWith('OBRTXN|')) return null;
    return encoded;
  }

  /// Pastikan token fase saat ini ada (hanya jika fase QR sudah dibuka admin).
  Future<Map<String, dynamic>> ensureTokens(String saleId) async {
    final sale =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    if (sale == null) throw 'Transaksi tidak ditemukan.';
    final patch = <String, dynamic>{};
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    final diambil = sale['diambil_at'] != null || tracking == 'DIAMBIL';
    final dpReady = tracking == 'SIAP_PELUNASAN' ||
        (sale['qr_dp_token'] ?? '').toString().trim().length >= 8;
    final lunasReady = tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR';

    if (isDp) {
      // QR DP hanya setelah admin "Barang Ready" — jangan auto-buat di PENDING.
      if (dpReady &&
          (sale['qr_dp_token'] ?? '').toString().trim().length < 8 &&
          sale['qr_dp_used_at'] == null) {
        patch['qr_dp_token'] = newToken();
      }
    } else if (!diambil) {
      if (lunasReady &&
          (sale['qr_lunas_token'] ?? '').toString().trim().length < 8 &&
          sale['qr_lunas_used_at'] == null) {
        patch['qr_lunas_token'] = newToken();
      }
    } else {
      if ((sale['qr_claim_token'] ?? '').toString().trim().length < 8 &&
          sale['qr_claim_used_at'] == null) {
        patch['qr_claim_token'] = newToken();
      }
    }

    // Normalisasi status bayar ke DP/LUNAS
    if (pay == 'DP' || pay == 'LUNAS') {
      if ((sale['status_pembayaran']?.toString() ?? '') != pay) {
        patch['status_pembayaran'] = pay;
      }
    }

    if (patch.isNotEmpty) {
      await _db.from('sales').update(patch).eq('id', saleId);
      final updated =
          await _db.from('sales').select().eq('id', saleId).maybeSingle();
      return Map<String, dynamic>.from(updated ?? sale);
    }
    return Map<String, dynamic>.from(sale);
  }

  /// Validasi raw scan vs fase transaksi. Lempar jika tidak cocok / sudah dipakai.
  Future<({Map<String, dynamic> sale, String phase, String token})>
      validateCustomerScan(String raw) async {
    final parsed = ObrInvoice.parse(raw);
    if (parsed == null || !parsed.customerLifecycle) {
      throw 'QR pelanggan tidak valid. Gunakan QR DP / LUNAS / CLAIM bertoken.';
    }
    final phase = parsed.phase!;
    final token = parsed.token!;
    final sale = await _db
        .from('sales')
        .select()
        .eq('no_invoice', parsed.noInvoice)
        .maybeSingle();
    if (sale == null) throw 'Invoice tidak ditemukan.';

    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    final diambil = sale['diambil_at'] != null ||
        (sale['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');

    if (phase == 'DP') {
      if (!isDp) throw 'QR DP sudah tidak berlaku (transaksi sudah lunas).';
      if (sale['qr_dp_used_at'] != null) {
        throw 'QR DP sudah dipakai. Cetak QR LUNAS setelah pelunasan.';
      }
      if ((sale['qr_dp_token'] ?? '').toString() != token) {
        throw 'Token QR DP tidak cocok / sudah diganti.';
      }
    } else if (phase == 'LUNAS') {
      if (isDp) throw 'QR LUNAS belum berlaku. Lunasi sisa tagihan dulu.';
      if (diambil) {
        throw 'QR LUNAS sudah dipakai untuk serah terima. Pakai QR CLAIM.';
      }
      if (sale['qr_lunas_used_at'] != null) {
        throw 'QR LUNAS sudah dipakai (sekali pakai).';
      }
      if ((sale['qr_lunas_token'] ?? '').toString() != token) {
        throw 'Token QR LUNAS tidak cocok / sudah diganti.';
      }
    } else if (phase == 'CLAIM') {
      if (!diambil) {
        throw 'QR CLAIM belum berlaku. Selesaikan serah terima dulu.';
      }
      if (sale['qr_claim_used_at'] != null) {
        throw 'QR CLAIM sudah dipakai (sekali pakai). Case closed.';
      }
      if ((sale['qr_claim_token'] ?? '').toString() != token) {
        throw 'Token QR CLAIM tidak cocok / sudah diganti.';
      }
    } else {
      throw 'Fase QR tidak dikenali.';
    }

    return (sale: Map<String, dynamic>.from(sale), phase: phase, token: token);
  }

  /// Pelunasan via scan QR DP pelanggan (kasir / HID).
  Future<Map<String, dynamic>> settleDpViaGateway({
    required String saleId,
    required String metodePembayaran,
    required String staffNik,
    required String staffNama,
    required String rawScan,
  }) async {
    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'DP') {
      throw 'Scan QR DP pelanggan untuk pelunasan.';
    }
    if (validated.sale['id']?.toString() != saleId) {
      throw 'Invoice tidak cocok dengan QR.';
    }
    return _settleDpCore(
      sale: validated.sale,
      saleId: saleId,
      metodePembayaran: metodePembayaran,
      staffNik: staffNik,
      staffNama: staffNama,
    );
  }

  /// Pelunasan langsung dari board admin (tanpa scan QR).
  Future<Map<String, dynamic>> settleDpByAdmin({
    required String saleId,
    required String metodePembayaran,
    required String staffNik,
    required String staffNama,
  }) async {
    final sale =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    if (sale == null) throw 'Transaksi tidak ditemukan.';
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    if (pay != 'DP' && sisa <= 0) {
      throw 'Nota ini bukan DP / tidak ada sisa tagihan.';
    }
    return _settleDpCore(
      sale: Map<String, dynamic>.from(sale),
      saleId: saleId,
      metodePembayaran: metodePembayaran,
      staffNik: staffNik,
      staffNama: staffNama,
    );
  }

  /// Pelunasan sisa (1x) + jurnal finance + langsung LUNAS ready.
  Future<Map<String, dynamic>> _settleDpCore({
    required Map<String, dynamic> sale,
    required String saleId,
    required String metodePembayaran,
    required String staffNik,
    required String staffNama,
  }) async {
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final dibayar = int.tryParse(sale['dibayarkan']?.toString() ?? '0') ?? 0;
    final total = int.tryParse(sale['total_harga']?.toString() ?? '0') ?? 0;
    final bayarPelunasan = sisa > 0 ? sisa : (total - dibayar).clamp(0, total);
    if (bayarPelunasan <= 0) throw 'Tidak ada sisa tagihan untuk dilunasi.';

    final metode = metodePembayaran.trim();
    if (metode.isEmpty) throw 'Metode pembayaran wajib.';

    final now = DateTime.now();
    final lunasToken = newToken();

    try {
      await _db.from('finance_transactions').insert({
        'toko_id': sale['toko_id'],
        'tanggal_transaksi': now.toIso8601String().split('T').first,
        'jenis_transaksi': 'PEMASUKAN',
        'kategori': 'Pelunasan Kasir',
        'deskripsi':
            'Pelunasan ${sale['no_invoice']} · ${sale['nama_pelanggan'] ?? ''} · oleh $staffNama ($staffNik)',
        'nominal': bayarPelunasan,
        'status_pembayaran': 'LUNAS',
        'metode_pembayaran': metode,
        'nama_kasir': staffNama,
        'status_konfirmasi': 'APPROVED',
        'referensi_id': sale['no_invoice']?.toString(),
        'updated_at': now.toIso8601String(),
      });
    } catch (e) {
      throw 'Gagal catat finance pelunasan — sales tidak diubah. Detail: $e';
    }

    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    final dpAlreadyReady = tracking == 'SIAP_PELUNASAN' ||
        (sale['qr_dp_token'] ?? '').toString().trim().length >= 8;

    try {
      await _db.from('sales').update({
        'status_pembayaran': 'LUNAS',
        'dibayarkan': dibayar + bayarPelunasan,
        'sisa_tagihan': 0,
        // Sudah ready sebelumnya → CLEAR + QR ambil.
        // Belum ready → masuk PENDING (QR nanti setelah admin ready).
        'tracking_status': dpAlreadyReady ? 'SIAP_DIAMBIL' : 'PENDING_PO',
        'metode_pembayaran': metode,
        'lunas_at': now.toUtc().toIso8601String(),
        'qr_dp_used_at': now.toUtc().toIso8601String(),
        'qr_dp_used_by': staffNik,
        if (dpAlreadyReady) 'qr_lunas_token': lunasToken,
        if (dpAlreadyReady) 'qr_lunas_used_at': null,
        if (dpAlreadyReady) 'qr_lunas_used_by': null,
      }).eq('id', saleId);
    } catch (e) {
      throw 'Finance sudah tercatat, tetapi update sales gagal. '
          'Hubungi admin segera (invoice ${sale['no_invoice']}). Detail: $e';
    }

    final updated =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    return Map<String, dynamic>.from(updated ?? sale);
  }

  /// Admin: barang ready — DP → QR pelunasan; lunas pending → QR pengambilan.
  Future<Map<String, dynamic>> markGoodsReadyAndIssueCustomerQr({
    required String saleId,
    required String staffNik,
    String? staffNama,
  }) async {
    final sale =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    if (sale == null) throw 'Transaksi tidak ditemukan.';

    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    if (sale['diambil_at'] != null || tracking == 'DIAMBIL') {
      throw 'Barang sudah diambil. Tidak perlu konfirmasi ready.';
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final by = [
      if ((staffNama ?? '').trim().isNotEmpty) staffNama!.trim(),
      if (staffNik.trim().isNotEmpty) staffNik.trim(),
    ].join(' · ');

    if (isDp) {
      if (tracking == 'SIAP_PELUNASAN' &&
          (sale['qr_dp_token'] ?? '').toString().trim().length >= 8) {
        return Map<String, dynamic>.from(sale);
      }
      final dpToken = newToken();
      await _db.from('sales').update({
        'tracking_status': 'SIAP_PELUNASAN',
        'qr_dp_token': dpToken,
        'qr_dp_used_at': null,
        'qr_dp_used_by': null,
        'updated_at': now,
        if (by.isNotEmpty) 'nama_kasir': sale['nama_kasir'] ?? by,
      }).eq('id', saleId);
    } else {
      if (tracking == 'SIAP_DIAMBIL' || tracking == 'CLEAR') {
        return ensureTokens(saleId);
      }
      final lunasToken = newToken();
      await _db.from('sales').update({
        'tracking_status': 'SIAP_DIAMBIL',
        'qr_lunas_token': lunasToken,
        'qr_lunas_used_at': null,
        'qr_lunas_used_by': null,
        'updated_at': now,
        if (by.isNotEmpty) 'nama_kasir': sale['nama_kasir'] ?? by,
      }).eq('id', saleId);
    }

    final updated =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    return Map<String, dynamic>.from(updated ?? sale);
  }

  /// Alias lama → [markGoodsReadyAndIssueCustomerQr] (lunas pending).
  Future<Map<String, dynamic>> markGlassesReadyAndIssueLunasQr({
    required String saleId,
    required String staffNik,
    String? staffNama,
  }) =>
      markGoodsReadyAndIssueCustomerQr(
        saleId: saleId,
        staffNik: staffNik,
        staffNama: staffNama,
      );

  /// Serah terima + aktifkan garansi + consume LUNAS + terbitkan CLAIM.
  /// Hanya untuk QR LUNAS ready (tracking sudah SIAP_DIAMBIL/CLEAR).
  Future<Map<String, dynamic>> handoverAndIssueClaim({
    required String noInvoice,
    required String rawScan,
    required String staffNik,
    String? fotoHasilUrl,
    String? tokoId,
    bool isPusat = false,
  }) async {
    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'LUNAS') {
      throw 'Scan QR LUNAS ready pelanggan untuk serah terima / aktifkan garansi.';
    }
    if (validated.sale['no_invoice']?.toString() != noInvoice) {
      throw 'Invoice tidak cocok dengan QR.';
    }

    final tracking =
        (validated.sale['tracking_status'] ?? '').toString().toUpperCase();
    if (tracking != 'SIAP_DIAMBIL' && tracking != 'CLEAR') {
      throw 'QR LUNAS ready belum berlaku. '
          'Admin harus konfirmasi barang ready dulu (lunas pending).';
    }

    final garansi = GaransiService(client: _db);
    final res = await garansi.konfirmasiAmbil(
      noInvoice: noInvoice,
      fotoHasilUrl: fotoHasilUrl,
      tokoId: tokoId,
      isPusat: isPusat,
    );

    final claimToken = newToken();
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.from('sales').update({
      'qr_lunas_used_at': now,
      'qr_lunas_used_by': staffNik,
      'qr_claim_token': claimToken,
      'qr_claim_used_at': null,
      'qr_claim_used_by': null,
    }).eq('id', validated.sale['id']);

    final sale = await _db
        .from('sales')
        .select()
        .eq('id', validated.sale['id'])
        .maybeSingle();

    return {
      ...res,
      'sale': sale,
      'claim_qr': sale == null ? null : customerQrPayload(sale),
    };
  }

  /// Buka klaim: consume QR CLAIM (sekali) — case closed setelahnya.
  Future<void> consumeClaimQr({
    required String rawScan,
    required String staffNik,
  }) async {
    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'CLAIM') {
      throw 'Scan QR CLAIM pelanggan untuk klaim garansi.';
    }

    final cards = await _db
        .from('garansi_kartu')
        .select()
        .eq('sale_id', validated.sale['id']);
    final garansi = GaransiService(client: _db);
    final anyClaimable = (cards as List).any(
      (raw) => garansi.kartuBisaDiklaim(Map<String, dynamic>.from(raw as Map)),
    );
    if (!anyClaimable) {
      throw 'Case closed: garansi habis masa / sudah diklaim / belum aktif.';
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await _db.from('sales').update({
      'qr_claim_used_at': now,
      'qr_claim_used_by': staffNik,
    }).eq('id', validated.sale['id']);
  }
}
