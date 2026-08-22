import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'product_identity.dart';
import 'stock_realtime.dart';
import 'write_off_rules.dart';

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
  /// Hold Member online checkout (15 menit) — sinkron reserved_qty.
  static const onlineHold = 'ONLINE_HOLD';
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
    if (reason == StockReason.writeOff) {
      throw 'Stok rusak hanya lewat write_off_stock.';
    }

    final toko = tokoId.trim().toUpperCase();
    final res = await _client.rpc('apply_stock_delta', params: {
      'p_toko': toko,
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
    final map = Map<String, dynamic>.from(res as Map);
    final stockAfter = int.tryParse(
      '${map['stock_after'] ?? map['real_stock'] ?? map['stock'] ?? ''}',
    );
    final pending = int.tryParse(
      '${map['pending_stock'] ?? map['reserved_qty'] ?? ''}',
    );
    final avail = int.tryParse('${map['available_qty'] ?? ''}') ??
        (stockAfter != null && pending != null
            ? StockQty.available(stockAfter, pending)
            : null);
    _pingRealtime(
      tokoId: toko,
      sku: normalized,
      stock: stockAfter,
      reservedQty: pending,
      availableQty: avail,
    );
    return map;
  }

  void _pingRealtime({
    required String tokoId,
    String? sku,
    int? stock,
    int? reservedQty,
    int? availableQty,
  }) {
    unawaited(StockRealtime.broadcastToko(
      tokoId: tokoId,
      sku: sku,
      stock: stock,
      reservedQty: reservedQty,
      availableQty: availableQty,
    ));
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

    final from = fromToko.trim().toUpperCase();
    final to = toToko.trim().toUpperCase();
    final res = await _client.rpc('apply_stock_transfer', params: {
      'p_from_toko': from,
      'p_to_toko': to,
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
    final map = Map<String, dynamic>.from(res as Map);
    _pingRealtime(tokoId: from, sku: normalized);
    _pingRealtime(tokoId: to, sku: normalized);
    return map;
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

    final toko = tokoId.trim().toUpperCase();
    final res = await _client.rpc('reserve_stock', params: {
      'p_toko': toko,
      'p_sku': normalized,
      'p_qty': qty,
      'p_kind': kind,
      'p_ref_type': refType,
      'p_ref_id': refId,
      'p_meta': meta ?? {},
    });
    final map = Map<String, dynamic>.from(res as Map);
    _pingRealtime(
      tokoId: toko,
      sku: normalized,
      stock: int.tryParse('${map['real_stock'] ?? ''}'),
      reservedQty: int.tryParse('${map['pending_stock'] ?? ''}'),
      availableQty: int.tryParse('${map['available_qty'] ?? ''}'),
    );
    return map;
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
    final map = Map<String, dynamic>.from(res as Map);
    if (tokoId != null && tokoId.trim().isNotEmpty) {
      _pingRealtime(tokoId: tokoId, sku: sku);
    }
    return map;
  }

  /// Hold stok ready keranjang POS (15 menit). Menurunkan available di semua saluran.
  Future<Map<String, dynamic>> holdPosCartStock({
    required String tokoId,
    required String refId,
    required List<Map<String, dynamic>> items,
    int holdMinutes = 15,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    final res = await _client.rpc('hold_pos_cart_stock', params: {
      'p_toko': toko,
      'p_ref_id': refId.trim(),
      'p_items': items,
      'p_hold_minutes': holdMinutes,
    });
    if (res is! Map) {
      return {'ok': false, 'error': 'Respons hold POS tidak valid'};
    }
    final map = Map<String, dynamic>.from(res);
    if (map['ok'] == true) {
      _pingRealtime(tokoId: toko);
      for (final it in items) {
        final sku = (it['sku'] ?? '').toString();
        if (sku.isNotEmpty) _pingRealtime(tokoId: toko, sku: sku);
      }
    }
    return map;
  }

  Future<Map<String, dynamic>> releasePosCartStock(
    String refId, {
    String? tokoId,
  }) async {
    final res = await _client.rpc('release_pos_cart_stock', params: {
      'p_ref_id': refId.trim(),
    });
    if (res is! Map) {
      return {'ok': false, 'error': 'Respons release POS tidak valid'};
    }
    final map = Map<String, dynamic>.from(res);
    if (tokoId != null && tokoId.trim().isNotEmpty) {
      _pingRealtime(tokoId: tokoId);
    }
    return map;
  }

  /// Consume POS_HOLD → SALE atomik (tanpa window available antar saluran).
  Future<Map<String, dynamic>> consumePosCartIntoSale({
    required String tokoId,
    required String refId,
    required List<Map<String, dynamic>> items,
    required String invoiceNo,
    String? actorNama,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    final res = await _client.rpc('consume_pos_cart_into_sale', params: {
      'p_toko': toko,
      'p_ref_id': refId.trim(),
      'p_items': items,
      'p_invoice': invoiceNo.trim(),
      'p_actor_id': _actorId,
      'p_actor_nama': actorNama ?? _actorEmail,
    });
    if (res is! Map) {
      return {'ok': false, 'error': 'Respons consume POS tidak valid'};
    }
    final map = Map<String, dynamic>.from(res);
    if (map['ok'] == true) {
      _pingRealtime(tokoId: toko);
      for (final it in items) {
        final sku = (it['sku'] ?? '').toString();
        if (sku.isNotEmpty) _pingRealtime(tokoId: toko, sku: sku);
      }
    }
    return map;
  }

  Future<int> expireStalePosHolds() async {
    final res = await _client.rpc('expire_stale_pos_holds');
    if (res is int) return res;
    return int.tryParse('$res') ?? 0;
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

  /// Kurangi stok rusak lewat RPC 000030 — bukan apply_stock_delta langsung.
  Future<Map<String, dynamic>> writeOff({
    required String tokoId,
    required String sku,
    required int qty,
    required String alasan,
    String? actorNama,
    String? refId,
    Map<String, dynamic>? meta,
  }) async {
    if (!WriteOffRules.qtyValid(qty)) {
      throw 'Qty rusak harus lebih dari 0.';
    }
    final alasanClean = alasan.trim();
    if (!WriteOffRules.alasanCukup(alasanClean)) {
      throw 'Alasan terlalu singkat (min. ${WriteOffRules.minAlasanChars} karakter).';
    }

    final toko = tokoId.trim().toUpperCase();
    final row = await ProductIdentity.findAtToko(
      tokoId: toko,
      sku: sku,
      barcode: sku,
      select: 'id, sku, barcode, nama, stock, reserved_qty, toko_id',
    );
    if (row == null) {
      throw 'Produk / SKU tidak ditemukan di $toko.';
    }

    final canonicalSku =
        ProductIdentity.normalizeSku(row['sku']) ?? sku.trim();
    final real = StockQty.realOf(row);
    final pending = StockQty.pendingOf(row);
    final available = StockQty.availableOf(row);
    if (available <= 0) {
      throw 'Tidak ada stok tersedia di $toko '
          '(real $real · booking $pending). '
          'Selesaikan paket Disiapkan / perjalanan dulu jika stok ter-booking.';
    }
    if (!WriteOffRules.tersediaCukup(
      real: real,
      reserved: pending,
      qty: qty,
    )) {
      throw 'Qty melebihi stok tersedia di $toko '
          '(real $real · booking $pending · tersedia $available · minta $qty).';
    }

    final woRef = (refId ?? '').trim().isNotEmpty
        ? refId!.trim()
        : 'WO-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final res = await _client.rpc('write_off_stock', params: {
        'p_toko': toko,
        'p_sku': canonicalSku,
        'p_qty': qty,
        'p_alasan': alasanClean,
        'p_actor_nama': actorNama ?? _actorEmail,
        'p_ref_id': woRef,
        'p_meta': {
          ...?meta,
          'nama': row['nama'],
          'stock_before': real,
          'pending_before': pending,
          'available_before': available,
        },
      });
      final map = Map<String, dynamic>.from(res as Map);
      final stockAfter = int.tryParse(
        '${map['stock_after'] ?? map['real_stock'] ?? map['stock'] ?? ''}',
      );
      final pendingAfter = int.tryParse(
        '${map['pending_stock'] ?? map['reserved_qty'] ?? ''}',
      );
      final avail = int.tryParse('${map['available_qty'] ?? ''}') ??
          (stockAfter != null && pendingAfter != null
              ? StockQty.available(stockAfter, pendingAfter)
              : null);
      _pingRealtime(
        tokoId: toko,
        sku: canonicalSku,
        stock: stockAfter,
        reservedQty: pendingAfter,
        availableQty: avail,
      );
      return map;
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal catat stok rusak.' : msg;
    }
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
    String? reason,
    int limit = 100,
  }) async {
    final filterSku = sku?.trim();
    final filterToko = tokoId?.trim().toUpperCase();
    final filterReason = reason?.trim().toUpperCase();

    var q = _client.from('product_stock_ledger').select();
    if (filterSku != null && filterSku.isNotEmpty) {
      q = q.eq('sku', filterSku);
    }
    if (filterToko != null && filterToko.isNotEmpty) {
      q = q.eq('toko_id', filterToko);
    }
    if (filterReason != null && filterReason.isNotEmpty) {
      q = q.eq('reason', filterReason);
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Riwayat write-off terbaru di toko (untuk UI Stok Rusak).
  Future<List<Map<String, dynamic>>> fetchWriteOffs({
    required String tokoId,
    int limit = 12,
  }) {
    return fetchLedger(
      tokoId: tokoId,
      reason: StockReason.writeOff,
      limit: limit,
    );
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
