import 'package:supabase_flutter/supabase_flutter.dart';

/// Transit / terima / retur lewat RPC 000027 — bukan REST + stok terpisah.
class DoLifecycleService {
  DoLifecycleService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<Map<String, dynamic>> markTransit({
    required String moveId,
    String? kurirId,
    String? kurirNama,
    String? buktiFotoKurir,
  }) async {
    try {
      final res = await _db.rpc('mark_stock_move_transit', params: {
        'p_move_id': moveId,
        'p_kurir_id': (kurirId ?? '').trim().isEmpty ? null : kurirId!.trim(),
        'p_kurir_nama':
            (kurirNama ?? '').trim().isEmpty ? null : kurirNama!.trim(),
        'p_bukti_foto_kurir': (buktiFotoKurir ?? '').trim().isEmpty
            ? null
            : buktiFotoKurir!.trim(),
      });
      return _map('mark_stock_move_transit', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal set TRANSIT.' : msg;
    }
  }

  Future<Map<String, dynamic>> receive({
    required String moveId,
    String? verifiedBy,
    String? verifiedByName,
    String? buktiFotoPenerima,
  }) async {
    try {
      final res = await _db.rpc('receive_stock_move', params: {
        'p_move_id': moveId,
        'p_verified_by':
            (verifiedBy ?? '').trim().isEmpty ? null : verifiedBy!.trim(),
        'p_verified_by_name': (verifiedByName ?? '').trim().isEmpty
            ? null
            : verifiedByName!.trim(),
        'p_bukti_foto_penerima': (buktiFotoPenerima ?? '').trim().isEmpty
            ? null
            : buktiFotoPenerima!.trim(),
      });
      return _map('receive_stock_move', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal terima surat jalan.' : msg;
    }
  }

  Future<Map<String, dynamic>> createReturn({
    required String dari,
    required List<Map<String, dynamic>> items,
    String? kurirId,
    String? kurirNama,
  }) async {
    try {
      final res = await _db.rpc('create_return_stock_move', params: {
        'p_dari': dari.trim().toUpperCase(),
        'p_items': items,
        'p_kurir_id': (kurirId ?? '').trim().isEmpty ? null : kurirId!.trim(),
        'p_kurir_nama':
            (kurirNama ?? '').trim().isEmpty ? null : kurirNama!.trim(),
      });
      return _map('create_return_stock_move', res);
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal buat retur.' : msg;
    }
  }

  static Map<String, dynamic> _map(String rpc, dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw 'Respon $rpc tidak valid.';
  }
}
