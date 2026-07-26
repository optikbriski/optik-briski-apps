import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_identity.dart';

/// Reasons allowed by SQL `product_stock_ledger`.
abstract final class StockReason {
  static const opening = 'OPENING';
  static const transferOut = 'TRANSFER_OUT';
  static const transferIn = 'TRANSFER_IN';
  static const returnOut = 'RETURN_OUT';
  static const returnIn = 'RETURN_IN';
  static const sale = 'SALE';
  static const writeOff = 'WRITE_OFF';
  static const adjust = 'ADJUST';
}

/// Reservation kinds for stok PENDING (bayangan).
abstract final class StockReserveKind {
  static const doDraft = 'DO_DRAFT';
  static const doPreparing = 'DO_PREPARING';
  static const ro = 'RO';
  static const posHold = 'POS_HOLD';
}

/// Real / Pending / Available helpers.
abstract final class StockQty {
  static int realOf(Map<String, dynamic>? row) =>
      int.tryParse(row?['stock']?.toString() ?? '0') ?? 0;

  static int pendingOf(Map<String, dynamic>? row) =>
      int.tryParse(row?['reserved_qty']?.toString() ?? '0') ?? 0;

  /// Total tersedia untuk dijual = Real − Pending.
  static int availableOf(Map<String, dynamic>? row) {
    final a = realOf(row) - pendingOf(row);
    return a < 0 ? 0 : a;
  }

  static int available(int real, int pending) {
    final a = real - pending;
    return a < 0 ? 0 : a;
  }
}

/// All stock changes go through Supabase RPCs (ledger + atomic update).
class StockMutationService {
  StockMutationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _actorId => _client.auth.currentUser?.id;
  String? get _actorEmail => _client.auth.currentUser?.email;

  Future<Map<String, dynamic>> applyDelta({
    required String tokoId,
    required String sku,
    required int qtyDelta,
    required String reason,
    String? alasanText,
    String? refType,
    String? refId,
    String? actorNama,
    Map<String, dynamic>? meta,
    bool allowCreate = true,
  }) async {
    final normalized = ProductIdentity.normalizeSku(sku);
    if (normalized == null) {
      throw 'SKU wajib untuk mutasi stok.';
    }
    if (qtyDelta == 0) throw 'qty_delta tidak boleh 0.';

    final res = await _client.rpc('apply_stock_delta', params: {
      'p_toko': tokoId.trim().toUpperCase(),
      'p_sku': normalized,
      'p_qty_delta': qtyDelta,
      'p_reason': reason,
      'p_alasan_text': alasanText,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_actor_id': _actorId,
      'p_actor_nama': actorNama ?? _actorEmail,
      'p_meta': meta ?? {},
      'p_allow_create': allowCreate,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Balanced move: from −qty and to +qty in one DB transaction.
  Future<Map<String, dynamic>> transfer({
    required String fromToko,
    required String toToko,
    required String sku,
    required int qty,
    String reasonOut = StockReason.transferOut,
    String reasonIn = StockReason.transferIn,
    String? alasanText,
    String? refType,
    String? refId,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) async {
    final normalized = ProductIdentity.normalizeSku(sku);
    if (normalized == null) throw 'SKU wajib untuk transfer stok.';
    if (qty <= 0) throw 'Qty transfer harus > 0.';

    final res = await _client.rpc('apply_stock_transfer', params: {
      'p_from_toko': fromToko.trim().toUpperCase(),
      'p_to_toko': toToko.trim().toUpperCase(),
      'p_sku': normalized,
      'p_qty': qty,
      'p_reason_out': reasonOut,
      'p_reason_in': reasonIn,
      'p_alasan_text': alasanText,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_actor_id': _actorId,
      'p_actor_nama': actorNama ?? _actorEmail,
      'p_meta': meta ?? {},
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Book PENDING stock (does not change Real `stock`).
  Future<Map<String, dynamic>> reserve({
    required String tokoId,
    required String sku,
    required int qty,
    required String kind,
    required String refType,
    required String refId,
    Map<String, dynamic>? meta,
  }) async {
    final normalized = ProductIdentity.normalizeSku(sku);
    if (normalized == null) throw 'SKU wajib untuk reservasi stok.';
    if (qty <= 0) throw 'Qty reservasi harus > 0.';

    final res = await _client.rpc('reserve_stock', params: {
      'p_toko': tokoId.trim().toUpperCase(),
      'p_sku': normalized,
      'p_qty': qty,
      'p_kind': kind,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_meta': meta ?? {},
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> releaseReservation({
    required String kind,
    required String refType,
    required String refId,
    String? sku,
    String? tokoId,
  }) async {
    final res = await _client.rpc('release_reservation', params: {
      'p_kind': kind,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_sku': sku,
      'p_toko': tokoId?.trim().toUpperCase(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// PREPARING/draft → TRANSIT: clear PENDING then cut Real via TRANSFER_OUT.
  Future<Map<String, dynamic>> consumeReservationAndShipOut({
    required String kind,
    required String refType,
    required String refId,
    required String tokoId,
    String? alasanText,
    String? actorNama,
    String? ledgerRefType,
    String? ledgerRefId,
  }) async {
    final res = await _client.rpc(
      'consume_reservation_and_transfer_out',
      params: {
        'p_kind': kind,
        'p_ref_type': refType,
        'p_ref_id': refId,
        'p_toko': tokoId.trim().toUpperCase(),
        'p_alasan_text': alasanText,
        'p_actor_id': _actorId,
        'p_actor_nama': actorNama ?? _actorEmail,
        'p_ledger_ref_type': ledgerRefType,
        'p_ledger_ref_id': ledgerRefId,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Ship / leave source (stock in transit): only −from.
  Future<Map<String, dynamic>> shipOut({
    required String fromToko,
    required String sku,
    required int qty,
    String reason = StockReason.transferOut,
    String? alasanText,
    String? refType,
    String? refId,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) {
    return applyDelta(
      tokoId: fromToko,
      sku: sku,
      qtyDelta: -qty,
      reason: reason,
      alasanText: alasanText,
      refType: refType,
      refId: refId,
      actorNama: actorNama,
      meta: meta,
      allowCreate: false,
    );
  }

  /// Receive at destination: only +to (creates row from master if needed).
  Future<Map<String, dynamic>> receiveIn({
    required String toToko,
    required String sku,
    required int qty,
    String reason = StockReason.transferIn,
    String? alasanText,
    String? refType,
    String? refId,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) {
    return applyDelta(
      tokoId: toToko,
      sku: sku,
      qtyDelta: qty,
      reason: reason,
      alasanText: alasanText,
      refType: refType,
      refId: refId,
      actorNama: actorNama,
      meta: meta,
      allowCreate: true,
    );
  }

  Future<Map<String, dynamic>> sale({
    required String tokoId,
    required String sku,
    required int qty,
    required String invoiceNo,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) {
    if (qty <= 0) throw 'Qty jual harus > 0.';
    return applyDelta(
      tokoId: tokoId,
      sku: sku,
      qtyDelta: -qty,
      reason: StockReason.sale,
      alasanText: 'Penjualan POS $invoiceNo',
      refType: 'sale',
      refId: invoiceNo,
      actorNama: actorNama,
      meta: meta,
      allowCreate: false,
    );
  }

  Future<Map<String, dynamic>> writeOff({
    required String tokoId,
    required String sku,
    required int qty,
    required String alasan,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) {
    if (qty <= 0) throw 'Qty rusak harus > 0.';
    if (alasan.trim().isEmpty) throw 'Alasan rusak wajib diisi.';
    return applyDelta(
      tokoId: tokoId,
      sku: sku,
      qtyDelta: -qty,
      reason: StockReason.writeOff,
      alasanText: alasan.trim(),
      refType: 'write_off',
      actorNama: actorNama,
      meta: meta,
      allowCreate: false,
    );
  }

  /// Revisi stok (stock opname / koreksi): set ke [newStock], delta dihitung otomatis.
  Future<Map<String, dynamic>> reviseTo({
    required String tokoId,
    required String sku,
    required int newStock,
    required String alasan,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) async {
    if (newStock < 0) throw 'Stok baru tidak boleh negatif.';
    if (alasan.trim().isEmpty) throw 'Alasan revisi wajib diisi.';

    final row = await ProductIdentity.findAtToko(
      tokoId: tokoId,
      sku: sku,
      barcode: sku,
    );
    if (row == null) throw 'Produk $sku tidak ada di $tokoId.';
    final current = int.tryParse(row['stock']?.toString() ?? '0') ?? 0;
    final delta = newStock - current;
    if (delta == 0) {
      throw 'Stok sudah $current — tidak ada yang diubah.';
    }

    return applyDelta(
      tokoId: tokoId,
      sku: ProductIdentity.normalizeSku(row['sku']) ?? sku,
      qtyDelta: delta,
      reason: StockReason.adjust,
      alasanText: 'Revisi stok $current → $newStock: ${alasan.trim()}',
      refType: 'stock_revise',
      actorNama: actorNama,
      meta: {
        ...?meta,
        'stock_before': current,
        'stock_after_target': newStock,
      },
      allowCreate: false,
    );
  }

  Future<Map<String, dynamic>> opening({
    required String tokoId,
    required String sku,
    required int qty,
    String? actorNama,
    Map<String, dynamic>? meta,
  }) {
    if (qty <= 0) throw 'Qty opening harus > 0.';
    return applyDelta(
      tokoId: tokoId,
      sku: sku,
      qtyDelta: qty,
      reason: StockReason.opening,
      alasanText: 'Saldo awal / create produk',
      refType: 'opening',
      actorNama: actorNama,
      meta: meta,
      allowCreate: true,
    );
  }

  Future<List<Map<String, dynamic>>> fetchLedger({
    String? sku,
    String? tokoId,
    int limit = 100,
  }) async {
    final filterSku = sku?.trim();
    final filterToko = tokoId?.trim().toUpperCase();
    late final List rows;
    if (filterSku != null &&
        filterSku.isNotEmpty &&
        filterToko != null &&
        filterToko.isNotEmpty) {
      rows = await _client
          .from('product_stock_ledger')
          .select()
          .eq('sku', filterSku)
          .eq('toko_id', filterToko)
          .order('created_at', ascending: false)
          .limit(limit);
    } else if (filterSku != null && filterSku.isNotEmpty) {
      rows = await _client
          .from('product_stock_ledger')
          .select()
          .eq('sku', filterSku)
          .order('created_at', ascending: false)
          .limit(limit);
    } else if (filterToko != null && filterToko.isNotEmpty) {
      rows = await _client
          .from('product_stock_ledger')
          .select()
          .eq('toko_id', filterToko)
          .order('created_at', ascending: false)
          .limit(limit);
    } else {
      rows = await _client
          .from('product_stock_ledger')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
    }
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Inject stock lines from stock_move `keterangan` JSON (SKU-first).
  Future<void> receiveItemsFromMoveKeterangan({
    required String tokoId,
    required String keterangan,
    required int jumlahFlat,
    required String reason,
    String? refType,
    String? refId,
    String? actorNama,
    bool isReturn = false,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    final inReason = isReturn ? StockReason.returnIn : reason;
    final items = _parseItems(keterangan);
    if (items.isNotEmpty) {
      for (final itm in items) {
        final qty = int.tryParse(itm['qty']?.toString() ?? '0') ?? 0;
        if (qty <= 0) continue;
        final sku = ProductIdentity.skuOf(itm);
        if (sku == null) {
          throw 'Item tanpa SKU tidak bisa diterima: ${itm['nama'] ?? '-'}';
        }
        await receiveIn(
          toToko: toko,
          sku: sku,
          qty: qty,
          reason: inReason,
          alasanText: isReturn ? 'Terima retur' : 'Terima kiriman',
          refType: refType,
          refId: refId,
          actorNama: actorNama,
          meta: {
            'product': {
              'nama': itm['nama'],
              'barcode': itm['barcode'],
              'harga': itm['harga_jual'] ?? itm['harga'],
              'harga_jual': itm['harga_jual'] ?? itm['harga'],
              'harga_modal': itm['harga_modal'],
              'kategori': itm['kategori'],
              'warna': itm['warna'],
            },
          },
        );
      }
      return;
    }
    if (jumlahFlat > 0) {
      throw 'Paket tanpa detail SKU tidak bisa diterima (qty $jumlahFlat).';
    }
  }

  List<Map<String, dynamic>> _parseItems(String keterangan) {
    if (!keterangan.contains('[{')) return const [];
    try {
      final jsonPart = keterangan.substring(keterangan.indexOf('[{'));
      final decoded = jsonDecode(jsonPart);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
