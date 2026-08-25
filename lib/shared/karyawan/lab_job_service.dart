import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import 'shift_auto_assign.dart';

/// Antrian job lab Backliner (claim first-wins + selesai → READY + poin LAB).
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

  List<String> _tokoKeys(String tokoId) {
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    if (aliases.isEmpty) {
      final t = tokoId.trim();
      return t.isEmpty ? const [] : [t];
    }
    return aliases;
  }

  Future<List<Map<String, dynamic>>> listOpenForToko(String tokoId) async {
    final keys = _tokoKeys(tokoId);
    if (keys.isEmpty) return const [];
    final rows = await _db
        .from('lab_jobs')
        .select(
          'id, sale_id, toko_id, no_invoice, status, claimed_by, '
          'claimed_at, unit_qty, created_at',
        )
        .inFilter('toko_id', keys)
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
    if (res is Map) {
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] == false) {
        throw (m['error'] ?? 'Gagal klaim job lab').toString();
      }
      return m;
    }
    return {'ok': true, 'job_id': id};
  }

  /// Selesai: PENDING_RO→READY + QR siap ambil/pelunasan. Poin LAB via trigger DB.
  Future<Map<String, dynamic>> complete({
    required String jobId,
    List<String>? saleItemIds,
    String? fotoUrl,
  }) async {
    final id = jobId.trim();
    if (id.isEmpty) throw 'Job lab kosong.';
    final ids = (saleItemIds ?? [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final foto = (fotoUrl ?? '').trim();
    final res = await _db.rpc('complete_lab_job', params: {
      'p_job_id': id,
      if (ids.isNotEmpty) 'p_item_ids': ids,
      if (foto.isNotEmpty) 'p_foto_url': foto,
    });
    if (res is! Map) throw 'Respons complete_lab_job tidak valid.';
    final m = Map<String, dynamic>.from(res);
    if (m['ok'] == false) {
      throw (m['error'] ?? 'Gagal selesaikan job lab').toString();
    }
    return m;
  }

  /// Parse `LAB_JOB:` + uuid dari isi notifikasi.
  static String? jobIdFromNotifikasiIsi(String? isi) {
    final raw = (isi ?? '').trim();
    if (raw.isEmpty) return null;
    final m = RegExp(r'LAB_JOB:([0-9a-fA-F-]{36})').firstMatch(raw);
    return m?.group(1);
  }
}
