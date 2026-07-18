import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final t = tipe.toUpperCase();
    if (!const {'IJIN', 'CUTI', 'TUKAR'}.contains(t)) {
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
  }) async {
    final userId = _client.auth.currentUser?.id;
    final row = await _client
        .from('jadwal_pengajuan')
        .select()
        .eq('id', id)
        .eq('status', 'PENDING')
        .maybeSingle();
    if (row == null) throw 'Pengajuan tidak ditemukan / sudah diproses.';

    if (!approve) {
      await _client.from('jadwal_pengajuan').update({
        'status': 'REJECTED',
        'reviewer_id': userId,
        'reviewer_note': note,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      return;
    }

    final tipe = (row['tipe'] ?? '').toString().toUpperCase();
    if (tipe == 'IJIN' || tipe == 'CUTI') {
      await _applyIjin(
        karyawanId: row['karyawan_id'].toString(),
        tokoId: row['toko_id']?.toString(),
        tanggal: row['tanggal'].toString(),
        catatan: '$tipe disetujui: ${row['alasan'] ?? ''}',
      );
    } else if (tipe == 'TUKAR') {
      await _applyTukar(
        karyawanId: row['karyawan_id'].toString(),
        partnerId: row['partner_karyawan_id']?.toString(),
        tokoId: row['toko_id']?.toString(),
        tanggalA: row['tanggal'].toString(),
        tanggalB: (row['tanggal_tukar'] ?? row['tanggal']).toString(),
      );
    } else {
      throw 'Tipe pengajuan tidak dikenal: $tipe';
    }

    await _client.from('jadwal_pengajuan').update({
      'status': 'APPROVED',
      'reviewer_id': userId,
      'reviewer_note': note,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> _applyIjin({
    required String karyawanId,
    required String? tokoId,
    required String tanggal,
    required String catatan,
  }) async {
    await _client.from('jadwal_kerja').upsert(
      {
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'tanggal': tanggal.length >= 10 ? tanggal.substring(0, 10) : tanggal,
        'jam_masuk': null,
        'jam_pulang': null,
        'is_libur': true,
        'catatan': catatan.trim(),
      },
      onConflict: 'karyawan_id,tanggal',
    );
  }

  Future<Map<String, dynamic>?> _loadJadwal(String kid, String tgl) async {
    final key = tgl.length >= 10 ? tgl.substring(0, 10) : tgl;
    return _client
        .from('jadwal_kerja')
        .select()
        .eq('karyawan_id', kid)
        .eq('tanggal', key)
        .maybeSingle();
  }

  Future<void> _applyTukar({
    required String karyawanId,
    required String? partnerId,
    required String? tokoId,
    required String tanggalA,
    required String tanggalB,
  }) async {
    if (partnerId == null || partnerId.isEmpty) {
      throw 'Partner tukar tidak ada.';
    }
    final a = tanggalA.length >= 10 ? tanggalA.substring(0, 10) : tanggalA;
    final b = tanggalB.length >= 10 ? tanggalB.substring(0, 10) : tanggalB;

    final jadwalA = await _loadJadwal(karyawanId, a);
    final jadwalB = await _loadJadwal(partnerId, b);

    // Tukar isi jadwal A@hariA ↔ B@hariB
    await _client.from('jadwal_kerja').upsert(
      [
        {
          'karyawan_id': karyawanId,
          'toko_id': tokoId,
          'tanggal': a,
          'jam_masuk': jadwalB?['jam_masuk'],
          'jam_pulang': jadwalB?['jam_pulang'],
          'is_libur': jadwalB?['is_libur'] == true,
          'catatan': 'Hasil tukar jadwal dengan partner',
        },
        {
          'karyawan_id': partnerId,
          'toko_id': tokoId,
          'tanggal': b,
          'jam_masuk': jadwalA?['jam_masuk'],
          'jam_pulang': jadwalA?['jam_pulang'],
          'is_libur': jadwalA?['is_libur'] == true,
          'catatan': 'Hasil tukar jadwal dengan partner',
        },
      ],
      onConflict: 'karyawan_id,tanggal',
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
