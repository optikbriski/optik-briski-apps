import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'invoice_lifecycle_service.dart';

/// Per-line fulfillment (PENDING_RO / READY / DIAMBIL) + aggregate tracking.
class SaleFulfillmentService {
  SaleFulfillmentService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const statusPendingRo = 'PENDING_RO';
  static const statusReady = 'READY';
  static const statusDiambil = 'DIAMBIL';

  Future<List<Map<String, dynamic>>> listItems(String saleId) async {
    final rows = await _db
        .from('sales_items')
        .select(
          'id, sale_id, nama_produk, tipe_produk, qty, subtotal, '
          'needs_fulfillment, fulfillment_status, diambil_at, pending_request_id',
        )
        .eq('sale_id', saleId);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static String normalizeLineStatus(dynamic raw) {
    final s = (raw ?? statusReady).toString().trim().toUpperCase();
    if (s == statusPendingRo || s == 'PENDING') return statusPendingRo;
    if (s == statusDiambil) return statusDiambil;
    return statusReady;
  }

  static ({int pendingRo, int ready, int diambil, int total}) counts(
    List<Map<String, dynamic>> items,
  ) {
    var pendingRo = 0, ready = 0, diambil = 0;
    for (final i in items) {
      final st = normalizeLineStatus(i['fulfillment_status']);
      if (st == statusPendingRo) {
        pendingRo++;
      } else if (st == statusDiambil) {
        diambil++;
      } else {
        ready++;
      }
    }
    return (
      pendingRo: pendingRo,
      ready: ready,
      diambil: diambil,
      total: items.length,
    );
  }

  static String summaryLabel(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 'Siap diambil';
    final c = counts(items);
    if (c.total > 0 && c.diambil == c.total) return 'Sudah diambil';
    if (c.ready > 0 && c.pendingRo > 0) {
      return 'Partial · Ready ${c.ready} · RO ${c.pendingRo}';
    }
    if (c.ready > 0 && c.diambil > 0 && c.pendingRo > 0) {
      return 'Partial · Diambil ${c.diambil} · Ready ${c.ready} · RO ${c.pendingRo}';
    }
    if (c.pendingRo > 0 && c.ready == 0) return 'RO · stok pending';
    if (c.ready > 0) return 'Siap diambil';
    if (c.diambil > 0 && c.pendingRo > 0) {
      return 'Partial · RO pending';
    }
    return 'Dalam proses';
  }

  /// Aggregate tracking from lines + payment.
  /// - all DIAMBIL → DIAMBIL
  /// - DP open → PENDING_PO | SIAP_PELUNASAN (hanya setelah admin Barang Ready)
  /// - LUNAS + PENDING_PO eksplisit → tetap PENDING (lunasi sebelum ready)
  /// - LUNAS + SIAP_DIAMBIL/CLEAR + READY → SIAP_DIAMBIL
  /// - LUNAS + PENDING_RO only → PENDING_PO
  static String aggregateTracking({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> sale,
    String? preferredIfDpReady,
  }) {
    final c = counts(items);
    if (c.total > 0 && c.diambil == c.total) return 'DIAMBIL';

    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    final t = (sale['tracking_status'] ?? '').toString().toUpperCase();

    if (isDp) {
      if (preferredIfDpReady != null) return preferredIfDpReady;
      if (t == 'SIAP_PELUNASAN') return 'SIAP_PELUNASAN';
      return 'PENDING_PO';
    }

    // Setelah pelunasan DP tanpa Barang Ready — jangan naikkan ke SIAP
    // hanya karena line READY (admin harus konfirmasi dulu).
    if (t == 'PENDING_PO') return 'PENDING_PO';

    if (c.ready > 0) return 'SIAP_DIAMBIL';
    if (c.pendingRo > 0) return 'PENDING_PO';
    if (t == 'SIAP_DIAMBIL' || t == 'CLEAR') return 'SIAP_DIAMBIL';
    return 'SIAP_DIAMBIL';
  }

  /// Recompute + apply sales.tracking_status (and diambil_at when complete).
  Future<Map<String, dynamic>> recomputeSale(String saleId) async {
    final sale =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    if (sale == null) throw 'Transaksi tidak ditemukan.';
    final items = await listItems(saleId);
    final c = counts(items);
    final tracking = aggregateTracking(items: items, sale: sale);
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{
      'tracking_status': tracking,
    };

    if (tracking == 'DIAMBIL') {
      if (sale['diambil_at'] == null) {
        patch['diambil_at'] = now;
      }
    }

    // Partial complete batch left RO: ensure invoice not stuck as DIAMBIL
    if (c.diambil > 0 && c.diambil < c.total && sale['diambil_at'] != null) {
      // Keep diambil_at as first-pickup stamp only if we want — plan says
      // sales.diambil_at only when ALL taken. Clear if set prematurely.
      patch['diambil_at'] = null;
    }

    await _db.from('sales').update(patch).eq('id', saleId);
    final updated =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    return Map<String, dynamic>.from(updated ?? sale);
  }

  Future<void> markLinesReady({
    required String saleId,
    List<String>? saleItemIds,
  }) async {
    if (saleItemIds == null || saleItemIds.isEmpty) {
      await _db
          .from('sales_items')
          .update({
            'fulfillment_status': statusReady,
            'needs_fulfillment': false,
          })
          .eq('sale_id', saleId)
          .eq('fulfillment_status', statusPendingRo);
    } else {
      // Jangan turunkan line yang sudah DIAMBIL.
      await _db
          .from('sales_items')
          .update({
            'fulfillment_status': statusReady,
            'needs_fulfillment': false,
          })
          .eq('sale_id', saleId)
          .eq('fulfillment_status', statusPendingRo)
          .inFilter('id', saleItemIds);
    }
    await recomputeSale(saleId);
  }

  Future<List<Map<String, dynamic>>> markReadyLinesDiambil({
    required String saleId,
    List<String>? onlyItemIds,
  }) async {
    final items = await listItems(saleId);
    final targets = items.where((i) {
      final st = normalizeLineStatus(i['fulfillment_status']);
      if (st != statusReady) return false;
      if (onlyItemIds == null || onlyItemIds.isEmpty) return true;
      return onlyItemIds.contains(i['id']?.toString());
    }).toList();
    if (targets.isEmpty) {
      throw 'Tidak ada item READY untuk diserahkan. '
          'Tunggu RO selesai atau konfirmasi barang ready dulu.';
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final ids = targets.map((e) => e['id'].toString()).toList();
    await _db.from('sales_items').update({
      'fulfillment_status': statusDiambil,
      'diambil_at': now,
    }).inFilter('id', ids);
    // Jangan gagalkan serah terima jika recompute sales error —
    // line sudah DIAMBIL; caller / load berikutnya bisa recompute ulang.
    try {
      await recomputeSale(saleId);
    } catch (_) {}
    return targets;
  }

  /// Setelah RO SUCCESS: set linked line READY + promote tracking + re-arm QR.
  /// Return sale map (dengan `qr_rearmed`) atau null.
  Future<Map<String, dynamic>?> markReadyFromPendingRequest({
    required dynamic pendingRequestId,
    String? saleItemId,
  }) async {
    /// RO datang = barang ready: LUNAS PENDING_PO → SIAP_DIAMBIL (bukan
    /// menunggu admin Barang Ready seperti setelah pelunasan DP).
    Future<Map<String, dynamic>?> finish(String? sid) async {
      if (sid == null || sid.isEmpty) return null;
      final sale0 =
          await _db.from('sales').select().eq('id', sid).maybeSingle();
      if (sale0 == null) return null;
      final pay = ObrInvoice.normalizePayStatus(
        sale0['status_pembayaran']?.toString(),
      );
      final sisa = int.tryParse(sale0['sisa_tagihan']?.toString() ?? '0') ?? 0;
      final isDp = pay == 'DP' || sisa > 0;
      final t = (sale0['tracking_status'] ?? '').toString().trim().toUpperCase();

      if (!isDp && (t == 'PENDING_PO' || t.isEmpty)) {
        await _db.from('sales').update({
          'tracking_status': 'SIAP_DIAMBIL',
        }).eq('id', sid);
      } else if (isDp &&
          t != 'SIAP_PELUNASAN' &&
          t != 'SIAP_DIAMBIL' &&
          t != 'CLEAR') {
        // DP: RO ready → QR pelunasan (selaras admin Barang Ready DP).
        final existing = (sale0['qr_dp_token'] ?? '').toString().trim();
        final dpToken = (existing.length >= 8 && sale0['qr_dp_used_at'] == null)
            ? existing
            : InvoiceLifecycleService.newToken();
        await _db.from('sales').update({
          'tracking_status': 'SIAP_PELUNASAN',
          'qr_dp_token': dpToken,
          'qr_dp_used_at': null,
          'qr_dp_used_by': null,
        }).eq('id', sid);
        final updated =
            await _db.from('sales').select().eq('id', sid).maybeSingle();
        return {
          ...Map<String, dynamic>.from(updated ?? sale0),
          'qr_rearmed': true,
        };
      }

      await recomputeSale(sid);
      return ensurePickupQrIfReady(sid);
    }

    if (saleItemId != null && saleItemId.isNotEmpty) {
      await _db
          .from('sales_items')
          .update({
            'fulfillment_status': statusReady,
            'needs_fulfillment': false,
            'pending_request_id': pendingRequestId,
          })
          .eq('id', saleItemId)
          .neq('fulfillment_status', statusDiambil);
      final row = await _db
          .from('sales_items')
          .select('sale_id')
          .eq('id', saleItemId)
          .maybeSingle();
      return finish(row?['sale_id']?.toString());
    }

    final pr = await _db
        .from('pending_requests')
        .select('id, sale_id, sale_item_id')
        .eq('id', pendingRequestId)
        .maybeSingle();
    if (pr == null) return null;
    var itemId = pr['sale_item_id']?.toString();
    final saleId = pr['sale_id']?.toString();

    // Fallback: link lewat pending_request_id di sales_items.
    if (itemId == null || itemId.isEmpty) {
      final linked = await _db
          .from('sales_items')
          .select('id, sale_id')
          .eq('pending_request_id', pendingRequestId)
          .maybeSingle();
      itemId = linked?['id']?.toString();
      if (itemId != null && itemId.isNotEmpty) {
        await _db
            .from('sales_items')
            .update({
              'fulfillment_status': statusReady,
              'needs_fulfillment': false,
            })
            .eq('id', itemId)
            .neq('fulfillment_status', statusDiambil);
        return finish(
          saleId ?? linked?['sale_id']?.toString(),
        );
      }
      return null;
    }

    await _db
        .from('sales_items')
        .update({
          'fulfillment_status': statusReady,
          'needs_fulfillment': false,
          'pending_request_id': pendingRequestId,
        })
        .eq('id', itemId)
        .neq('fulfillment_status', statusDiambil);
    final sid = saleId ??
        (await _db
                .from('sales_items')
                .select('sale_id')
                .eq('id', itemId)
                .maybeSingle())?['sale_id']
            ?.toString();
    return finish(sid);
  }

  /// Kembalikan line ke READY (rollback serah terima gagal).
  Future<void> revertLinesToReady({
    required String saleId,
    required List<String> saleItemIds,
  }) async {
    final ids = saleItemIds.where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty) return;
    await _db.from('sales_items').update({
      'fulfillment_status': statusReady,
      'diambil_at': null,
    }).eq('sale_id', saleId).inFilter('id', ids);
    try {
      await recomputeSale(saleId);
    } catch (_) {}
  }

  /// Issue / refresh QR LUNAS when aggregate is SIAP_DIAMBIL.
  /// Return map sale + flag `qr_rearmed` bila token baru diterbitkan.
  Future<Map<String, dynamic>> ensurePickupQrIfReady(String saleId) async {
    final sale = await recomputeSale(saleId);
    final tracking =
        (sale['tracking_status'] ?? '').toString().trim().toUpperCase();
    final pay = ObrInvoice.normalizePayStatus(
      sale['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(sale['sisa_tagihan']?.toString() ?? '0') ?? 0;
    final isDp = pay == 'DP' || sisa > 0;
    if (isDp || tracking != 'SIAP_DIAMBIL' && tracking != 'CLEAR') {
      return {...sale, 'qr_rearmed': false};
    }
    // Re-arm LUNAS token if previous batch consumed and new READY exists
    final items = await listItems(saleId);
    final c = counts(items);
    if (c.ready <= 0) return {...sale, 'qr_rearmed': false};

    final used = sale['qr_lunas_used_at'] != null;
    final token = (sale['qr_lunas_token'] ?? '').toString().trim();
    if (!used && token.length >= 8) {
      return {...sale, 'qr_rearmed': false};
    }

    final newTok = InvoiceLifecycleService.newToken();
    await _db.from('sales').update({
      'qr_lunas_token': newTok,
      'qr_lunas_used_at': null,
      'qr_lunas_used_by': null,
      'tracking_status': 'SIAP_DIAMBIL',
    }).eq('id', saleId);
    final updated =
        await _db.from('sales').select().eq('id', saleId).maybeSingle();
    return {
      ...Map<String, dynamic>.from(updated ?? sale),
      'qr_rearmed': true,
    };
  }
}
