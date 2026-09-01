import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';

class ReimburseService {
  ReimburseService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<void> submit({
    required String karyawanId,
    required String tokoId,
    required String kategori,
    required int jumlahRp,
    required String catatan,
    String? fotoUrl,
  }) async {
    if (jumlahRp <= 0) throw 'Jumlah harus lebih dari 0.';
    if (catatan.trim().isEmpty) throw 'Catatan wajib diisi.';
    if (tokoId.trim().isEmpty) throw 'Toko karyawan belum terisi.';
    await _db.from('karyawan_reimburse').insert({
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'kategori': kategori.trim(),
      'jumlah_rp': jumlahRp,
      'catatan': catatan.trim(),
      'foto_url': fotoUrl,
      'status': 'OPEN',
    });
  }

  Future<List<Map<String, dynamic>>> listMine(String karyawanId) async {
    final rows = await _db
        .from('karyawan_reimburse')
        .select()
        .eq('karyawan_id', karyawanId)
        .order('created_at', ascending: false)
        .limit(40);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<Map<String, dynamic>>> listInbox({
    required Map<String, dynamic> profile,
  }) async {
    final toko = AttendanceAdminScope.tokoOf(profile);
    final isPusat = AttendanceAdminScope.isPusatTokoId(toko) ||
        AttendanceAdminScope.isPusatOperator(profile);
    var q = _db.from('karyawan_reimburse').select(
          '*, karyawan:karyawan_id(nama, nik)',
        );
    if (!isPusat && toko.isNotEmpty) {
      final keys = AttendanceAdminScope.storeIdAliases(toko);
      q = q.inFilter('toko_id', keys.isEmpty ? [toko] : keys);
    }
    final rows = await q.order('created_at', ascending: false).limit(80);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<void> decide({
    required String id,
    required bool approve,
    String? note,
  }) async {
    final res = await _db.rpc('decide_karyawan_reimburse', params: {
      'p_id': id,
      'p_approve': approve,
      'p_note': note,
    });
    final map = res is Map ? Map<String, dynamic>.from(res) : {};
    if (map['ok'] != true && map.isNotEmpty) {
      throw map['error'] ?? 'Gagal memutus klaim.';
    }
  }
}
