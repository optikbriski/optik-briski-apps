import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/bootstrap.dart';

/// Owner APK data access — server RPCs only (scoped by ownership).
class OwnerService {
  OwnerService({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> myProfile() async {
    final res = await _client.rpc('owner_my_profile');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listCabang() async {
    final res = await _client.rpc('owner_list_cabang');
    return _asMapList(res);
  }

  Future<Map<String, dynamic>> ringkasan({
    String? tokoId,
    String? periodeYm,
  }) async {
    final res = await _client.rpc(
      'owner_ringkasan',
      params: {
        'p_toko_id': tokoId,
        'p_periode_ym': periodeYm,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listTim({String? tokoId}) async {
    final res = await _client.rpc(
      'owner_list_tim',
      params: {'p_toko_id': tokoId},
    );
    return _asMapList(res);
  }

  Future<Map<String, dynamic>> payrollMonitor({String? tokoId}) async {
    final res = await _client.rpc(
      'owner_payroll_monitor',
      params: {'p_toko_id': tokoId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> listPersetujuan() async {
    final res = await _client.rpc('owner_list_persetujuan');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> decideKaryawan({
    required String karyawanId,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.rpc(
      'owner_decide_karyawan',
      params: {
        'p_karyawan_id': karyawanId,
        'p_approve': approve,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> decideJadwal({
    required String pengajuanId,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.rpc(
      'owner_decide_jadwal',
      params: {
        'p_pengajuan_id': pengajuanId,
        'p_approve': approve,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> decideFinance({
    required String txId,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.rpc(
      'owner_decide_finance',
      params: {
        'p_tx_id': txId,
        'p_approve': approve,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listAlerts({int limit = 50}) async {
    final res = await _client.rpc(
      'owner_list_alerts',
      params: {'p_limit': limit},
    );
    return _asMapList(res);
  }

  Future<bool> markAlertRead(String alertId) async {
    final res = await _client.rpc(
      'owner_mark_alert_read',
      params: {'p_alert_id': alertId},
    );
    return res == true;
  }

  Future<List<Map<String, dynamic>>> listSaldoLedger({
    String? tokoId,
    int limit = 50,
  }) async {
    final res = await _client.rpc(
      'owner_list_saldo_ledger',
      params: {
        'p_toko_id': tokoId,
        'p_limit': limit,
      },
    );
    return _asMapList(res);
  }

  Future<Map<String, dynamic>> postSaldoMovement({
    required String tokoId,
    required String direction,
    required int amount,
    String? note,
  }) async {
    final res = await _client.rpc(
      'owner_post_saldo_movement',
      params: {
        'p_toko_id': tokoId,
        'p_direction': direction,
        'p_amount': amount,
        'p_note': note,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> computeBagiHasil({
    required String tokoId,
    required String periodeYm,
    bool lock = false,
  }) async {
    final res = await _client.rpc(
      'owner_compute_bagi_hasil',
      params: {
        'p_toko_id': tokoId,
        'p_periode_ym': periodeYm,
        'p_lock': lock,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listBagiHasil({String? tokoId}) async {
    final res = await _client.rpc(
      'owner_list_bagi_hasil',
      params: {'p_toko_id': tokoId},
    );
    return _asMapList(res);
  }

  /// Daily P&L — Buku Besar aligned (read-only).
  Future<Map<String, dynamic>> laporanHarian({
    required String tokoId,
    String? date,
  }) async {
    final res = await _client.rpc(
      'owner_laporan_harian',
      params: {
        'p_toko_id': tokoId,
        'p_date': date,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> laporanBulanan({
    required String tokoId,
    String? periodeYm,
  }) async {
    final res = await _client.rpc(
      'owner_laporan_bulanan',
      params: {
        'p_toko_id': tokoId,
        'p_periode_ym': periodeYm ?? currentPeriodeYm(),
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> laporanTahunan({
    required String tokoId,
    int? year,
  }) async {
    final res = await _client.rpc(
      'owner_laporan_tahunan',
      params: {
        'p_toko_id': tokoId,
        'p_year': year ?? DateTime.now().year,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> reportSummary({
    required String tokoId,
    required String granularity,
    String? anchorDate,
  }) async {
    final res = await _client.rpc(
      'owner_report_summary',
      params: {
        'p_toko_id': tokoId,
        'p_granularity': granularity,
        'p_anchor': anchorDate,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> listFinanceLedger({
    String? tokoId,
    String? from,
    String? to,
    int limit = 100,
  }) async {
    final res = await _client.rpc(
      'owner_list_finance_ledger',
      params: {
        'p_toko_id': tokoId,
        'p_from': from,
        'p_to': to,
        'p_limit': limit,
      },
    );
    return _asMapList(res);
  }

  Future<Map<String, dynamic>> financeSnapshot({
    required String tokoId,
    String? from,
    String? to,
  }) async {
    final res = await _client.rpc(
      'owner_finance_snapshot',
      params: {
        'p_toko_id': tokoId,
        'p_from': from,
        'p_to': to,
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static List<Map<String, dynamic>> _asMapList(dynamic res) {
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static String formatRp(num? v) {
    final n = (v ?? 0).round();
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}Rp ${buf.toString()}';
  }

  static String currentPeriodeYm([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }
}
