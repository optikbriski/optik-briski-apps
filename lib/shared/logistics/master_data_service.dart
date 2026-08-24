import 'package:supabase_flutter/supabase_flutter.dart';

import 'master_data_rules.dart';

/// Katalog Master Data lewat RPC 000047 — bukan potong 1000 REST.
class MasterDataService {
  MasterDataService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  Future<List<Map<String, dynamic>>> listAllRows() async {
    try {
      final raw = await _client.rpc('list_master_products');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty
            ? 'Gagal pindai Master Data. Paste seal 000047 jika belum.'
            : msg;
      }
    }
    return _restPaged();
  }

  Future<List<Map<String, dynamic>>> _restPaged() async {
    final byId = <String, Map<String, dynamic>>{};
    var offset = 0;
    const pageSize = 500;
    while (true) {
      final chunk = await _client
          .from('products')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      final rows = List<Map<String, dynamic>>.from(chunk as List);
      if (rows.isEmpty) break;
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = r;
      }
      if (rows.length < pageSize) break;
      offset += pageSize;
      if (offset > 20000) break;
    }
    return byId.values.toList();
  }

  static bool sameStoreRow(String? toko, String? other) =>
      MasterDataRules.sameStore(toko, other);
}
