import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';

/// Antrian verifikasi terima (TRANSIT/PENDING ke toko tujuan).
class ReceiveQueueService {
  ReceiveQueueService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> listIncoming({
    required String tokoId,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) return const [];
    try {
      final raw = await _db.rpc(
        'list_incoming_receive_queue',
        params: {'p_toko': toko},
      );
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) rethrow;
    }
    return _listIncomingRest(toko);
  }

  Future<int> countIncoming({
    required String tokoId,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) return 0;
    try {
      final raw = await _db.rpc(
        'count_incoming_receive_queue',
        params: {'p_toko': toko},
      );
      if (raw is int) return raw < 0 ? 0 : raw;
      if (raw is num) return raw.round() < 0 ? 0 : raw.round();
      final parsed = int.tryParse('$raw');
      if (parsed != null) return parsed < 0 ? 0 : parsed;
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) rethrow;
    }
    return (await _listIncomingRest(toko)).length;
  }

  Future<List<Map<String, dynamic>>> _listIncomingRest(String toko) async {
    const pageSize = 1000;
    var from = 0;
    final out = <Map<String, dynamic>>[];
    final aliases = AttendanceAdminScope.storeIdAliases(toko);
    while (true) {
      var q = _db
          .from('stock_move_history')
          .select()
          .inFilter('status', ['TRANSIT', 'PENDING']);
      q = aliases.length == 1
          ? q.eq('ke_lokasi', aliases.first)
          : q.inFilter('ke_lokasi', aliases);
      final res = await q
          .order('created_at', ascending: false)
          .range(from, from + pageSize - 1);
      final chunk = List<Map<String, dynamic>>.from(
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      out.addAll(chunk);
      if (chunk.length < pageSize) break;
      from += pageSize;
      if (from > 8000) break;
    }
    return out;
  }

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }
}
