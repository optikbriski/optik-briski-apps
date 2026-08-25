import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../garansi/garansi_service.dart';
import '../qr/obr_codes.dart';
import '../qr/qr_scan_rules.dart';
import '../tenant/tenant_service.dart';
import 'invoice_lifecycle_rules.dart';
import 'invoice_link.dart';
import 'sale_fulfillment_service.dart';

/// Siklus QR pelanggan sekali pakai: DP → LUNAS → CLAIM.
/// Fulfillment per-line: RO pending vs READY partial pickup.
class InvoiceLifecycleService {
  InvoiceLifecycleService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client,
        _fulfillment = SaleFulfillmentService(client: client);

  final SupabaseClient _db;
  final SaleFulfillmentService _fulfillment;
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

  Future<Map<String, dynamic>?> _saleById(String saleId) async {
    var q = _db.from('sales').select().eq('id', saleId);
    final bound = AttendanceAdminScope.boundTenantIdOrNull();
    if (bound != null) q = q.eq('tenant_id', bound);
    return q.maybeSingle();
  }

  Future<void> _updateSale(String saleId, Map<String, dynamic> patch) async {
    var q = _db.from('sales').update(patch).eq('id', saleId);
    final bound = AttendanceAdminScope.boundTenantIdOrNull();
    if (bound != null) q = q.eq('tenant_id', bound);
    await q;
  }

  bool _rpcMissing(PostgrestException e) {
    final code = (e.code ?? '').toUpperCase();
    final msg = e.message.toLowerCase();
    return code == 'PGRST202' ||
        code == 'PGRST204' ||
        msg.contains('could not find the function') ||
        msg.contains('schema cache');
  }

  /// Pastikan token fase saat ini ada (hanya jika fase QR sudah dibuka admin).
  Future<Map<String, dynamic>> ensureTokens(String saleId) async {
    final sale = await _saleById(saleId);
    if (sale == null) throw 'Transaksi tidak ditemukan.';
    final patch = <String, dynamic>{};
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    final isDp = pay == 'DP' || sisa > 0;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    final diambil = sale['diambil_at'] != null || tracking == 'DIAMBIL';
    // DP QR hanya di fase SIAP_PELUNASAN (bukan token orphan di PENDING).
    final dpReady = tracking == 'SIAP_PELUNASAN';
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
      await _updateSale(saleId, patch);
      final updated = await _saleById(saleId);
      return Map<String, dynamic>.from(updated ?? sale);
    }
    return Map<String, dynamic>.from(sale);
  }

  /// Validasi raw scan vs fase transaksi. Lempar jika tidak cocok / sudah dipakai.
  Future<({Map<String, dynamic> sale, String phase, String token})>
      validateCustomerScan(String raw) async {
    final parsed = ObrInvoice.parse(raw);
    if (parsed == null || !parsed.customerLifecycle) {
      throw QrScanRules.messageForReason('bukan_qr_invoice');
    }
    final phase = parsed.phase!;
    final token = parsed.token!;

    try {
      final res = await _db.rpc(
        'validate_invoice_customer_qr',
        params: TenantService.instance.isBound
            ? withTenant({'p_payload': raw.trim()})
            : {'p_payload': raw.trim()},
      );
      final map = res is Map ? Map<String, dynamic>.from(res) : null;
      if (map == null) throw QrScanRules.messageForReason('bukan_qr_invoice');
      if (map['ok'] != true) {
        throw QrScanRules.messageForReason(map['reason']?.toString());
      }
      final saleId = (map['sale_id'] ?? '').toString();
      final sale = saleId.isEmpty ? null : await _saleById(saleId);
      if (sale == null) {
        throw QrScanRules.messageForReason('invoice_tidak_ditemukan');
      }
      return (
        sale: Map<String, dynamic>.from(sale),
        phase: (map['phase'] ?? phase).toString(),
        token: token,
      );
    } on PostgrestException catch (e) {
      if (!_rpcMissing(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty ? QrScanRules.messageForReason(null) : msg;
      }
    }

    var q = _db.from('sales').select().eq('no_invoice', parsed.noInvoice);
    final bound = AttendanceAdminScope.boundTenantIdOrNull();
    if (bound != null) q = q.eq('tenant_id', bound);
    final sale = await q.maybeSingle();
    if (sale == null) {
      throw QrScanRules.messageForReason('invoice_tidak_ditemukan');
    }

    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    final isDp = pay == 'DP' || sisa > 0;
    final trackingFull =
        (sale['tracking_status']?.toString().toUpperCase() ?? '');
    final allDiambil = sale['diambil_at'] != null || trackingFull == 'DIAMBIL';
    // Partial: claim berlaku jika token CLAIM sudah diterbitkan (batch handover).
    final claimTokenReady =
        (sale['qr_claim_token'] ?? '').toString().trim().length >= 8;

    if (phase == 'DP') {
      if (!isDp) throw 'QR DP sudah tidak berlaku (transaksi sudah lunas).';
      if (trackingFull != 'SIAP_PELUNASAN') {
        throw 'QR DP belum berlaku. Admin harus konfirmasi Barang Ready dulu.';
      }
      if (sale['qr_dp_used_at'] != null) {
        throw 'QR DP sudah dipakai. Cetak QR LUNAS setelah pelunasan.';
      }
      if ((sale['qr_dp_token'] ?? '').toString() != token) {
        throw 'Token QR DP tidak cocok / sudah diganti.';
      }
    } else if (phase == 'LUNAS') {
      if (isDp) throw 'QR LUNAS belum berlaku. Lunasi sisa tagihan dulu.';
      if (allDiambil) {
        throw 'QR LUNAS sudah dipakai untuk serah terima. Pakai QR CLAIM.';
      }
      if (sale['qr_lunas_used_at'] != null) {
        throw 'QR LUNAS sudah dipakai (sekali pakai). '
            'Tunggu RO ready / admin kirim QR LUNAS baru.';
      }
      if ((sale['qr_lunas_token'] ?? '').toString() != token) {
        throw 'Token QR LUNAS tidak cocok / sudah diganti.';
      }
      // Wajib ada minimal 1 item READY untuk serah terima.
      final items = await _fulfillment.listItems(sale['id'].toString());
      final ready = SaleFulfillmentService.counts(items).ready;
      if (ready <= 0) {
        throw 'QR LUNAS belum berlaku untuk pengambilan. '
            'Belum ada item READY — selesaikan RO / konfirmasi barang ready.';
      }
    } else if (phase == 'CLAIM') {
      if (!allDiambil && !claimTokenReady) {
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
    String? posPaymentId,
    String? midtransOrderId,
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
      posPaymentId: posPaymentId,
      midtransOrderId: midtransOrderId,
    );
  }

  /// Pelunasan langsung dari board admin (tanpa scan QR).
  Future<Map<String, dynamic>> settleDpByAdmin({
    required String saleId,
    required String metodePembayaran,
    required String staffNik,
    required String staffNama,
  }) async {
    final sale = await _saleById(saleId);
    if (sale == null) throw 'Transaksi tidak ditemukan.';
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
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

  Future<String?> _posPaymentIdForSettle({
    String? posPaymentId,
    String? midtransOrderId,
  }) async {
    final given = (posPaymentId ?? '').trim();
    if (given.isNotEmpty) return given;
    final mid = (midtransOrderId ?? '').trim();
    if (mid.isEmpty) return null;
    try {
      final row = await _db
          .from('pos_payments')
          .select('id')
          .eq('midtrans_order_id', mid)
          .maybeSingle();
      final id = (row?['id'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _saleFromRpc(String fn, dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw 'Respons $fn tidak valid.';
  }

  /// Pelunasan sisa (1x) lewat RPC: nominal dari baris nota, bukan dari HP.
  Future<Map<String, dynamic>> _settleDpCore({
    required Map<String, dynamic> sale,
    required String saleId,
    required String metodePembayaran,
    required String staffNik,
    required String staffNama,
    String? posPaymentId,
    String? midtransOrderId,
  }) async {
    final metode = metodePembayaran.trim();
    if (metode.isEmpty) throw 'Metode pembayaran wajib.';
    if (InvoiceLifecycleRules.remainingFromRow(sale) <= 0) {
      throw 'Tidak ada sisa tagihan untuk dilunasi.';
    }

    try {
      final payId = await _posPaymentIdForSettle(
        posPaymentId: posPaymentId,
        midtransOrderId: midtransOrderId,
      );
      final res = await _db.rpc('settle_invoice_dp', params: {
        'p_sale_id': saleId,
        'p_metode': metode,
        'p_staff_nik': staffNik,
        'p_staff_nama': staffNama,
        if (payId != null) 'p_pos_payment_id': payId,
      });
      return _saleFromRpc('settle_invoice_dp', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal pelunasan DP.' : msg;
    }
  }

  /// Admin: barang ready — DP → QR pelunasan; lunas → QR pengambilan.
  /// [saleItemIds] opsional: hanya line PENDING_RO terpilih → READY.
  /// Null/empty = semua PENDING_RO di nota.
  Future<Map<String, dynamic>> markGoodsReadyAndIssueCustomerQr({
    required String saleId,
    required String staffNik,
    String? staffNama,
    List<String>? saleItemIds,
  }) async {
    final sale = await _saleById(saleId);
    if (sale == null) throw 'Transaksi tidak ditemukan.';

    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = InvoiceLifecycleRules.moneyOf(sale['sisa_tagihan']);
    final isDp = pay == 'DP' || sisa > 0;
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    if (tracking == 'DIAMBIL' && sale['diambil_at'] != null) {
      final items = await _fulfillment.listItems(saleId);
      final c = SaleFulfillmentService.counts(items);
      if (c.total > 0 && c.diambil == c.total) {
        throw 'Barang sudah diambil. Tidak perlu konfirmasi ready.';
      }
    }

    final ids = (saleItemIds ?? [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      final res = await _db.rpc('mark_invoice_goods_ready', params: {
        'p_sale_id': saleId,
        'p_staff_nik': staffNik,
        'p_staff_nama': staffNama,
        if (ids.isNotEmpty) 'p_item_ids': ids,
      });
      final out = _saleFromRpc('mark_invoice_goods_ready', res);
      if (!isDp) {
        final track =
            (out['tracking_status'] ?? '').toString().trim().toUpperCase();
        if (track != 'SIAP_DIAMBIL' && track != 'CLEAR') {
          throw 'Gagal set READY (SIAP_DIAMBIL) untuk nota ini. Coba lagi.';
        }
      }
      return out;
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal tandai Barang Ready.' : msg;
    }
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

  /// Serah terima: hanya [saleItemIds] yang READY → DIAMBIL + garansi batch.
  /// [saleItemIds] wajib (pilihan kasir); tidak boleh kosong.
  /// READY yang tidak dipilih tetap READY — QR LUNAS di-rearm untuk ambil belakangan.
  Future<Map<String, dynamic>> handoverAndIssueClaim({
    required String noInvoice,
    required String rawScan,
    required String staffNik,
    required List<String> saleItemIds,
    String? fotoHasilUrl,
    String? tokoId,
    bool isPusat = false,
  }) async {
    final ids = saleItemIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      throw 'Pilih minimal 1 item READY untuk diambil / aktifkan garansi.';
    }

    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'LUNAS') {
      throw 'Scan QR LUNAS ready pelanggan untuk serah terima / aktifkan garansi.';
    }
    if (validated.sale['no_invoice']?.toString() != noInvoice) {
      throw 'Invoice tidak cocok dengan QR.';
    }

    final saleId = validated.sale['id'].toString();
    final tracking =
        (validated.sale['tracking_status'] ?? '').toString().toUpperCase();
    if (tracking != 'SIAP_DIAMBIL' && tracking != 'CLEAR') {
      throw 'QR LUNAS ready belum berlaku. '
          'Admin harus konfirmasi barang ready dulu, atau ambil item READY.';
    }

    // Tolak id yang bukan READY (hindari nabrak DIAMBIL / RO).
    final lines = await _fulfillment.listItems(saleId);
    final byId = {
      for (final i in lines) i['id'].toString(): i,
    };
    for (final id in ids) {
      final row = byId[id];
      if (row == null) {
        throw 'Item tidak ada di nota ini.';
      }
      final st = SaleFulfillmentService.normalizeLineStatus(
        row['fulfillment_status'],
      );
      if (st == SaleFulfillmentService.statusDiambil) {
        throw 'Item sudah diambil sebelumnya: ${row['nama_produk']}.';
      }
      if (st == SaleFulfillmentService.statusPendingRo) {
        throw 'Item masih RO pending: ${row['nama_produk']}.';
      }
      if (st != SaleFulfillmentService.statusReady) {
        throw 'Item belum READY: ${row['nama_produk']}.';
      }
    }

    // 1) Aktifkan garansi dulu (belum DIAMBIL) — gagal di sini = tidak ubah line.
    final garansi = GaransiService(client: _db);
    Map<String, dynamic> res;
    try {
      res = await garansi.konfirmasiAmbilItems(
        noInvoice: noInvoice,
        saleItemIds: ids,
        fotoHasilUrl: fotoHasilUrl,
        tokoId: tokoId,
        isPusat: isPusat,
      );
    } catch (e) {
      throw 'Gagal aktifkan garansi — serah terima dibatalkan. $e';
    }

    // 2) Baru tandai line DIAMBIL.
    List<String> takenIds;
    try {
      final taken = await _fulfillment.markReadyLinesDiambil(
        saleId: saleId,
        onlyItemIds: ids,
      );
      takenIds = taken.map((e) => e['id'].toString()).toList();
      if (takenIds.isEmpty) {
        throw 'Tidak ada item yang berhasil ditandai diambil.';
      }
    } catch (e) {
      // Garansi sudah aktif — sync ulang line dari kartu aktif bila perlu.
      try {
        await garansi.syncAktifDariLineDiambil(saleId);
      } catch (_) {}
      throw 'Garansi aktif, tapi update item gagal. Refresh hub. Detail: $e';
    }

    final now = DateTime.now().toUtc().toIso8601String();
    Map<String, dynamic> after;
    try {
      after = await _fulfillment.recomputeSale(saleId);
      final allDone =
          (after['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
      final remain = SaleFulfillmentService.counts(
        await _fulfillment.listItems(saleId),
      );
      // READY ditunda → jangan hanguskan LUNAS. Habiskan jika 0 READY tersisa.
      final keepLunasQr = !allDone && remain.ready > 0;

      // Reuse CLAIM token yang belum dipakai (jangan invalidate batch sebelumnya).
      final existingClaim =
          (validated.sale['qr_claim_token'] ?? '').toString().trim();
      final claimUnused = validated.sale['qr_claim_used_at'] == null;
      final claimToken = (existingClaim.length >= 8 && claimUnused)
          ? existingClaim
          : newToken();

      await _updateSale(saleId, {
        if (!keepLunasQr) 'qr_lunas_used_at': now,
        if (!keepLunasQr) 'qr_lunas_used_by': staffNik,
        'qr_claim_token': claimToken,
        if (!(existingClaim.length >= 8 && claimUnused)) 'qr_claim_used_at': null,
        if (!(existingClaim.length >= 8 && claimUnused)) 'qr_claim_used_by': null,
        if (allDone) 'diambil_at': after['diambil_at'] ?? now,
        if (allDone) 'tracking_status': 'DIAMBIL',
        if (!allDone) 'diambil_at': null,
      });

      after = Map<String, dynamic>.from(
        await _saleById(saleId) ?? after,
      );

      final claimQr = InvoiceLink.encode(
        after['no_invoice']?.toString() ?? noInvoice,
        paymentStatus: 'CLAIM',
        token: claimToken,
        channel: ObrSaleChannel.fromSaleChannel(after['channel']?.toString()),
      );

      if (!allDone && remain.ready == 0 && remain.pendingRo > 0) {
        after = await _fulfillment.recomputeSale(saleId);
      }

      return {
        ...res,
        'sale': after,
        'partial': !allDone,
        'deferred_ready': remain.ready,
        'pending_ro': remain.pendingRo,
        'taken_item_ids': takenIds,
        'taken_count': takenIds.length,
        'claim_qr': claimQr,
        'lunas_qr_kept': keepLunasQr,
        'next_lunas_qr':
            keepLunasQr ? InvoiceLink.encodeFromSale(after) : null,
      };
    } catch (e) {
      // Rollback line ke READY agar bisa serah terima ulang.
      try {
        await _fulfillment.revertLinesToReady(
          saleId: saleId,
          saleItemIds: takenIds,
        );
      } catch (_) {}
      throw 'Serah terima gagal setelah ambil item — status item dikembalikan READY. '
          'Detail: $e';
    }
  }

  /// Validasi QR CLAIM saja (belum hanguskan). Panggil [consumeClaimQr] setelah klaim tersimpan.
  Future<({Map<String, dynamic> sale, String phase, String token})>
      validateClaimScan(String rawScan) async {
    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'CLAIM') {
      throw 'Scan QR CLAIM pelanggan untuk klaim garansi.';
    }
    final cards = await _db
        .from('garansi_kartu')
        .select()
        .eq('sale_id', validated.sale['id']);
    final anyClaimable = (cards as List).any(
      (raw) => GaransiService.kartuBisaDiklaim(
        Map<String, dynamic>.from(raw as Map),
      ),
    );
    if (!anyClaimable) {
      throw 'Case closed: garansi habis masa / sudah diklaim / belum aktif.';
    }
    return validated;
  }

  /// Hanguskan QR CLAIM setelah klaim berhasil dibuat.
  ///
  /// Tidak memanggil [validateClaimScan] (yang butuh kartu masih claimable) —
  /// setelah `ajukanDanPutuskan` kartu sudah `diklaim`, jadi burn hanya cek
  /// fase/token QR masih valid & belum dipakai.
  Future<void> consumeClaimQr({
    required String rawScan,
    required String staffNik,
  }) async {
    final nik = staffNik.trim().toUpperCase();
    if (nik.isEmpty) throw 'NIK staf wajib untuk hanguskan QR CLAIM.';

    final validated = await validateCustomerScan(rawScan);
    if (validated.phase != 'CLAIM') {
      throw 'Scan QR CLAIM pelanggan untuk hanguskan klaim.';
    }
    if (validated.sale['qr_claim_used_at'] != null) {
      return; // sudah hangus — idempotent
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _updateSale(validated.sale['id'].toString(), {
      'qr_claim_used_at': now,
      'qr_claim_used_by': nik,
    });
  }

  /// Pastikan ada QR CLAIM aktif bila sudah ada item DIAMBIL + garansi aktif.
  Future<String?> ensureClaimQrIfNeeded(String saleId) async {
    final sale = await _saleById(saleId);
    if (sale == null) return null;
    final items = await _fulfillment.listItems(saleId);
    final c = SaleFulfillmentService.counts(items);
    if (c.diambil <= 0) return null;

    final cards = await _db
        .from('garansi_kartu')
        .select('id, status')
        .eq('sale_id', saleId)
        .eq('status', 'aktif');
    if ((cards as List).isEmpty) return null;

    var token = (sale['qr_claim_token'] ?? '').toString().trim();
    final used = sale['qr_claim_used_at'] != null;
    if (token.length < 8 || used) {
      token = newToken();
      await _updateSale(saleId, {
        'qr_claim_token': token,
        'qr_claim_used_at': null,
        'qr_claim_used_by': null,
      });
    }
    return InvoiceLink.encode(
      sale['no_invoice']?.toString() ?? '',
      paymentStatus: 'CLAIM',
      token: token,
      channel: ObrSaleChannel.fromSaleChannel(sale['channel']?.toString()),
    );
  }
}
