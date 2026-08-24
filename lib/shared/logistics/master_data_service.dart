import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'master_data_rules.dart';
import 'product_identity.dart';
import 'stock_mutation_service.dart';

/// Katalog Master Data lewat RPC 000047/000048 — bukan potong 1000 REST.
class MasterDataService {
  MasterDataService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int pageSize = 800;
  static const int restPageSize = 500;
  static const int maxRows = 20000;
  static const int restCapHint = 1000;

  static bool _missingRpc(PostgrestException e) {
    final blob = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    return e.code == 'PGRST202' ||
        blob.contains('pgrst202') ||
        blob.contains('could not find the function') ||
        blob.contains('does not exist');
  }

  static List<Map<String, dynamic>> _asRows(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        return _asRows(jsonDecode(raw));
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> listAllRows() async {
    final byId = <String, Map<String, dynamic>>{};
    void absorb(Iterable<Map<String, dynamic>> rows) {
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = r;
      }
    }

    var pagedOk = false;
    try {
      var offset = 0;
      while (offset <= maxRows) {
        final raw = await _client.rpc(
          'list_master_products',
          params: {'p_offset': offset, 'p_limit': pageSize},
        );
        final chunk = _asRows(raw);
        absorb(chunk);
        pagedOk = true;
        if (chunk.length < pageSize) break;
        offset += pageSize;
      }
    } on PostgrestException catch (e) {
      if (!_missingRpc(e)) {
        final msg = e.message.trim();
        throw msg.isEmpty
            ? 'Gagal pindai Master Data. Paste seal 000048 jika belum.'
            : msg;
      }
    }

    if (!pagedOk) {
      try {
        final raw = await _client.rpc('list_master_products');
        final chunk = _asRows(raw);
        absorb(chunk);
        if (chunk.length >= restCapHint) {
          absorb(await _restPaged());
        }
        if (byId.isNotEmpty) return byId.values.toList();
      } on PostgrestException catch (e) {
        if (!_missingRpc(e)) {
          final msg = e.message.trim();
          throw msg.isEmpty
              ? 'Gagal pindai Master Data. Paste seal 000047 jika belum.'
              : msg;
        }
      }
    }

    if (byId.isEmpty) absorb(await _restPaged());
    return byId.values.toList();
  }

  Future<List<Map<String, dynamic>>> _restPaged() async {
    final byId = <String, Map<String, dynamic>>{};
    var offset = 0;
    while (true) {
      final chunk = await _client
          .from('products')
          .select()
          .order('created_at', ascending: false)
          .range(offset, offset + restPageSize - 1);
      final rows = List<Map<String, dynamic>>.from(chunk as List);
      if (rows.isEmpty) break;
      for (final r in rows) {
        final id = r['id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = r;
      }
      if (rows.length < restPageSize) break;
      offset += restPageSize;
      if (offset > maxRows) break;
    }
    return byId.values.toList();
  }

  /// Gabung baris SKU × toko. PUSAT = CABANG-PUSAT satu slot, stok tidak dobel.
  static List<Map<String, dynamic>> mergeBySku(
    Iterable<Map<String, dynamic>> rawList,
  ) {
    final mapGabung = <String, Map<String, dynamic>>{};
    for (final item in rawList) {
      final rawKey = ProductIdentity.normalizeSku(item['sku']) ??
          ProductIdentity.normalizeBarcode(item['barcode']) ??
          'ID-${item['id']}';
      final skuKey = rawKey.toUpperCase();
      final itemMap = Map<String, dynamic>.from(item);
      final realSekarang = StockQty.realOf(itemMap);
      final pendingSekarang = StockQty.pendingOf(itemMap);
      final availableSekarang = StockQty.availableOf(itemMap);
      final lokasiToko = MasterDataRules.canonicalToko(
        item['toko_id']?.toString(),
      );
      final slot = {
        'cabang': lokasiToko,
        'stok': realSekarang,
        'pending': pendingSekarang,
        'available': availableSekarang,
        '_exact': (item['toko_id'] ?? '').toString().trim().toUpperCase(),
      };

      if (!mapGabung.containsKey(skuKey)) {
        final row = Map<String, dynamic>.from(item);
        row['breakdown_stok'] = [slot];
        row['total_stock'] = realSekarang;
        row['total_pending'] = pendingSekarang;
        row['total_available'] = availableSekarang;
        mapGabung[skuKey] = row;
        continue;
      }

      final dest = mapGabung[skuKey]!;
      final breakdown = List<Map<String, dynamic>>.from(
        (dest['breakdown_stok'] as List).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      final existingIdx = breakdown.indexWhere(
        (b) => MasterDataRules.sameStore(
          b['cabang']?.toString(),
          lokasiToko,
        ),
      );

      if (existingIdx >= 0) {
        final old = breakdown[existingIdx];
        final oldAvail = MasterDataRules.stokOf(old['available']);
        final oldExact = (old['_exact'] ?? old['cabang'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        final newExact =
            (item['toko_id'] ?? '').toString().trim().toUpperCase();
        final takeNew = availableSekarang > oldAvail ||
            (availableSekarang == oldAvail &&
                newExact == 'PUSAT' &&
                oldExact != 'PUSAT');
        if (takeNew) {
          dest['total_stock'] = MasterDataRules.stokOf(dest['total_stock']) -
              MasterDataRules.stokOf(old['stok']) +
              realSekarang;
          dest['total_pending'] =
              MasterDataRules.stokOf(dest['total_pending']) -
                  MasterDataRules.stokOf(old['pending']) +
                  pendingSekarang;
          dest['total_available'] =
              MasterDataRules.stokOf(dest['total_available']) -
                  oldAvail +
                  availableSekarang;
          breakdown[existingIdx] = slot;
        }
      } else {
        dest['total_stock'] =
            MasterDataRules.stokOf(dest['total_stock']) + realSekarang;
        dest['total_pending'] =
            MasterDataRules.stokOf(dest['total_pending']) + pendingSekarang;
        dest['total_available'] =
            MasterDataRules.stokOf(dest['total_available']) + availableSekarang;
        breakdown.add(slot);
      }

      dest['breakdown_stok'] = breakdown;
      final destToko = MasterDataRules.canonicalToko(dest['toko_id']?.toString());
      final destExact =
          (dest['toko_id'] ?? '').toString().trim().toUpperCase();
      final newExact = (item['toko_id'] ?? '').toString().trim().toUpperCase();
      final preferMeta = MasterDataRules.sameStore(lokasiToko, 'PUSAT') &&
          (destToko != 'PUSAT' ||
              (newExact == 'PUSAT' && destExact != 'PUSAT'));
      if (preferMeta) {
        final next = Map<String, dynamic>.from(item);
        next['breakdown_stok'] = breakdown;
        next['total_stock'] = dest['total_stock'];
        next['total_pending'] = dest['total_pending'];
        next['total_available'] = dest['total_available'];
        mapGabung[skuKey] = next;
      }
    }

    for (final row in mapGabung.values) {
      final bd = row['breakdown_stok'];
      if (bd is! List) continue;
      row['breakdown_stok'] = [
        for (final raw in bd)
          if (raw is Map)
            {
              'cabang': raw['cabang'],
              'stok': raw['stok'],
              'pending': raw['pending'],
              'available': raw['available'],
            }
      ];
    }
    return mapGabung.values.toList();
  }

  static bool sameStoreRow(String? toko, String? other) =>
      MasterDataRules.sameStore(toko, other);
}
