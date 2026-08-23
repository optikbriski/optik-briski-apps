import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import 'quick_stock_scan_rules.dart';

/// Lookup stok lewat RPC 000046 — bukan REST .select() penuh.
class QuickStockScanService {
  QuickStockScanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  Future<Map<String, dynamic>?> lookup({
    required Map<String, dynamic> profile,
    required String code,
  }) async {
    final toko = AttendanceAdminScope.tokoOf(profile).toUpperCase();
    if (!QuickStockScanRules.bolehScanToko(profile, toko)) {
      throw 'Hanya admin toko/cabang ini yang boleh pindai stok.';
    }
    if (!QuickStockScanRules.codeOk(code)) {
      throw 'Kode bukan label produk.';
    }
    try {
      final res = await _client.rpc('lookup_quick_stock_scan', params: {
        'p_toko': toko,
        'p_code': code.trim(),
      });
      if (res is! Map) return null;
      final map = Map<String, dynamic>.from(res);
      if (map['mutated'] == true) {
        throw 'Scan tidak boleh mengubah stok.';
      }
      if (map['found'] != true) return null;
      return map;
    } on PostgrestException catch (e) {
      if (_missingRpc(e)) {
        throw 'Gagal pindai stok. Paste seal 000046 (lookup_quick_stock_scan) jika belum.';
      }
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal pindai stok.' : msg;
    }
  }
}
