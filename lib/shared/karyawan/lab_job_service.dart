import 'package:supabase_flutter/supabase_flutter.dart';

import 'shift_auto_assign.dart';

/// Antrian job lab Backliner (claim first-wins + poin saat READY di DB).
class LabJobService {
  LabJobService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const statusOpen = 'OPEN';
  static const statusClaimed = 'CLAIMED';
  static const statusDone = 'DONE';

  /// True jika jabatan termasuk jalur Back (boleh lihat/claim antrian).
  bool isBackOffice(String? jabatan) =>
      officeLayerOf(jabatan) == OfficeLayer.back;

  Future<List<Map<String, dynamic>>> listOpenForToko(String tokoId) async {
    final tid = tokoId.trim();
    if (tid.isEmpty) return const [];
    final rows = await _db
        .from('lab_jobs')
        .select(
          'id, sale_id, toko_id, no_invoice, status, claimed_by, '
          'claimed_at, unit_qty, created_at',
        )
        .eq('toko_id', tid)
        .eq('status', statusOpen)
        .order('created_at', ascending: true)
        .limit(40);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> listMine({
    required String karyawanId,
    int limit = 20,
  }) async {
    final kid = karyawanId.trim();
    if (kid.isEmpty) return const [];
    final rows = await _db
        .from('lab_jobs')
        .select(
          'id, sale_id, toko_id, no_invoice, status, claimed_by, '
          'claimed_at, unit_qty, created_at',
        )
        .eq('claimed_by', kid)
        .inFilter('status', [statusClaimed, statusDone])
        .order('claimed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// OPEN toko + CLAIMED milik saya (untuk kartu home).
  Future<({List<Map<String, dynamic>> open, List<Map<String, dynamic>> mine})>
      listHomeQueue({
    required String tokoId,
    required String karyawanId,
  }) async {
    final open = await listOpenForToko(tokoId);
    final mine = await listMine(karyawanId: karyawanId, limit: 8);
    final mineActive =
        mine.where((j) => j['status']?.toString() == statusClaimed).toList();
    return (open: open, mine: mineActive);
  }

  Future<Map<String, dynamic>?> fetchBySaleId(String saleId) async {
    final id = saleId.trim();
    if (id.isEmpty) return null;
    final row = await _db
        .from('lab_jobs')
        .select(
          'id, sale_id, toko_id, no_invoice, status, claimed_by, '
          'claimed_at, unit_qty, created_at',
        )
        .eq('sale_id', id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>?> fetchByInvoice(String noInvoice) async {
    final inv = noInvoice.trim();
    if (inv.isEmpty) return null;
    final row = await _db
        .from('lab_jobs')
        .select(
          'id, sale_id, toko_id, no_invoice, status, claimed_by, '
          'claimed_at, unit_qty, created_at',
        )
        .eq('no_invoice', inv)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Atomic claim — first wins. Raises message dari DB bila gagal.
  Future<Map<String, dynamic>> claim(String jobId) async {
    final id = jobId.trim();
    if (id.isEmpty) throw 'Job lab kosong.';
    final res = await _db.rpc('claim_lab_job', params: {'p_job_id': id});
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'ok': true, 'job_id': id};
  }

  /// Parse `LAB_JOB:` + uuid dari isi notifikasi.
  static String? jobIdFromNotifikasiIsi(String? isi) {
    final raw = (isi ?? '').trim();
    if (raw.isEmpty) return null;
    final m = RegExp(r'LAB_JOB:([0-9a-fA-F-]{36})').firstMatch(raw);
    return m?.group(1);
  }
}
