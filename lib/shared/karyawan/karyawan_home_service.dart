import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'kpi_fire_service.dart';
import 'streak_fire_level.dart';

class KaryawanHomeSnapshot {
  KaryawanHomeSnapshot({
    required this.karyawan,
    required this.jadwalMinggu,
    required this.sopTasks,
    required this.totalPoinBulan,
    required this.streakHari,
    required this.streakHariBulanIni,
    required this.daysInMonth,
    required this.fireHistory,
    required this.kpiYearHistory,
    required this.sudahKlaimHariIni,
    required this.riwayat30Hari,
    required this.securityScore,
    required this.kpiFire,
    this.jadwalHariIni,
    this.absenStatus = 'belum_masuk',
    this.absenMasukAt,
    this.absenPulangAt,
    this.hasOpenShift = false,
    this.pengajuanTerbaru = const [],
    this.pengumuman = const [],
  });

  final Map<String, dynamic> karyawan;
  final List<Map<String, String>> jadwalMinggu;
  final List<Map<String, dynamic>> sopTasks;
  final int totalPoinBulan;

  /// Streak beruntun lintas bulan (bonus SOP legacy).
  final int streakHari;

  /// Legacy streak hari bulan (diganti [kpiFire] untuk warna api).
  final int streakHariBulanIni;

  /// Panjang bulan berjalan (28–31).
  final int daysInMonth;

  /// Riwayat api per bulan (legacy streak hari), terbaru dulu.
  final List<StreakFireMonthRecord> fireHistory;

  /// Riwayat Api KPI 12 bulan dari poin (terbaru dulu).
  final List<KpiMonthHistoryRecord> kpiYearHistory;
  final bool sudahKlaimHariIni;
  final List<int> riwayat30Hari;
  final double securityScore;

  /// Api KPI: 40% tetap (absen+SOP) + 60% fair share toko.
  final KpiFireSnapshot kpiFire;

  /// Kartu jadwal untuk hari ini (dari [jadwalMinggu]).
  final Map<String, String>? jadwalHariIni;

  /// `belum_masuk` | `sedang_bekerja` | `selesai` | `libur`
  final String absenStatus;
  final DateTime? absenMasukAt;
  final DateTime? absenPulangAt;
  final bool hasOpenShift;
  final List<Map<String, dynamic>> pengajuanTerbaru;
  final List<Map<String, dynamic>> pengumuman;
}

class KaryawanHomeService {
  KaryawanHomeService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client,
        _kpiFire = KpiFireService(client: client ?? Supabase.instance.client);

  final SupabaseClient _client;
  final KpiFireService _kpiFire;

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

    // Samakan poin absensi Admin (attendance_verifications.poin_awarded)
    // ke poin_logs bila insert Admin sebelumnya gagal diam-diam.
    await _syncAbsenPoinFromVerifications(karyawanId);

    final monthKey = _dateKey.format(monthStart);
    final poinRows = await _client
        .from('poin_logs')
        .select('poin, tanggal, sumber, ref_id')
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', monthKey);

    var totalPoin = 0;
    final logRefs = <String>{};
    for (final p in poinRows) {
      totalPoin += (p['poin'] as num?)?.toInt() ?? 0;
      final ref = p['ref_id']?.toString();
      if (ref != null && ref.isNotEmpty) logRefs.add(ref);
    }

    // Cadangan: jika insert poin_logs gagal (RLS/dll), tetap hitung dari verifikasi.
    totalPoin += await _absenPoinFromVerificationsMissingInLogs(
      karyawanId: karyawanId,
      monthStartKey: monthKey,
      existingRefs: logRefs,
    );

    final sudahKlaim = poinRows.any((p) =>
        p['sumber'] == 'SOP' &&
        p['tanggal']?.toString() == today &&
        (p['ref_id']?.toString().startsWith('daily-') ?? false));

    final masukDays = await _loadMasukDays(karyawanId, monthsBack: 12);
    final now = DateTime.now();
    final streak = _streakFromDays(masukDays, now);
    final streakBulan = _streakInCalendarMonth(masukDays, now);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final fireHistory = _buildFireHistory(masukDays, now, months: 12);
    final riwayat = await _riwayat30Hari(karyawanId);
    final security = _securityScore(karyawan);

    final jadwalHariIni = jadwalMinggu.cast<Map<String, String>?>().firstWhere(
          (j) => j?['date_key'] == today,
          orElse: () => null,
        );

    final tokoId = (karyawan['toko_id'] ?? '').toString();
    final homeExtras = await _loadHomeExtras(
      karyawanId: karyawanId,
      tokoId: tokoId,
      jadwalHariIni: jadwalHariIni,
    );

    final totalPoinClamped = totalPoin.clamp(-100000, 100000);
    KpiFireSnapshot kpiFire;
    try {
      kpiFire = await _kpiFire.computeMonth(
        karyawanId: karyawanId,
        tokoId: tokoId,
        jabatan: jabatan,
        totalPoinBulan: totalPoinClamped,
        now: now,
      );
    } catch (e) {
      debugPrint('kpi fire: $e');
      kpiFire = KpiFireSnapshot.empty().syncedWithPoints(totalPoinClamped);
    }

    List<KpiMonthHistoryRecord> kpiYearHistory;
    try {
      kpiYearHistory = await _kpiFire.loadYearHistory(
        karyawanId: karyawanId,
        now: now,
      );
      // Bulan ini: pakai total/target yang sama dengan snapshot hidup.
      if (kpiYearHistory.isNotEmpty) {
        final cur = kpiYearHistory.first;
        kpiYearHistory = [
          KpiMonthHistoryRecord(
            year: cur.year,
            month: cur.month,
            totalPoin: totalPoinClamped,
            pointTarget: kpiFire.pointTarget,
            workDays: cur.workDays,
            progress: kpiFire.progress,
            fire: kpiFire.fire,
          ),
          ...kpiYearHistory.skip(1),
        ];
      }
    } catch (e) {
      debugPrint('kpi year history: $e');
      kpiYearHistory = const [];
    }

    return KaryawanHomeSnapshot(
      karyawan: karyawan,
      jadwalMinggu: jadwalMinggu,
      sopTasks: sopTasks,
      // Biarkan negatif (penalti curang) tampil di APK.
      totalPoinBulan: totalPoinClamped,
      streakHari: streak,
      streakHariBulanIni: streakBulan,
      daysInMonth: daysInMonth,
      fireHistory: fireHistory,
      kpiYearHistory: kpiYearHistory,
      sudahKlaimHariIni: sudahKlaim,
      riwayat30Hari: riwayat,
      securityScore: security,
      kpiFire: kpiFire,
      jadwalHariIni: jadwalHariIni,
      absenStatus: homeExtras.absenStatus,
      absenMasukAt: homeExtras.absenMasukAt,
      absenPulangAt: homeExtras.absenPulangAt,
      hasOpenShift: homeExtras.hasOpenShift,
      pengajuanTerbaru: homeExtras.pengajuan,
      pengumuman: homeExtras.pengumuman,
    );
  }

  Future<
      ({
        String absenStatus,
        DateTime? absenMasukAt,
        DateTime? absenPulangAt,
        bool hasOpenShift,
        List<Map<String, dynamic>> pengajuan,
        List<Map<String, dynamic>> pengumuman,
      })> _loadHomeExtras({
    required String karyawanId,
    required String tokoId,
    required Map<String, String>? jadwalHariIni,
  }) async {
    DateTime? masukAt;
    DateTime? pulangAt;
    var hasOpen = false;
    var status = 'belum_masuk';
    var pengajuan = <Map<String, dynamic>>[];
    var pengumuman = <Map<String, dynamic>>[];

    try {
      final open = await _client
          .from('attendance_shifts')
          .select('id, status, masuk_at, pulang_at')
          .eq('karyawan_id', karyawanId)
          .eq('status', 'OPEN')
          .order('masuk_at', ascending: false)
          .limit(1)
          .maybeSingle();
      hasOpen = open != null;
      if (open != null) {
        masukAt = DateTime.tryParse((open['masuk_at'] ?? '').toString());
      }
    } catch (e) {
      debugPrint('home open shift: $e');
    }

    try {
      final start = _jakartaDayStartUtc();
      final end = start.add(const Duration(days: 1));
      final logs = await _client
          .from('attendance_logs')
          .select('tipe, created_at')
          .eq('karyawan_id', karyawanId)
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at');
      for (final raw in logs) {
        final row = Map<String, dynamic>.from(raw as Map);
        final tipe = (row['tipe'] ?? '').toString().toUpperCase();
        final at = DateTime.tryParse((row['created_at'] ?? '').toString());
        if (tipe == 'MASUK' && at != null) masukAt ??= at;
        if (tipe == 'PULANG' && at != null) pulangAt = at;
      }
    } catch (e) {
      debugPrint('home attendance logs: $e');
    }

    final shiftText = (jadwalHariIni?['shift'] ?? '').toLowerCase();
    final isLibur = shiftText.contains('libur');
    if (isLibur && masukAt == null && !hasOpen) {
      status = 'libur';
    } else if (pulangAt != null && !hasOpen) {
      status = 'selesai';
    } else if (hasOpen || masukAt != null) {
      status = 'sedang_bekerja';
    } else {
      status = 'belum_masuk';
    }

    try {
      final rows = await _client
          .from('jadwal_pengajuan')
          .select('id, tipe, tanggal, status, alasan, created_at')
          .eq('karyawan_id', karyawanId)
          .order('created_at', ascending: false)
          .limit(5);
      pengajuan = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('home pengajuan: $e');
    }

    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final tokoFilter = tokoId.isEmpty
          ? 'toko_id.is.null,toko_id.eq.PUSAT'
          : 'toko_id.is.null,toko_id.eq.PUSAT,toko_id.eq.$tokoId';
      final rows = await _client
          .from('pengumuman_cabang')
          .select('id, judul, isi, created_at, toko_id')
          .eq('aktif', true)
          .or('tampil_sampai.is.null,tampil_sampai.gte.$nowIso')
          .or(tokoFilter)
          .order('created_at', ascending: false)
          .limit(3);
      pengumuman = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      // Tabel belum dimigrasi → diam, kartu disembunyikan.
      debugPrint('home pengumuman: $e');
    }

    return (
      absenStatus: status,
      absenMasukAt: masukAt,
      absenPulangAt: pulangAt,
      hasOpenShift: hasOpen,
      pengajuan: pengajuan,
      pengumuman: pengumuman,
    );
  }

  DateTime _jakartaDayStartUtc([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final jkt = utc.add(const Duration(hours: 7));
    return DateTime.utc(jkt.year, jkt.month, jkt.day)
        .subtract(const Duration(hours: 7));
  }

  /// Backfill `poin_logs` dari verifikasi aman/curang + penalti telat di logs.
  /// Unique (karyawan, sumber, ref_id) mencegah double.
  Future<void> _syncAbsenPoinFromVerifications(String karyawanId) async {
    try {
      final rows = await _client
          .from('attendance_verifications')
          .select('id, status, poin_awarded, reviewed_at, created_at')
          .eq('karyawan_id', karyawanId)
          .inFilter('status', ['aman', 'curang'])
          .limit(200);

      for (final raw in rows) {
        final v = Map<String, dynamic>.from(raw as Map);
        final status = (v['status'] ?? '').toString();
        var points = (v['poin_awarded'] as num?)?.toInt() ?? 0;
        if (points == 0) {
          points = status == 'curang' ? -200 : 20;
        }
        final id = (v['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final refId = status == 'curang' ? 'absen-curang-$id' : 'absen-valid-$id';
        final when = DateTime.tryParse(
              (v['reviewed_at'] ?? v['created_at'] ?? '').toString(),
            ) ??
            DateTime.now();
        final tanggal = _dateKey.format(when.toLocal());
        await _insertPoinIgnoreDup(
          karyawanId: karyawanId,
          tanggal: tanggal,
          poin: points,
          sumber: 'ABSEN',
          refId: refId,
        );
      }

      // Heal ABSEN_TELAT hanya jika verifikasi sudah aman + telat
      // (poin belom ada sebelum Admin verifikasi).
      final lateVerified = await _client
          .from('attendance_verifications')
          .select(
            'id, log_id, poin_awarded, reviewed_at, created_at, '
            'log:log_id(id, late_penalty_points)',
          )
          .eq('karyawan_id', karyawanId)
          .eq('status', 'aman')
          .lt('poin_awarded', 0)
          .limit(200);
      for (final raw in lateVerified) {
        final v = Map<String, dynamic>.from(raw as Map);
        final log = v['log'];
        String? logId;
        var pts = (v['poin_awarded'] as num?)?.toInt() ?? 0;
        if (log is Map) {
          logId = (log['id'] ?? '').toString();
          final lp = (log['late_penalty_points'] as num?)?.toInt();
          if (lp != null && lp < 0) pts = lp;
        }
        logId ??= (v['log_id'] ?? '').toString();
        if (logId.isEmpty || pts >= 0) continue;
        final when = DateTime.tryParse(
              (v['reviewed_at'] ?? v['created_at'] ?? '').toString(),
            ) ??
            DateTime.now();
        await _insertPoinIgnoreDup(
          karyawanId: karyawanId,
          tanggal: _dateKey.format(when.toLocal()),
          poin: pts,
          sumber: 'ABSEN_TELAT',
          refId: 'absen-telat-$logId',
        );
      }
    } catch (_) {
      // Jangan gagalkan load home.
    }
  }

  Future<void> _insertPoinIgnoreDup({
    required String karyawanId,
    required String tanggal,
    required int poin,
    required String sumber,
    required String refId,
  }) async {
    try {
      await _client.from('poin_logs').insert({
        'karyawan_id': karyawanId,
        'tanggal': tanggal,
        'poin': poin,
        'sumber': sumber,
        'ref_id': refId,
      });
    } catch (_) {
      // Unique / RLS — sudah ada, jangan double.
    }
  }

  /// Jumlahkan poin verifikasi bulan ini yang belum masuk `poin_logs`.
  Future<int> _absenPoinFromVerificationsMissingInLogs({
    required String karyawanId,
    required String monthStartKey,
    required Set<String> existingRefs,
  }) async {
    try {
      final rows = await _client
          .from('attendance_verifications')
          .select('id, status, poin_awarded, reviewed_at, created_at')
          .eq('karyawan_id', karyawanId)
          .inFilter('status', ['aman', 'curang'])
          .limit(200);

      var extra = 0;
      for (final raw in rows) {
        final v = Map<String, dynamic>.from(raw as Map);
        final status = (v['status'] ?? '').toString();
        final id = (v['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final refId = status == 'curang' ? 'absen-curang-$id' : 'absen-valid-$id';
        if (existingRefs.contains(refId)) continue;

        final when = DateTime.tryParse(
              (v['reviewed_at'] ?? v['created_at'] ?? '').toString(),
            ) ??
            DateTime.now();
        final tanggal = _dateKey.format(when.toLocal());
        if (tanggal.compareTo(monthStartKey) < 0) continue;

        var points = (v['poin_awarded'] as num?)?.toInt() ?? 0;
        if (points == 0) {
          points = status == 'curang' ? -200 : 20;
        }
        extra += points;
      }
      return extra;
    } catch (_) {
      return 0;
    }
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

  /// Serialize reminder upserts so concurrent home refreshes don't twin-insert.
  static Future<void>? _ensureRemindersInFlight;

  Future<void> ensureTodayReminders({
    required String karyawanId,
    required List<Map<String, String>> jadwalMinggu,
    required List<Map<String, dynamic>> sopTasks,
  }) {
    final prev = _ensureRemindersInFlight;
    late final Future<void> run;
    run = () async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      await _ensureTodayRemindersBody(
        karyawanId: karyawanId,
        jadwalMinggu: jadwalMinggu,
        sopTasks: sopTasks,
      );
    }();
    _ensureRemindersInFlight = run;
    return run;
  }

  Future<void> _ensureTodayRemindersBody({
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
        .select('id, tipe, judul, created_at')
        .eq('user_id', uid)
        .gte(
            'created_at',
            DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 20))
                .toIso8601String())
        .order('created_at', ascending: false);

    const dailyKeys = {
      'SOP|SOP belum selesai',
      'SHIFT|Jadwal hari ini',
    };
    final titles = <String>{};
    final dupIds = <String>[];
    for (final n in existing) {
      final key = '${n['tipe']}|${n['judul']}';
      if (!titles.add(key) && dailyKeys.contains(key)) {
        final id = n['id']?.toString();
        if (id != null && id.isNotEmpty) dupIds.add(id);
      }
    }

    // Clean twin daily reminders left by earlier race inserts.
    if (dupIds.isNotEmpty) {
      try {
        await _client.from('notifikasi').delete().inFilter('id', dupIds);
      } catch (e) {
        debugPrint('ensureTodayReminders dedupe: $e');
      }
    }

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
        titles.add(key);
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
        titles.add(key);
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

  /// Set tanggal `yyyy-MM-dd` yang punya absen MASUK (lokal).
  Future<Set<String>> _loadMasukDays(
    String karyawanId, {
    int monthsBack = 12,
  }) async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - monthsBack, 1);
    final rows = await _client
        .from('attendance_logs')
        .select('created_at')
        .eq('karyawan_id', karyawanId)
        .eq('tipe', 'MASUK')
        .gte('created_at', from.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(400);

    final days = <String>{};
    for (final r in rows) {
      final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
      if (dt != null) {
        days.add(_dateKey.format(dt.toLocal()));
      }
    }
    return days;
  }

  int _streakFromDays(Set<String> days, DateTime now) {
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
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

  /// Streak beruntun yang masih berada di bulan kalender [now].
  /// Bulan baru → hitungan api mulai dari 0 lagi.
  int _streakInCalendarMonth(Set<String> days, DateTime now) {
    final monthStart = DateTime(now.year, now.month, 1);
    var streak = 0;
    var cursor = DateTime(now.year, now.month, now.day);
    if (!days.contains(_dateKey.format(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (
        !cursor.isBefore(monthStart) && days.contains(_dateKey.format(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Peak streak beruntun di dalam bulan [year]/[month].
  int _peakStreakInMonth(Set<String> days, int year, int month) {
    final dim = DateTime(year, month + 1, 0).day;
    var peak = 0;
    var run = 0;
    for (var d = 1; d <= dim; d++) {
      final key = _dateKey.format(DateTime(year, month, d));
      if (days.contains(key)) {
        run++;
        if (run > peak) peak = run;
      } else {
        run = 0;
      }
    }
    return peak;
  }

  List<StreakFireMonthRecord> _buildFireHistory(
    Set<String> days,
    DateTime now, {
    int months = 12,
  }) {
    final out = <StreakFireMonthRecord>[];
    for (var i = 0; i < months; i++) {
      final cursor = DateTime(now.year, now.month - i, 1);
      final y = cursor.year;
      final m = cursor.month;
      final dim = DateTime(y, m + 1, 0).day;
      final achieved = i == 0
          ? _streakInCalendarMonth(days, now)
          : _peakStreakInMonth(days, y, m);
      // Lewati bulan lama yang benar-benar kosong (kecuali bulan ini).
      if (i > 0 && achieved <= 0) continue;
      out.add(
        StreakFireMonthRecord(
          year: y,
          month: m,
          daysInMonth: dim,
          daysAchieved: achieved,
          fire: StreakFireLevel.forMonth(
            daysInMonthProgress: achieved,
            daysInMonth: dim,
          ),
        ),
      );
    }
    return out;
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
      if (pts < 0) {
        // Hari kena penalti (mis. curang) — bedakan dari kosong.
        out.add(-1);
      } else if (pts >= 35) {
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
