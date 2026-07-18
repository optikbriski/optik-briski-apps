import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KaryawanHomeSnapshot {
  KaryawanHomeSnapshot({
    required this.karyawan,
    required this.jadwalMinggu,
    required this.sopTasks,
    required this.totalPoinBulan,
    required this.streakHari,
    required this.sudahKlaimHariIni,
    required this.riwayat30Hari,
    required this.securityScore,
  });

  final Map<String, dynamic> karyawan;
  final List<Map<String, String>> jadwalMinggu;
  final List<Map<String, dynamic>> sopTasks;
  final int totalPoinBulan;
  final int streakHari;
  final bool sudahKlaimHariIni;
  final List<int> riwayat30Hari;
  final double securityScore;
}

class KaryawanHomeService {
  KaryawanHomeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final _dayFmt = DateFormat('d MMM', 'id_ID');
  static final _dateKey = DateFormat('yyyy-MM-dd');

  Future<Map<String, dynamic>?> fetchKaryawan() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final byId =
        await _client.from('karyawan').select().eq('id', user.id).maybeSingle();
    if (byId != null) return byId;

    final email = user.email;
    if (email == null || email.isEmpty) return null;
    return _client.from('karyawan').select().eq('email', email).maybeSingle();
  }

  Future<KaryawanHomeSnapshot?> loadHome() async {
    final karyawan = await fetchKaryawan();
    if (karyawan == null) return null;

    final karyawanId = karyawan['id'] as String;
    final jabatan = (karyawan['jabatan'] ?? '').toString();

    final monday = _startOfWeek(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));

    final jadwalRows = await _client
        .from('jadwal_kerja')
        .select()
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', _dateKey.format(monday))
        .lte('tanggal', _dateKey.format(sunday))
        .order('tanggal');

    final jadwalMinggu = _buildWeekCards(monday, List<Map<String, dynamic>>.from(jadwalRows));

    final templates = await _loadSopTemplates(jabatan);
    final today = _dateKey.format(DateTime.now());
    final completions = await _client
        .from('sop_completions')
        .select()
        .eq('karyawan_id', karyawanId)
        .eq('tanggal', today);
    final doneIds = {
      for (final c in completions) c['template_id']?.toString(),
    };

    final sopTasks = templates.map((t) {
      final id = t['id']?.toString() ?? '';
      return <String, dynamic>{
        'id': id,
        'tugas': t['judul']?.toString() ?? '-',
        'jenis_bukti': _mapTipe(t['tipe']?.toString()),
        'poin': t['poin'] ?? 10,
        'selesai': doneIds.contains(id),
        'bukti_text': null,
        'bukti_bytes': null,
      };
    }).toList();

    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final poinRows = await _client
        .from('poin_logs')
        .select('poin, tanggal, sumber, ref_id')
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', _dateKey.format(monthStart));

    var totalPoin = 0;
    for (final p in poinRows) {
      totalPoin += (p['poin'] as num?)?.toInt() ?? 0;
    }

    final sudahKlaim = poinRows.any((p) =>
        p['sumber'] == 'SOP' &&
        p['tanggal']?.toString() == today &&
        (p['ref_id']?.toString().startsWith('daily-') ?? false));

    final streak = await _computeStreak(karyawanId);
    final riwayat = await _riwayat30Hari(karyawanId);
    final security = _securityScore(karyawan);

    return KaryawanHomeSnapshot(
      karyawan: karyawan,
      jadwalMinggu: jadwalMinggu,
      sopTasks: sopTasks,
      totalPoinBulan: totalPoin.clamp(0, 100000),
      streakHari: streak,
      sudahKlaimHariIni: sudahKlaim,
      riwayat30Hari: riwayat,
      securityScore: security,
    );
  }

  Future<void> completeSopTask({
    required String karyawanId,
    required Map<String, dynamic> task,
    String? buktiText,
    Uint8List? buktiBytes,
  }) async {
    final templateId = task['id']?.toString();
    if (templateId == null || templateId.isEmpty) {
      throw 'Template SOP tidak valid.';
    }

    String? buktiUrl;
    if (buktiBytes != null && buktiBytes.isNotEmpty) {
      final path =
          '$karyawanId/${templateId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _client.storage.from('attendance_photos').uploadBinary(
            path,
            buktiBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      buktiUrl = _client.storage.from('attendance_photos').getPublicUrl(path);
    }

    final today = _dateKey.format(DateTime.now());
    final poin = (task['poin'] as num?)?.toInt() ?? 10;

    await _client.from('sop_completions').upsert({
      'karyawan_id': karyawanId,
      'template_id': templateId,
      'tanggal': today,
      'bukti_text': buktiText,
      'bukti_url': buktiUrl,
      'poin_claimed': poin,
    }, onConflict: 'karyawan_id,template_id,tanggal');
  }

  Future<int> claimDailySopPoints({
    required String karyawanId,
    required List<Map<String, dynamic>> tasks,
    required int streakHari,
  }) async {
    final unfinished = tasks.where((t) => t['selesai'] != true).toList();
    if (unfinished.isNotEmpty) {
      throw 'Selesaikan semua SOP dulu.';
    }

    final today = _dateKey.format(DateTime.now());
    final refId = 'daily-$today';

    var base = 0;
    for (final t in tasks) {
      base += (t['poin'] as num?)?.toInt() ?? 0;
    }
    final bonus = streakHari >= 3 ? 5 : 0;
    final total = base + bonus;

    try {
      await _client.from('poin_logs').insert({
        'karyawan_id': karyawanId,
        'tanggal': today,
        'poin': total,
        'sumber': 'SOP',
        'ref_id': refId,
      });
    } catch (e) {
      throw 'Poin hari ini sudah diklaim.';
    }

    final uid = _client.auth.currentUser?.id ?? karyawanId;
    await _client.from('notifikasi').insert({
      'user_id': uid,
      'judul': 'SOP selesai',
      'isi': 'Poin +$total berhasil diklaim hari ini.',
      'tipe': 'SOP',
    });

    return total;
  }

  Future<void> ensureTodayReminders({
    required String karyawanId,
    required List<Map<String, String>> jadwalMinggu,
    required List<Map<String, dynamic>> sopTasks,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final todayKey = _dateKey.format(DateTime.now());
    Map<String, String>? todayCard;
    for (final j in jadwalMinggu) {
      if (j['date_key'] == todayKey) {
        todayCard = j;
        break;
      }
    }

    final existing = await _client
        .from('notifikasi')
        .select('id, tipe, judul')
        .eq('user_id', uid)
        .gte(
            'created_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 20))
                .toIso8601String());

    final titles = {
      for (final n in existing) '${n['tipe']}|${n['judul']}',
    };

    final unfinished = sopTasks.where((t) => t['selesai'] != true).length;
    if (unfinished > 0) {
      const key = 'SOP|SOP belum selesai';
      if (!titles.contains(key)) {
        await _client.from('notifikasi').insert({
          'user_id': uid,
          'judul': 'SOP belum selesai',
          'isi': 'Masih ada $unfinished tugas SOP hari ini.',
          'tipe': 'SOP',
        });
      }
    }

    if (todayCard != null) {
      final shift = todayCard['shift'] ?? '-';
      const key = 'SHIFT|Jadwal hari ini';
      if (!titles.contains(key)) {
        await _client.from('notifikasi').insert({
          'user_id': uid,
          'judul': 'Jadwal hari ini',
          'isi': 'Shift: $shift',
          'tipe': 'SHIFT',
        });
      }
    }
  }

  DateTime _startOfWeek(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - 1));
  }

  List<Map<String, String>> _buildWeekCards(
    DateTime monday,
    List<Map<String, dynamic>> rows,
  ) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      byDate[r['tanggal'].toString()] = r;
    }

    const hariKeys = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];

    final out = <Map<String, String>>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final key = _dateKey.format(day);
      final row = byDate[key];
      String shift;
      if (row == null) {
        shift = 'Belum dijadwalkan';
      } else if (row['is_libur'] == true) {
        shift = 'Libur';
      } else {
        final masuk = _fmtTime(row['jam_masuk']);
        final pulang = _fmtTime(row['jam_pulang']);
        shift = (masuk == null && pulang == null)
            ? 'Belum dijadwalkan'
            : '${masuk ?? '--'}-${pulang ?? '--'}';
      }
      out.add({
        'hari': hariKeys[i],
        'tanggal': _dayFmt.format(day),
        'shift': shift,
        'date_key': key,
        'catatan': row?['catatan']?.toString() ?? '',
      });
    }
    return out;
  }

  String? _fmtTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }

  Future<List<Map<String, dynamic>>> _loadSopTemplates(String jabatan) async {
    final all = await _client
        .from('sop_templates')
        .select()
        .eq('aktif', true)
        .order('urutan');

    final list = List<Map<String, dynamic>>.from(all);
    final specific = list
        .where((t) =>
            (t['jabatan']?.toString() ?? '').toLowerCase() ==
            jabatan.toLowerCase())
        .toList();
    if (specific.isNotEmpty) return specific;

    final generic = list.where((t) => t['jabatan'] == null).toList();
    if (generic.isNotEmpty) return generic;

    // Fallback jika seed belum dijalankan
    return [
      {
        'id': '',
        'judul': 'Rapikan area kerja',
        'tipe': 'FOTO',
        'poin': 10,
      },
      {
        'id': '',
        'judul': 'Foto kondisi toko pagi',
        'tipe': 'FOTO',
        'poin': 10,
      },
    ];
  }

  String _mapTipe(String? tipe) {
    switch ((tipe ?? 'CHECK').toUpperCase()) {
      case 'FOTO':
        return 'foto';
      case 'SCAN':
        return 'scan';
      case 'INPUT':
        return 'input';
      default:
        return 'foto';
    }
  }

  Future<int> _computeStreak(String karyawanId) async {
    final rows = await _client
        .from('attendance_logs')
        .select('created_at')
        .eq('karyawan_id', karyawanId)
        .eq('tipe', 'MASUK')
        .order('created_at', ascending: false)
        .limit(60);

    final days = <String>{};
    for (final r in rows) {
      final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
      if (dt != null) {
        days.add(_dateKey.format(dt.toLocal()));
      }
    }

    var streak = 0;
    var cursor = DateTime.now();
    // Jika hari ini belum absen, mulai dari kemarin
    if (!days.contains(_dateKey.format(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (days.contains(_dateKey.format(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<List<int>> _riwayat30Hari(String karyawanId) async {
    final start = DateTime.now().subtract(const Duration(days: 29));
    final rows = await _client
        .from('poin_logs')
        .select('tanggal, poin')
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', _dateKey.format(start));

    final map = <String, int>{};
    for (final r in rows) {
      final k = r['tanggal'].toString();
      map[k] = (map[k] ?? 0) + ((r['poin'] as num?)?.toInt() ?? 0);
    }

    final out = <int>[];
    for (var i = 0; i < 30; i++) {
      final d = start.add(Duration(days: i));
      final pts = map[_dateKey.format(d)] ?? 0;
      if (pts >= 35) {
        out.add(2);
      } else if (pts > 0) {
        out.add(1);
      } else {
        out.add(0);
      }
    }
    return out;
  }

  double _securityScore(Map<String, dynamic> karyawan) {
    var score = 0.0;
    final pin = karyawan['pin_absensi']?.toString() ?? '';
    if (pin.length >= 4) score += 0.34;
    final face = karyawan['face_template'] != null ||
        (karyawan['face_photo_url']?.toString().isNotEmpty ?? false);
    if (face) score += 0.33;
    // Auth session implies password/account exists
    if (_client.auth.currentUser != null) score += 0.33;
    return score.clamp(0.0, 1.0);
  }
}
