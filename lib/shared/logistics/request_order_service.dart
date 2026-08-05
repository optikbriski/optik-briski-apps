import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/invoice_delivery_service.dart';
import '../invoice/sale_fulfillment_service.dart';
import 'product_identity.dart';
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

  static int? requestIdOf(Map<String, dynamic> req) {
    final v = req['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  static String tokoLabel(String? id) {
    final t = (id ?? '').trim().toUpperCase();
    if (t.isEmpty) return '-';
    if (t == 'PUSAT') return 'Pusat';
    if (t.startsWith('CABANG-')) return t.replaceFirst('CABANG-', '');
    return t;
  }

  Future<List<Map<String, dynamic>>> listByStatuses(List<String> statuses) async {
    final rows = await _client
        .from('pending_requests')
        .select()
        .inFilter('status', statuses)
        .order('created_at', ascending: true)
        .limit(300);
    return List<Map<String, dynamic>>.from(rows);
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
              'id, nama, sku, barcode, stock, reserved_qty, harga_jual, harga_modal, kategori, warna, toko_id')
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
      final own = (self?['reserved_qty'] as num?)?.toInt() ?? 0;
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

  Future<void> sendToHq(List<dynamic> ids) async {
    if (ids.isEmpty) return;
    await _client.from('pending_requests').update({
      'status': 'SENT_TO_HQ',
      'tracking_status': trackingFor('SENT_TO_HQ'),
    }).inFilter('id', ids);
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
    await sendToHq(ids);
    return ids.length;
  }

  Future<void> approve(Map<String, dynamic> req) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (status != 'SENT_TO_HQ' && status != 'PENDING') {
      throw 'Hanya request menunggu approval yang bisa disetujui.';
    }

    final qty = (req['qty_request'] as num?)?.toInt() ?? 0;
    if (qty <= 0) throw 'Qty request tidak valid.';

    final snap = await stockSnapshot(
      sku: req['sku']?.toString(),
      namaProduk: req['nama_produk']?.toString(),
      excludeRequestId: id,
    );
    if (snap.product == null) {
      throw 'Produk tidak ditemukan di stok Pusat.';
    }
    if (snap.available < qty) {
      throw 'Stok tersedia Pusat tidak cukup '
          '(stok ${snap.stock}, reservasi ${snap.reserved}, tersedia ${snap.available}, minta $qty).';
    }

    final userId = _client.auth.currentUser?.id;
    final sku = ProductIdentity.skuOf(snap.product!) ??
        ProductIdentity.normalizeSku(req['sku']);
    if (sku == null) {
      throw 'SKU produk wajib untuk reservasi RO.';
    }

    final mut = StockMutationService(client: _client);
    // Approve langsung masuk Disiapkan + reservasi aktif (Pending terpusat).
    await mut.reserve(
      tokoId: 'PUSAT',
      sku: sku,
      qty: qty,
      kind: StockReserveKind.ro,
      refType: 'pending_request',
      refId: id.toString(),
    );

    try {
      final updated = await _client
          .from('pending_requests')
          .update({
            'status': 'PREPARING',
            'tracking_status': trackingFor('PREPARING'),
            'reserved_qty': qty,
            'sku': sku,
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': userId,
          })
          .eq('id', id)
          .inFilter('status', ['SENT_TO_HQ', 'PENDING'])
          .select('id');
      if ((updated as List).isEmpty) {
        await mut.releaseReservation(
          kind: StockReserveKind.ro,
          refType: 'pending_request',
          refId: id.toString(),
          sku: sku,
          tokoId: 'PUSAT',
        );
        throw 'Request sudah diproses orang lain / status berubah.';
      }
    } catch (e) {
      // Lepas reservasi jika update gagal (kecuali sudah dilepas di cabang empty).
      final msg = e.toString();
      if (!msg.contains('sudah diproses')) {
        try {
          await mut.releaseReservation(
            kind: StockReserveKind.ro,
            refType: 'pending_request',
            refId: id.toString(),
            sku: sku,
            tokoId: 'PUSAT',
          );
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> reject(Map<String, dynamic> req, {String? note}) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (!const {
      'SENT_TO_HQ',
      'PENDING',
      'APPROVED',
      'PREPARING',
    }.contains(status)) {
      throw 'Status ini tidak bisa ditolak.';
    }

    final userId = _client.auth.currentUser?.id;
    await StockMutationService(client: _client).releaseReservation(
      kind: StockReserveKind.ro,
      refType: 'pending_request',
      refId: id.toString(),
      tokoId: 'PUSAT',
    );
    final updated = await _client
        .from('pending_requests')
        .update({
          'status': 'REJECTED',
          'tracking_status': trackingFor('REJECTED'),
          'reserved_qty': 0,
          'reviewed_at': DateTime.now().toIso8601String(),
          'reviewed_by': userId,
          if (note != null && note.trim().isNotEmpty) 'detail_resep': note.trim(),
        })
        .eq('id', id)
        .inFilter('status', const [
          'SENT_TO_HQ',
          'PENDING',
          'APPROVED',
          'PREPARING',
        ])
        .select('id');
    if ((updated as List).isEmpty) {
      throw 'Request tidak bisa ditolak — status sudah berubah.';
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
    final reserved = (req['reserved_qty'] as num?)?.toInt() ?? 0;
    final qty = (req['qty_request'] as num?)?.toInt() ?? 0;
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
    await _client.from('pending_requests').update({
      'status': 'PREPARING',
      'tracking_status': trackingFor('PREPARING'),
      'reserved_qty': hold,
      'sku': sku,
    }).eq('id', id).eq('status', 'APPROVED');
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
    await _client.from('pending_requests').update({
      'status': 'PREPARING',
      'tracking_status': trackingFor('PREPARING'),
    }).eq('status', 'APPROVED');
  }

  /// Potong stok Pusat (consume reservasi RO) + buat stock_move TRANSIT.
  Future<String> ship(
    Map<String, dynamic> req, {
    String? kurirKaryawanId,
    String? kurirNama,
  }) async {
    final id = requestIdOf(req);
    if (id == null) throw 'ID request tidak valid.';
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (status != 'PREPARING' && status != 'APPROVED') {
      throw 'Kirim hanya dari status Disiapkan.';
    }

    final qty = (req['qty_request'] as num?)?.toInt() ?? 0;
    if (qty <= 0) throw 'Qty tidak valid.';

    final tokoTujuan = req['toko_id']?.toString();
    if (tokoTujuan == null || tokoTujuan.isEmpty) {
      throw 'Toko tujuan kosong.';
    }

    final product = await findPusatProduct(
      sku: req['sku']?.toString(),
      namaProduk: req['nama_produk']?.toString(),
    );
    if (product == null) throw 'Produk tidak ditemukan di stok Pusat.';

    final sku = ProductIdentity.skuOf(product) ??
        ProductIdentity.normalizeSku(req['sku']);
    if (sku == null) {
      throw 'SKU produk wajib untuk kirim RO. Lengkapi di Master Produk.';
    }

    final realNow = StockQty.realOf(product);
    final pendingNow = StockQty.pendingOf(product);
    // Consume dulu melepas pending RO sendiri, lalu potong real — cek real >= qty.
    if (realNow < qty) {
      throw 'Stok real Pusat tidak cukup untuk dikirim '
          '(real $realNow, booking $pendingNow, minta $qty).';
    }

    final resi =
        'RO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final itemJson = jsonEncode([
      {
        'nama': product['nama'] ?? req['nama_produk'] ?? '-',
        'barcode': product['barcode'] ?? sku,
        'sku': sku,
        'qty': qty,
        'harga_jual': product['harga_jual'] ?? 0,
        'harga_modal': product['harga_modal'] ?? 0,
        'kategori': product['kategori'] ?? req['kategori'] ?? 'Lainnya',
        'warna': product['warna'] ?? '-',
      }
    ]);

    final kurirId = (kurirKaryawanId ?? '').trim();
    final kurirNm = (kurirNama ?? '').trim();
    final move = await _client
        .from('stock_move_history')
        .insert({
          'product_name': resi,
          'dari_lokasi': 'PUSAT',
          'ke_lokasi': tokoTujuan,
          'jumlah': qty,
          'tipe': 'REQUEST',
          'status': 'TRANSIT',
          'keterangan':
              'RequestOrder#$id | Invoice ${req['no_invoice'] ?? '-'} | $itemJson',
          'created_at': DateTime.now().toIso8601String(),
          if (kurirId.isNotEmpty) 'kurir_karyawan_id': kurirId,
          if (kurirNm.isNotEmpty) 'kurir_nama': kurirNm,
        })
        .select('id')
        .single();

    final mut = StockMutationService(client: _client);
    final moveId = move['id'].toString();
    try {
      // Atomik: consum reservasi RO + TRANSFER_OUT real (satu RPC).
      final consumed = await mut.consumeReservationAndShipOut(
        kind: StockReserveKind.ro,
        refType: 'pending_request',
        refId: id.toString(),
        tokoId: 'PUSAT',
        alasanText: 'Kirim RO $resi → $tokoTujuan',
        ledgerRefType: 'stock_move',
        ledgerRefId: moveId,
      );
      final items = consumed['items'];
      if (items is! List || items.isEmpty) {
        // Legacy APPROVED tanpa baris reservasi — fallback shipOut langsung.
        await mut.shipOut(
          fromToko: 'PUSAT',
          sku: sku,
          qty: qty,
          reason: StockReason.transferOut,
          alasanText: 'Kirim RO $resi → $tokoTujuan (tanpa reservasi)',
          refType: 'stock_move',
          refId: moveId,
        );
      }
    } catch (e) {
      await _client.from('stock_move_history').delete().eq('id', move['id']);
      rethrow;
    }

    final updated = await _client
        .from('pending_requests')
        .update({
          'status': 'SHIPPING',
          'tracking_status': trackingFor('SHIPPING'),
          'reserved_qty': 0,
          'stock_move_id': move['id'],
          'stock_move_resi': resi,
          'sku': sku,
        })
        .eq('id', id)
        .inFilter('status', ['PREPARING', 'APPROVED'])
        .select('id');
    if ((updated as List).isEmpty) {
      // Stok sudah terpotong — jangan rollback diam-diam; tandai error jelas.
      throw 'Stok sudah dipotong, tapi status RO gagal diubah. '
          'Cek resi $resi / move $moveId di Tracking & Verifikasi Terima.';
    }

    return resi;
  }

  Future<void> markSuccessFromMove({
    required String stockMoveId,
    String? resi,
  }) async {
    final successPatch = {
      'status': 'SUCCESS',
      'tracking_status': trackingFor('SUCCESS'),
      'reserved_qty': 0,
      'reviewed_at': DateTime.now().toIso8601String(),
    };

    final byId = await _client
        .from('pending_requests')
        .select('id, sale_item_id, sale_id')
        .eq('stock_move_id', stockMoveId)
        .eq('status', 'SHIPPING');
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
        .select('id, sale_item_id, sale_id')
        .eq('stock_move_resi', resiClean)
        .eq('status', 'SHIPPING');
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
}
