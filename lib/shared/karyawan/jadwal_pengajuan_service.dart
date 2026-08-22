import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../attendance/jadwal_kerja_rules.dart';

/// Service pengajuan ijin / cuti / tukar jadwal.
class JadwalPengajuanService {
  JadwalPengajuanService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static final _dateKey = DateFormat('yyyy-MM-dd');

  Future<void> submit({
    required String karyawanId,
    required String tokoId,
    required String tipe,
    required DateTime tanggal,
    required String alasan,
    DateTime? tanggalTukar,
    String? partnerKaryawanId,
  }) async {
    final t = JadwalKerjaRules.tipeOf(tipe);
    if (!JadwalKerjaRules.isAllowedTipe(t)) {
      throw 'Tipe pengajuan tidak valid.';
    }
    if (alasan.trim().isEmpty) throw 'Alasan wajib diisi.';
    if (t == 'TUKAR') {
      if (partnerKaryawanId == null || partnerKaryawanId.isEmpty) {
        throw 'Pilih teman tukar jadwal.';
      }
      if (tanggalTukar == null) throw 'Pilih tanggal tukar partner.';
    }

    await _client.from('jadwal_pengajuan').insert({
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'tipe': t,
      'tanggal': _dateKey.format(tanggal),
      'tanggal_tukar':
          tanggalTukar == null ? null : _dateKey.format(tanggalTukar),
      'partner_karyawan_id': partnerKaryawanId,
      'alasan': alasan.trim(),
      'status': 'PENDING',
    });
  }

  Future<List<Map<String, dynamic>>> listMine(String karyawanId) async {
    final rows = await _client
        .from('jadwal_pengajuan')
        .select(
          '*, partner:partner_karyawan_id(id, nama)',
        )
        .eq('karyawan_id', karyawanId)
        .order('created_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> listPending({
    String? tokoId,
    bool allToko = false,
  }) async {
    var q = _client.from('jadwal_pengajuan').select(
          '*, karyawan:karyawan_id(id, nama, jabatan, toko_id), '
          'partner:partner_karyawan_id(id, nama)',
        );
    q = q.eq('status', 'PENDING');
    if (!allToko && tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId);
    }
    final rows = await q.order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> countPending({String? tokoId, bool allToko = false}) async {
    var q = _client.from('jadwal_pengajuan').select('id');
    q = q.eq('status', 'PENDING');
    if (!allToko && tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId);
    }
    final rows = await q;
    return (rows as List).length;
  }

  Future<void> cancel(String id, String karyawanId) async {
    await _client
        .from('jadwal_pengajuan')
        .update({'status': 'CANCELLED'})
        .eq('id', id)
        .eq('karyawan_id', karyawanId)
        .eq('status', 'PENDING');
  }

  Future<void> decide({
    required String id,
    required bool approve,
    String? note,
    Map<String, dynamic>? profile,
    String? tokoId,
  }) async {
    final pid = id.trim();
    if (pid.isEmpty) throw 'Pengajuan tidak valid.';
    if (profile != null) {
      if (!AttendanceAdminScope.canEditTokoJadwal(profile, tokoId)) {
        throw 'Hanya admin toko/cabang yang berhak memutus pengajuan.';
      }
    }
    await _client.rpc(
      'decide_jadwal_pengajuan',
      params: {
        'p_pengajuan_id': pid,
        'p_approve': approve,
        'p_note': note,
      },
    );
  }

  Future<List<Map<String, dynamic>>> coworkers({
    required String tokoId,
    required String excludeId,
  }) async {
    final rows = await _client
        .from('karyawan')
        .select('id, nama, jabatan')
        .eq('toko_id', tokoId)
        .eq('status_approval', 'Aktif')
        .neq('id', excludeId)
        .order('nama');
    return List<Map<String, dynamic>>.from(rows);
  }
}
