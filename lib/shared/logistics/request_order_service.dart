import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/invoice_delivery_service.dart';
import '../invoice/sale_fulfillment_service.dart';
import 'product_identity.dart';
import 'receive_verification_rules.dart';
import 'request_order_rules.dart';
import 'stock_mutation_service.dart';

/// Pipeline RO Pusat: Approve → Preparing → Shipping → Success
/// dengan reservasi stok (PREPARING) sebelum potong fisik.
class RequestOrderService {
  RequestOrderService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const reserveStatuses = ['APPROVED', 'PREPARING'];

  static String trackingFor(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'DIPROSES_DI_CABANG';
      case 'SENT_TO_HQ':
        return 'MENUNGGU_APPROVAL';
      case 'APPROVED':
        return 'DISETUJUI';
      case 'PREPARING':
        return 'DISIAPKAN';
      case 'SHIPPING':
        return 'DALAM_PERJALANAN';
      case 'SUCCESS':
        return 'SELESAI';
      case 'REJECTED':
        return 'DITOLAK';
      default:
        return status;
    }
  }

  static String labelStatus(String? status) {
    switch ((status ?? '').toUpperCase()) {
      case 'PENDING':
        return 'Antrian cabang';
      case 'SENT_TO_HQ':
        return 'Menunggu approval';
      case 'APPROVED':
        return 'Disetujui';
      case 'PREPARING':
        return 'Disiapkan';
      case 'SHIPPING':
        return 'Dalam perjalanan';
      case 'SUCCESS':
        return 'Diterima';
      case 'REJECTED':
        return 'Ditolak';
      default:
        return status ?? '-';
    }
  }

  static int? requestIdOf(Map<String, dynamic> req) =>
      RequestOrderRules.idOf(req['id']);

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  Future<List<Map<String, dynamic>>> _mapsFromRpc(
    String name,
    Map<String, dynamic> params,
  ) async {
    final raw = await _client.rpc(name, params: params);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String tokoLabel(String? id) {
    final t = (id ?? '').trim().toUpperCase();
    if (t.isEmpty) return '-';
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  Future<List<Map<String, dynamic>>> listByStatuses(
    List<String> statuses, {
    String? tokoId,
  }) async {
    final wanted = statuses
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();
    if (wanted.isEmpty) return const [];
    try {
      return await _mapsFromRpc('list_request_orders', {
        'p_toko': (tokoId ?? '').trim().isEmpty
            ? null
            : tokoId!.trim().toUpperCase(),
        'p_statuses': wanted,
      });
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) rethrow;
    }
    return _restListByStatuses(wanted, tokoId: tokoId);
  }

  Future<List<Map<String, dynamic>>> _restListByStatuses(
    List<String> statuses, {
    String? tokoId,
  }) async {
    final byId = <String, Map<String, dynamic>>{};
    var offset = 0;
    const pageSize = 500;
    final toko = (tokoId ?? '').trim().toUpperCase();
    while (true) {
      var q = _client
          .from('pending_requests')
          .select()
          .inFilter('status', statuses);
      if (toko.isNotEmpty) q = q.eq('toko_id', toko);
      final chunk = await q
          .order('created_at', ascending: true)
          .range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(chunk as List);
      if (rows.isEmpty) break;
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = r;
      }
      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset > 8000) break;
    }
    return byId.values.toList()
      ..sort((a, b) {
        final aa = (a['created_at'] ?? '').toString();
        final bb = (b['created_at'] ?? '').toString();
        return aa.compareTo(bb);
      });
  }

  /// PENDING cabang untuk hari lokal device.
  Future<List<Map<String, dynamic>>> listTodayPending({
    required String tokoId,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) return const [];
    final bounds = localDayBoundsUtc();
    final rows = await listByStatuses(['PENDING'], tokoId: toko);
    return rows.where((r) {
      final raw = r['created_at']?.toString();
      final at = DateTime.tryParse(raw ?? '')?.toUtc();
      if (at == null) return false;
      return !at.isBefore(bounds.startUtc) &&
          at.isBefore(bounds.endExclusiveUtc);
    }).toList();
  }

  Future<Map<String, dynamic>?> findPusatProduct({
    String? sku,
    String? namaProduk,
  }) async {
    final found = await ProductIdentity.findPusat(sku: sku);
    if (found != null) return found;
    // Nama hanya sebagai fallback lookup (bukan untuk mutasi tanpa SKU).
    if (namaProduk != null && namaProduk.trim().isNotEmpty) {
      final byNama = await _client
          .from('products')
          .select(
              'id, nama, sku, barcode, stock, reserved_qty, harga, harga_jual, harga_modal, kategori, warna, toko_id, image_url, foto_url')
          .eq('toko_id', 'PUSAT')
          .ilike('nama', namaProduk.trim())
          .maybeSingle();
      if (byNama != null) return Map<String, dynamic>.from(byNama);
    }
    return null;
  }

  Future<int> reservedQtyFor({
    String? sku,
    String? namaProduk,
    int? excludeRequestId,
  }) async {
    // Pending terpusat di products.reserved_qty; RO rows masih dihitung
    // jika excludeRequestId (saat approve sendiri) supaya available akurat.
    final product = await findPusatProduct(sku: sku, namaProduk: namaProduk);
    var total = StockQty.pendingOf(product);
    if (excludeRequestId != null) {
      final self = await _client
          .from('pending_requests')
          .select('reserved_qty')
          .eq('id', excludeRequestId)
          .maybeSingle();
      final own = RequestOrderRules.qtyOf(self?['reserved_qty']);
      total = (total - own).clamp(0, 1 << 30);
    }
    return total;
  }

  /// Real / Pending / Available Pusat untuk approve.
  Future<
      ({
        int stock,
        int reserved,
        int available,
        Map<String, dynamic>? product
      })> stockSnapshot({
    String? sku,
    String? namaProduk,
    int? excludeRequestId,
  }) async {
    final product = await findPusatProduct(sku: sku, namaProduk: namaProduk);
    final stock = StockQty.realOf(product);
    final reserved = await reservedQtyFor(
      sku: sku ?? product?['sku']?.toString(),
      namaProduk: namaProduk ?? product?['nama']?.toString(),
      excludeRequestId: excludeRequestId,
    );
    final available = StockQty.available(stock, reserved);
    return (
      stock: stock,
      reserved: reserved,
      available: available,
      product: product,
    );
  }

  Future<void> sendToHq(List<dynamic> ids, {required String tokoId}) async {
    if (ids.isEmpty) return;
    final parsed = <int>[];
    for (final raw in ids) {
      final n = RequestOrderRules.idOf(raw);
      if (n != null) parsed.add(n);
    }
    if (parsed.isEmpty) return;
    try {
      await _client.rpc('send_request_orders_to_hq', params: {
        'p_toko': tokoId.trim().toUpperCase(),
        'p_ids': parsed,
      });
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal kirim RO ke Pusat.' : msg;
    }
  }

  /// Batas hari lokal (WIB/device) untuk antrian RO "hari ini".
  static ({DateTime startUtc, DateTime endExclusiveUtc}) localDayBoundsUtc(
      [DateTime? nowLocal]) {
    final n = nowLocal ?? DateTime.now();
    final startLocal = DateTime(n.year, n.month, n.day);
    final endLocal = startLocal.add(const Duration(days: 1));
    return (startUtc: startLocal.toUtc(), endExclusiveUtc: endLocal.toUtc());
  }

  /// Failsafe EOD: kirim semua PENDING cabang untuk hari lokal ini ke pusat.
  /// Dipakai tombol manual + auto jam ≥ 23:59.
  Future<int> autoSendTodayPendingToHq(String tokoId) async {
    final tid = tokoId.trim();
    if (tid.isEmpty) return 0;
    final bounds = localDayBoundsUtc();
    final rows = await _client
        .from('pending_requests')
        .select('id')
        .eq('toko_id', tid)
        .eq('status', 'PENDING')
        .gte('created_at', bounds.startUtc.toIso8601String())
        .lt('created_at', bounds.endExclusiveUtc.toIso8601String());
    final ids = (rows as List)
        .map((e) => (e as Map)['id'])
        .whereType<Object>()
        .toList();
    if (ids.isEmpty) return 0;
    await sendToHq(ids, tokoId: tid);
    return ids.length;
  }

  Future<void> approve(Map<String, dynamic> req) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    try {
      await _client.rpc('approve_request_order', params: {'p_id': id});
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal setujui RO.' : msg;
    }
  }

  Future<void> reject(Map<String, dynamic> req, {String? note}) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    try {
      await _client.rpc('reject_request_order', params: {
        'p_id': id,
        'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      });
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal tolak RO.' : msg;
    }
  }

  /// Legacy: data lama status APPROVED digeser ke PREPARING.
  Future<void> toPreparing(Map<String, dynamic> req) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (status != 'APPROVED') {
      throw 'Request sudah di tahap Preparing atau selesai.';
    }
    final reserved = RequestOrderRules.qtyOf(req['reserved_qty']);
    final qty = RequestOrderRules.qtyOf(req['qty_request']);
    final hold = reserved > 0 ? reserved : qty;
    final product = await findPusatProduct(
      sku: req['sku']?.toString(),
      namaProduk: req['nama_produk']?.toString(),
    );
    final sku =
        ProductIdentity.normalizeSku(req['sku']) ?? ProductIdentity.skuOf(product ?? {});
    if (sku == null || hold <= 0) {
      throw 'SKU / qty tidak valid untuk Preparing RO.';
    }
    await StockMutationService(client: _client).reserve(
      tokoId: 'PUSAT',
      sku: sku,
      qty: hold,
      kind: StockReserveKind.ro,
      refType: 'pending_request',
      refId: id.toString(),
    );
    await approve(req);
  }

  Future<List<Map<String, dynamic>>> listHistory({
    int limit = 400,
    DateTime? from,
    DateTime? to,
    List<String>? tokoIds,
  }) async {
    var q = _client
        .from('pending_requests')
        .select()
        .inFilter('status', ['SUCCESS', 'REJECTED']);

    if (from != null) {
      final start = DateTime(from.year, from.month, from.day);
      q = q.gte('created_at', start.toUtc().toIso8601String());
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      q = q.lte('created_at', end.toUtc().toIso8601String());
    }
    if (tokoIds != null && tokoIds.isNotEmpty) {
      q = q.inFilter('toko_id', tokoIds);
    }

    final rows = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listTokoOptions() async {
    final rows = await _client.from('toko_id').select('id, toko_id').order('id');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Geser data lama APPROVED → PREPARING (tab Approved dihapus).
  Future<void> migrateLegacyApproved() async {
    final rows = await listByStatuses(['APPROVED']);
    for (final req in rows) {
      try {
        await approve(req);
      } catch (_) {}
    }
  }

  /// Potong stok Pusat (consume reservasi RO) + buat stock_move TRANSIT.
  Future<String> ship(
    Map<String, dynamic> req, {
    String? kurirKaryawanId,
    String? kurirNama,
  }) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    try {
      final res = await _client.rpc('ship_request_order', params: {
        'p_id': id,
        'p_kurir_id': (kurirKaryawanId ?? '').trim().isEmpty
            ? null
            : kurirKaryawanId!.trim(),
        'p_kurir_nama':
            (kurirNama ?? '').trim().isEmpty ? null : kurirNama!.trim(),
      });
      final map = _rpcMap('ship_request_order', res);
      final resi = (map['resi'] ?? '').toString().trim();
      if (resi.isEmpty) throw 'Gagal kirim RO.';
      return resi;
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal kirim RO.' : msg;
    }
  }

  Future<void> markSuccessFromMove({
    required String stockMoveId,
    String? resi,
  }) async {
    final move = await _client
        .from('stock_move_history')
        .select('status')
        .eq('id', stockMoveId)
        .maybeSingle();
    final moveStatus = (move?['status'] ?? '').toString();
    if (!ReceiveVerificationRules.canCloseRoFromMove(moveStatus)) {
      throw 'RO hanya boleh ditutup setelah surat jalan diterima.';
    }

    final successPatch = {
      'status': 'SUCCESS',
      'tracking_status': trackingFor('SUCCESS'),
      'reserved_qty': 0,
      'reviewed_at': DateTime.now().toIso8601String(),
    };

    final byId = await _client
        .from('pending_requests')
        .select('id, sale_item_id, sale_id, status')
        .eq('stock_move_id', stockMoveId)
        .inFilter('status', ['SHIPPING', 'SUCCESS']);
    if ((byId as List).isNotEmpty) {
      await _client
          .from('pending_requests')
          .update(successPatch)
          .eq('stock_move_id', stockMoveId)
          .eq('status', 'SHIPPING');
      await _syncSaleItemsReadyFromRequests(
        byId.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      );
      return;
    }

    final resiClean = (resi ?? '').trim();
    if (resiClean.isEmpty) return;

    final byResi = await _client
        .from('pending_requests')
        .select('id, sale_item_id, sale_id, status')
        .eq('stock_move_resi', resiClean)
        .inFilter('status', ['SHIPPING', 'SUCCESS']);
    if ((byResi as List).isEmpty) return;

    await _client
        .from('pending_requests')
        .update(successPatch)
        .eq('stock_move_resi', resiClean)
        .eq('status', 'SHIPPING');
    await _syncSaleItemsReadyFromRequests(
      byResi.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  /// RO SUCCESS → sales_items READY + re-arm QR + kirim ke pelanggan.
  Future<void> _syncSaleItemsReadyFromRequests(
    List<Map<String, dynamic>> rows,
  ) async {
    final fulfill = SaleFulfillmentService(client: _client);
    final deliveredSaleIds = <String>{};
    for (final row in rows) {
      try {
        final sale = await fulfill.markReadyFromPendingRequest(
          pendingRequestId: row['id'],
          saleItemId: row['sale_item_id']?.toString(),
        );
        if (sale == null) {
          // ignore: avoid_print
          print(
            'RO SUCCESS: tidak ada sales_item untuk PR ${row['id']} '
            '(sale_item_id=${row['sale_item_id']}). Link POS saat checkout.',
          );
          continue;
        }
        if (sale['qr_rearmed'] != true) continue;
        final sid = sale['id']?.toString() ?? '';
        if (sid.isEmpty || deliveredSaleIds.contains(sid)) continue;
        deliveredSaleIds.add(sid);
        try {
          await InvoiceDeliveryService(client: _client).deliver(
            sale: sale,
            mode: InvoiceDeliveryMode.goodsReady,
          );
        } catch (_) {}
      } catch (e) {
        // ignore: avoid_print
        print('RO SUCCESS sync line/QR gagal PR ${row['id']}: $e');
      }
    }
  }

  static Map<String, dynamic> _rpcMap(String rpc, dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw 'Respon $rpc tidak valid.';
  }
}
