import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

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
        return 'PREPARING';
      case 'SHIPPING':
        return 'PENGIRIMAN';
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
        return 'Di cabang';
      case 'SENT_TO_HQ':
        return 'Menunggu approval';
      case 'APPROVED':
        return 'Disetujui';
      case 'PREPARING':
        return 'Preparing';
      case 'SHIPPING':
        return 'Pengiriman';
      case 'SUCCESS':
        return 'Selesai';
      case 'REJECTED':
        return 'Ditolak';
      default:
        return status ?? '-';
    }
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
    if (sku != null && sku.trim().isNotEmpty && sku != 'No SKU') {
      final bySku = await _client
          .from('products')
          .select(
              'id, nama, sku, barcode, stock, harga_jual, harga_modal, kategori, warna')
          .eq('toko_id', 'PUSAT')
          .eq('sku', sku.trim())
          .maybeSingle();
      if (bySku != null) return Map<String, dynamic>.from(bySku);
    }
    if (namaProduk != null && namaProduk.trim().isNotEmpty) {
      final byNama = await _client
          .from('products')
          .select(
              'id, nama, sku, barcode, stock, harga_jual, harga_modal, kategori, warna')
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
    var q = _client
        .from('pending_requests')
        .select('id, reserved_qty, sku, nama_produk, status')
        .inFilter('status', reserveStatuses)
        .gt('reserved_qty', 0);

    if (sku != null && sku.trim().isNotEmpty && sku != 'No SKU') {
      q = q.eq('sku', sku.trim());
    } else if (namaProduk != null && namaProduk.trim().isNotEmpty) {
      q = q.ilike('nama_produk', namaProduk.trim());
    } else {
      return 0;
    }

    final rows = await q;
    var total = 0;
    for (final r in rows as List) {
      if (excludeRequestId != null && r['id'] == excludeRequestId) continue;
      total += (r['reserved_qty'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// Stok fisik Pusat, reserved aktif, dan available untuk approve.
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
    final stock = int.tryParse(product?['stock']?.toString() ?? '0') ?? 0;
    final reserved = await reservedQtyFor(
      sku: sku ?? product?['sku']?.toString(),
      namaProduk: namaProduk ?? product?['nama']?.toString(),
      excludeRequestId: excludeRequestId,
    );
    final available = stock - reserved;
    return (
      stock: stock,
      reserved: reserved,
      available: available < 0 ? 0 : available,
      product: product,
    );
  }

  Future<void> sendToHq(List<int> ids) async {
    if (ids.isEmpty) return;
    await _client.from('pending_requests').update({
      'status': 'SENT_TO_HQ',
      'tracking_status': trackingFor('SENT_TO_HQ'),
    }).inFilter('id', ids);
  }

  Future<void> approve(Map<String, dynamic> req) async {
    final id = req['id'] as int;
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
    // Approve langsung masuk Preparing + reservasi aktif.
    await _client.from('pending_requests').update({
      'status': 'PREPARING',
      'tracking_status': trackingFor('PREPARING'),
      'reserved_qty': qty,
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': userId,
    }).eq('id', id).inFilter('status', ['SENT_TO_HQ', 'PENDING']);
  }

  Future<void> reject(Map<String, dynamic> req, {String? note}) async {
    final id = req['id'] as int;
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
    await _client.from('pending_requests').update({
      'status': 'REJECTED',
      'tracking_status': trackingFor('REJECTED'),
      'reserved_qty': 0,
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': userId,
      if (note != null && note.trim().isNotEmpty) 'detail_resep': note.trim(),
    }).eq('id', id);
  }

  /// Legacy: data lama status APPROVED digeser ke PREPARING.
  Future<void> toPreparing(Map<String, dynamic> req) async {
    final id = req['id'] as int;
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (status != 'APPROVED') {
      throw 'Request sudah di tahap Preparing atau selesai.';
    }
    final reserved = (req['reserved_qty'] as num?)?.toInt() ?? 0;
    final qty = (req['qty_request'] as num?)?.toInt() ?? 0;
    await _client.from('pending_requests').update({
      'status': 'PREPARING',
      'tracking_status': trackingFor('PREPARING'),
      'reserved_qty': reserved > 0 ? reserved : qty,
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

  /// Potong stok Pusat + buat stock_move TRANSIT + lepas reservasi.
  Future<String> ship(Map<String, dynamic> req) async {
    final id = req['id'] as int;
    final status = (req['status'] ?? '').toString().toUpperCase();
    if (status != 'PREPARING' && status != 'APPROVED') {
      throw 'Shipping hanya dari Preparing.';
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

    final stockNow = int.tryParse(product['stock']?.toString() ?? '0') ?? 0;
    if (stockNow < qty) {
      throw 'Stok fisik Pusat tidak cukup untuk shipping '
          '(stok $stockNow, minta $qty).';
    }

    await _client
        .from('products')
        .update({'stock': stockNow - qty}).eq('id', product['id']);

    final resi =
        'RO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final itemJson = jsonEncode([
      {
        'nama': product['nama'] ?? req['nama_produk'] ?? '-',
        'barcode': product['barcode'] ?? '-',
        'sku': product['sku'] ?? req['sku'],
        'qty': qty,
        'harga_jual': product['harga_jual'] ?? 0,
        'harga_modal': product['harga_modal'] ?? 0,
        'kategori': product['kategori'] ?? req['kategori'] ?? 'Lainnya',
        'warna': product['warna'] ?? '-',
      }
    ]);

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
        })
        .select('id')
        .single();

    await _client.from('pending_requests').update({
      'status': 'SHIPPING',
      'tracking_status': trackingFor('SHIPPING'),
      'reserved_qty': 0,
      'stock_move_id': move['id'],
      'stock_move_resi': resi,
    }).eq('id', id);

    return resi;
  }

  Future<void> markSuccessFromMove({
    required String stockMoveId,
    String? resi,
  }) async {
    final byId = await _client
        .from('pending_requests')
        .select('id')
        .eq('stock_move_id', stockMoveId)
        .eq('status', 'SHIPPING');
    if ((byId as List).isNotEmpty) {
      await _client.from('pending_requests').update({
        'status': 'SUCCESS',
        'tracking_status': trackingFor('SUCCESS'),
        'reserved_qty': 0,
      }).eq('stock_move_id', stockMoveId);
      return;
    }

    if (resi != null && resi.isNotEmpty) {
      await _client.from('pending_requests').update({
        'status': 'SUCCESS',
        'tracking_status': trackingFor('SUCCESS'),
        'reserved_qty': 0,
      }).eq('stock_move_resi', resi).eq('status', 'SHIPPING');
    }
  }
}
