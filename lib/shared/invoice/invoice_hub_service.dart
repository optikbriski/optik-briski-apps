import 'package:supabase_flutter/supabase_flutter.dart';

import '../qr/obr_codes.dart';
import 'invoice_link.dart';

class InvoiceHubService {
  InvoiceHubService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  /// Resolve dari raw QR / URL / plain invoice.
  Future<Map<String, dynamic>?> loadFromScan(String raw) async {
    final inv = InvoiceLink.parse(raw);
    if (inv == null) return null;
    return loadByInvoice(inv);
  }

  /// [phone] = nomor Member (pemilik) agar RPC mengembalikan `qr_payload` OBRINV.
  Future<Map<String, dynamic>?> loadByInvoice(
    String noInvoice, {
    String? phone,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_no_invoice': noInvoice.trim(),
      };
      final p = phone?.trim();
      if (p != null && p.isNotEmpty) {
        params['p_phone'] = p;
      }
      final res = await _db.rpc('get_invoice_hub', params: params);
      if (res == null) return null;
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      // Fallback langsung ke tabel jika RPC belum di-deploy (staff only)
      return _fallbackStaffLoad(noInvoice.trim());
    }
  }

  Future<Map<String, dynamic>?> _fallbackStaffLoad(String noInvoice) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final sale = await _db
        .from('sales')
        .select()
        .eq('no_invoice', noInvoice)
        .maybeSingle();
    if (sale == null) return null;
    final items = await _db
        .from('sales_items')
        .select(
          'id, nama_produk, tipe_produk, qty, subtotal, '
          'needs_fulfillment, fulfillment_status, diambil_at',
        )
        .eq('sale_id', sale['id']);
    final garansi = await _db
        .from('garansi_kartu')
        .select(
          'id, jenis_garansi, nama_produk, status, tanggal_mulai, '
          'tanggal_akhir, klaim_digunakan, spesifikasi_produk',
        )
        .eq('sale_id', sale['id']);
    return {
      'role_view': 'staff',
      'sale_id': sale['id'],
      'no_invoice': sale['no_invoice'],
      'toko_id': sale['toko_id'],
      'nama_pelanggan': sale['nama_pelanggan'],
      'nama_kasir': sale['nama_kasir'],
      'status_pembayaran': sale['status_pembayaran'],
      'tracking_status': sale['tracking_status'],
      'diambil_at': sale['diambil_at'],
      'foto_hasil_url': sale['foto_hasil_url'],
      'created_at': sale['created_at'],
      'total_harga': sale['total_harga'],
      'dibayarkan': sale['dibayarkan'],
      'sisa_tagihan': sale['sisa_tagihan'],
      'metode_pembayaran': sale['metode_pembayaran'],
      'no_wa': sale['no_wa'],
      'email_pelanggan': sale['email_pelanggan'],
      'alamat': sale['alamat'],
      'channel': sale['channel'],
      'fulfillment': sale['fulfillment'],
      'courier': sale['courier'],
      'online_order_id': sale['online_order_id'],
      'items': items,
      'garansi': garansi,
      'garansi_claimable': (garansi as List).any((raw) {
        final g = Map<String, dynamic>.from(raw as Map);
        if (g['status']?.toString() != 'aktif') return false;
        if (g['klaim_digunakan'] == true) return false;
        final akhir = DateTime.tryParse(g['tanggal_akhir']?.toString() ?? '');
        if (akhir == null) return false;
        final today = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
        return !DateTime(akhir.year, akhir.month, akhir.day).isBefore(today);
      }),
      'qr_dp_ready':
          sale['qr_dp_token'] != null && sale['qr_dp_used_at'] == null,
      'qr_lunas_ready':
          sale['qr_lunas_token'] != null && sale['qr_lunas_used_at'] == null,
      'qr_claim_ready':
          sale['qr_claim_token'] != null && sale['qr_claim_used_at'] == null,
      'qr_dp_used': sale['qr_dp_used_at'] != null,
      'qr_lunas_used': sale['qr_lunas_used_at'] != null,
      'qr_claim_used': sale['qr_claim_used_at'] != null,
      'qr_payload': InvoiceLink.encodeFromSale(
        Map<String, dynamic>.from(sale),
      ),
      'qr_phase': () {
        final p = InvoiceLink.encodeFromSale(Map<String, dynamic>.from(sale));
        final parsed = ObrInvoice.parse(p);
        return parsed?.phase;
      }(),
      'qr_owner_verified': true,
    };
  }

  static bool isStaffView(Map<String, dynamic> hub) =>
      hub['role_view']?.toString() == 'staff';

  /// Belum lunas (DP / sisa tagihan).
  static bool isDpOpen(Map<String, dynamic> hub) {
    final st = ObrInvoice.normalizePayStatus(
      hub['status_pembayaran']?.toString(),
    );
    final sisa = int.tryParse(hub['sisa_tagihan']?.toString() ?? '0') ?? 0;
    if (sisa > 0) return true;
    return st == 'DP';
  }

  static bool isLunas(Map<String, dynamic> hub) => !isDpOpen(hub);

  static bool sudahDiambil(Map<String, dynamic> hub) =>
      hub['diambil_at'] != null ||
      (hub['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');

  static bool isGaransiClaimable(Map<String, dynamic> hub) =>
      hub['garansi_claimable'] == true;

  static bool isCaseClosed(Map<String, dynamic> hub) {
    if (!sudahDiambil(hub)) return false;
    if (hub['qr_claim_used'] == true) return true;
    return !isGaransiClaimable(hub);
  }

  static String statusLabel(Map<String, dynamic> hub) {
    final items = hub['items'];
    if (items is List && items.isNotEmpty) {
      final maps = items
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Import avoided — inline counts for label
      var pendingRo = 0, ready = 0, diambil = 0;
      for (final i in maps) {
        final st =
            (i['fulfillment_status'] ?? 'READY').toString().toUpperCase();
        if (st == 'PENDING_RO' || st == 'PENDING') {
          pendingRo++;
        } else if (st == 'DIAMBIL') {
          diambil++;
        } else {
          ready++;
        }
      }
      final total = maps.length;
      if (total > 0 && diambil == total) {
        // Board CLEAR — jangan "Sudah diambil" generik.
        if (isCaseClosed(hub) || !isGaransiClaimable(hub)) {
          return 'CLEAR · Garansi mati';
        }
        return 'CLEAR · Garansi aktif';
      }
      if (ready > 0 && pendingRo > 0) {
        return 'Partial · siap ambil ready ($ready) · RO $pendingRo';
      }
      if (diambil > 0 && pendingRo > 0) {
        return 'Partial · RO pending';
      }
      if (pendingRo > 0 && ready == 0) return 'RO · stok pending';
    }
    if (hub['diambil_at'] != null ||
        (hub['tracking_status']?.toString() ?? '').toUpperCase() == 'DIAMBIL') {
      if (isCaseClosed(hub) || !isGaransiClaimable(hub)) {
        return 'CLEAR · Garansi mati';
      }
      return 'CLEAR · Garansi aktif';
    }
    final t = (hub['tracking_status']?.toString() ?? '').trim().toUpperCase();
    if (t == 'SIAP_DIAMBIL') return 'Siap diambil';
    if (t == 'CLEAR') return 'CLEAR · siap diambil';
    if (t == 'SIAP_PELUNASAN') return 'Siap pelunasan';
    if (isDpOpen(hub) && t == 'PENDING_PO') return 'DP · menunggu barang ready';
    if (t == 'PENDING_PO') return 'PENDING · menunggu barang ready';
    if (t == 'DIPROSES_DI_CABANG' || t == 'DIPROSES') {
      return 'Diproses di cabang';
    }
    if (t == 'DIKIRIM' || t == 'SHIPPED') return 'Dalam pengiriman';
    return t.isEmpty ? 'Dalam proses' : t;
  }

  static bool hasPendingRoLines(Map<String, dynamic> hub) {
    final items = hub['items'];
    if (items is! List) return false;
    for (final raw in items) {
      final st = (Map<String, dynamic>.from(raw as Map)['fulfillment_status'] ??
              '')
          .toString()
          .toUpperCase();
      if (st == 'PENDING_RO' || st == 'PENDING') return true;
    }
    return false;
  }

  static bool hasReadyLines(Map<String, dynamic> hub) {
    final items = hub['items'];
    // Tanpa data line → jangan asumsikan READY (hindari panel serah terima palsu).
    if (items is! List || items.isEmpty) return false;
    for (final raw in items) {
      final st = (Map<String, dynamic>.from(raw as Map)['fulfillment_status'] ??
              'READY')
          .toString()
          .toUpperCase();
      if (st == 'READY') return true;
    }
    return false;
  }

  static bool hasDiambilLines(Map<String, dynamic> hub) {
    final items = hub['items'];
    if (items is! List || items.isEmpty) return false;
    for (final raw in items) {
      final m = Map<String, dynamic>.from(raw as Map);
      final st = (m['fulfillment_status'] ?? '').toString().toUpperCase();
      if (st == 'DIAMBIL' || m['diambil_at'] != null) return true;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> listKaryawanToko(String tokoId) async {
    final rows = await _db
        .from('karyawan')
        .select('id, nama, jabatan, toko_id')
        .eq('toko_id', tokoId)
        .eq('status_approval', 'Aktif')
        .order('nama');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> setPembuat({
    required String noInvoice,
    required String karyawanId,
  }) async {
    await _db.rpc(
      'set_invoice_pembuat',
      params: {
        'p_no_invoice': noInvoice,
        'p_karyawan_id': karyawanId,
      },
    );
  }

  /// Tandai pesanan online delivery sudah diserahkan ke kurir.
  Future<Map<String, dynamic>> markOnlineShipped({
    required String onlineOrderId,
    String? courierTracking,
    String? storeNote,
  }) async {
    final res = await _db.rpc(
      'update_online_order_fulfillment',
      params: {
        'p_order_id': onlineOrderId,
        'p_status': 'shipped',
        'p_courier_tracking': courierTracking ?? '',
        'p_store_note': storeNote ?? '',
      },
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': true};
  }

  /// Panggil kurir Biteship (create order) lalu status → shipped.
  Future<Map<String, dynamic>> createBiteshipShipment({
    required String onlineOrderId,
  }) async {
    try {
      final res = await _db.functions.invoke(
        'biteship-create-order',
        body: {'online_order_id': onlineOrderId},
      );
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {
        'ok': false,
        'error': 'Respons Biteship tidak valid (HTTP ${res.status})',
      };
    } catch (e) {
      return {'ok': false, 'error': '$e'};
    }
  }

  Future<void> submitRating({
    required String noInvoice,
    required String peran,
    required int skor,
    String? komentar,
  }) async {
    await _db.rpc(
      'submit_invoice_rating',
      params: {
        'p_no_invoice': noInvoice,
        'p_peran': peran,
        'p_skor': skor,
        'p_komentar': komentar,
      },
    );
  }

  static Map<String, dynamic>? ratingFor(
    Map<String, dynamic> hub,
    String peran,
  ) {
    final list = hub['ratings'];
    if (list is! List) return null;
    for (final raw in list) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['peran']?.toString() == peran) return m;
    }
    return null;
  }

  static int? garansiSisaHariMax(Map<String, dynamic> hub) {
    final list = hub['garansi'];
    if (list is! List || list.isEmpty) return null;
    int? best;
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    for (final raw in list) {
      final g = Map<String, dynamic>.from(raw as Map);
      if (g['status']?.toString() != 'aktif') continue;
      final akhir = DateTime.tryParse(g['tanggal_akhir']?.toString() ?? '');
      if (akhir == null) continue;
      final sisa = DateTime(akhir.year, akhir.month, akhir.day)
          .difference(today)
          .inDays;
      if (best == null || sisa > best) best = sisa;
    }
    return best;
  }
}
