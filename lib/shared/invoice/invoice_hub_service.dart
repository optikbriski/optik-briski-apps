import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<Map<String, dynamic>?> loadByInvoice(String noInvoice) async {
    try {
      final res = await _db.rpc(
        'get_invoice_hub',
        params: {'p_no_invoice': noInvoice.trim()},
      );
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
        .select('nama_produk, tipe_produk, qty, subtotal')
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
      'items': items,
      'garansi': garansi,
    };
  }

  static bool isStaffView(Map<String, dynamic> hub) =>
      hub['role_view']?.toString() == 'staff';

  static String statusLabel(Map<String, dynamic> hub) {
    if (hub['diambil_at'] != null) return 'Sudah diambil';
    final t = hub['tracking_status']?.toString() ?? '';
    if (t == 'DIAMBIL') return 'Sudah diambil';
    if (t == 'SIAP_DIAMBIL' || t == 'CLEAR') return 'Siap diambil';
    if (t == 'PENDING_PO') return 'Menunggu / proses';
    if (t == 'DIPROSES_DI_CABANG') return 'Diproses di cabang';
    return t.isEmpty ? 'Dalam proses' : t;
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
