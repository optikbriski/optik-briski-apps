import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import 'quick_stock_scan_rules.dart';

/// Lookup stok lewat RPC 000034 — bukan REST .select() penuh.
class QuickStockScanService {
  QuickStockScanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

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
      if (map['found'] != true) return null;
      return map;
    } on PostgrestException catch (e) {
      final msg = e.message.trim();
      throw msg.isEmpty ? 'Gagal pindai stok.' : msg;
    }
  }
}
