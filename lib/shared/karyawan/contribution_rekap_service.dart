import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../tenant/tenant_service.dart';
import 'contribution_rekap.dart';
import 'kpi_fire_service.dart';
import 'shift_auto_assign.dart';

/// Rekap kontribusi Front/Back se-cabang (invoice terlibat / kacamata).
class ContributionRekapService {
  ContributionRekapService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static final _dateKey = DateFormat('yyyy-MM-dd');

  Future<ContributionRekap> loadMonth({
    required String tokoId,
    required String? jabatan,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final layer = officeLayerOf(jabatan);
    final start = DateTime(n.year, n.month, 1);
    final end = DateTime(n.year, n.month + 1, 0);
    final startKey = _dateKey.format(start);
    final endKey = _dateKey.format(end);
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    final keys = aliases.isEmpty ? [tokoId] : aliases;
    final tid = TenantService.instance.id;

    final peers = await _peersSameLayer(keys: keys, layer: layer, tenantId: tid);
    if (peers.isEmpty) {
      return ContributionRekap(
        layerLabel: layer == OfficeLayer.back ? 'Back' : 'Front',
        fairShare: 0,
        unitTim: 0,
        targetHari: KpiFireSnapshot.fallbackWorkDays,
        peers: const [],
        periodStart: start,
        periodEnd: end,
      );
    }

    final ids = peers.map((p) => p.id).toList();
    final units = layer == OfficeLayer.front
        ? await _frontUnits(keys: keys, peerIds: ids, startKey: startKey, endKey: endKey, tenantId: tid)
        : await _backUnits(keys: keys, peerIds: ids, startKey: startKey, endKey: endKey, tenantId: tid);

    final hari = await _workDaysByKaryawan(
      peerIds: ids,
      startKey: startKey,
      endKey: endKey,
    );

    final daysInMonth = end.day;
    final targetHari = (daysInMonth - 4)
        .clamp(KpiFireSnapshot.minWorkDays, KpiFireSnapshot.maxWorkDays);

    return ContributionRekap.build(
      layerLabel: layer == OfficeLayer.back ? 'Back' : 'Front',
      unitsById: {for (final id in ids) id: units[id] ?? 0},
      namaById: {for (final p in peers) p.id: p.nama},
      jabatanById: {for (final p in peers) p.id: p.jabatan},
      hariKerjaById: hari,
      targetHari: targetHari,
      periodStart: start,
      periodEnd: end,
    );
  }

  Future<List<({String id, String nama, String jabatan})>> _peersSameLayer({
    required List<String> keys,
    required OfficeLayer layer,
    required String? tenantId,
  }) async {
    var q = _db
        .from('karyawan')
        .select('id, nama, jabatan, status_approval, toko_id')
        .inFilter('toko_id', keys);
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final rows = await q;
    final out = <({String id, String nama, String jabatan})>[];
    for (final r in rows as List) {
      final status =
          (r['status_approval'] ?? '').toString().toLowerCase().trim();
      if (status != 'aktif' && status != 'active' && status != 'approved') {
        continue;
      }
      if (officeLayerOf(r['jabatan']?.toString()) != layer) continue;
      final id = (r['id'] ?? '').toString();
      if (id.isEmpty) continue;
      out.add((
        id: id,
        nama: (r['nama'] ?? '-').toString(),
        jabatan: (r['jabatan'] ?? '').toString(),
      ));
    }
    return out;
  }

  Future<Map<String, int>> _frontUnits({
    required List<String> keys,
    required List<String> peerIds,
    required String startKey,
    required String endKey,
    required String? tenantId,
  }) async {
    var q = _db
        .from('sales')
        .select('id')
        .inFilter('toko_id', keys)
        .gte('created_at', '${startKey}T00:00:00')
        .lte('created_at', '${endKey}T23:59:59.999');
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final sales = await q;
    final saleIds = <String>[
      for (final s in sales as List)
        if (s['id'] != null) s['id'].toString(),
    ];
    final counts = {for (final id in peerIds) id: 0};
    if (saleIds.isEmpty) return counts;

    const chunk = 80;
    for (var i = 0; i < saleIds.length; i += chunk) {
      final slice = saleIds.sublist(
        i,
        i + chunk > saleIds.length ? saleIds.length : i + chunk,
      );
      final rows = await _db
          .from('sales_karyawan_terlibat')
          .select('karyawan_id')
          .inFilter('sale_id', slice);
      for (final r in rows as List) {
        final kid = r['karyawan_id']?.toString();
        if (kid != null && counts.containsKey(kid)) {
          counts[kid] = (counts[kid] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Future<Map<String, int>> _backUnits({
    required List<String> keys,
    required List<String> peerIds,
    required String startKey,
    required String endKey,
    required String? tenantId,
  }) async {
    final counts = {for (final id in peerIds) id: 0};
    var q = _db
        .from('sales')
        .select('pembuat_kacamata_id')
        .inFilter('toko_id', keys)
        .gte('created_at', '${startKey}T00:00:00')
        .lte('created_at', '${endKey}T23:59:59.999')
        .not('pembuat_kacamata_id', 'is', null);
    if (tenantId != null && tenantId.isNotEmpty) {
      q = q.eq('tenant_id', tenantId);
    }
    final sales = await q;
    for (final s in sales as List) {
      final kid = s['pembuat_kacamata_id']?.toString();
      if (kid != null && counts.containsKey(kid)) {
        counts[kid] = (counts[kid] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<Map<String, int>> _workDaysByKaryawan({
    required List<String> peerIds,
    required String startKey,
    required String endKey,
  }) async {
    final out = {for (final id in peerIds) id: 0};
    if (peerIds.isEmpty) return out;
    final rows = await _db
        .from('jadwal_kerja')
        .select('karyawan_id, tanggal, is_libur')
        .inFilter('karyawan_id', peerIds)
        .gte('tanggal', startKey)
        .lte('tanggal', endKey);
    for (final r in rows as List) {
      final kid = r['karyawan_id']?.toString();
      if (kid == null || !out.containsKey(kid)) continue;
      final libur = r['is_libur'] == true;
      if (!libur) out[kid] = (out[kid] ?? 0) + 1;
    }
    return out;
  }
}
