import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_verification_config.dart';
import 'shift_auto_assign.dart';
import 'streak_fire_level.dart';

/// Snapshot Api KPI bulan berjalan (per toko, bukan nasional).
class KpiFireSnapshot {
  const KpiFireSnapshot({
    required this.progress,
    required this.totalPoin,
    required this.pointTarget,
    required this.sTetap,
    required this.sToko,
    required this.fairShare,
    required this.aktualPct,
    required this.unitOrang,
    required this.unitTim,
    required this.peerCount,
    required this.hariValid,
    required this.layer,
    required this.fire,
  });

  /// 0…1 dari total poin bulan / [pointTarget] — penentu level api.
  final double progress;

  /// Total poin_logs bulan ini (sumber tunggal level + angka banner).
  final int totalPoin;

  /// Target 100% / level 5 — lihat [targetFromWorkDays].
  final int pointTarget;
  final double sTetap;
  final double sToko;

  /// Fair share se-jalur di toko (1/n) — info balance, bukan penentu level.
  final double fairShare;
  final double aktualPct;
  final int unitOrang;
  final int unitTim;
  final int peerCount;
  final int hariValid;
  final OfficeLayer layer;
  final StreakFireLevel fire;

  static const weightTetap = 0.40;
  static const weightToko = 0.60;

  /// Absen ontime (Admin Valid) — samakan dengan config absensi.
  static const absenOntimePoints = AttendanceVerificationConfig.validDayPoints;

  /// Envelope skor tetap: absen ontime 20 + SOP ±25 → −25…+45.
  static const sopEnvelope = 25;
  static const tetapMinDaily = -sopEnvelope;
  static const tetapEnvelope = absenOntimePoints + sopEnvelope; // 45

  /// SOP penuh (semua komponen beres) = +25.
  static const sopTypicalDaily = sopEnvelope;

  /// Inti poin hari kerja bila absen ontime + SOP penuh.
  static const dailyCorePoints = absenOntimePoints + sopTypicalDaily; // 45

  /// Fallback hari kerja/bulan toko (~Sen–Sab, ± libur nasional).
  static const fallbackWorkDays = 26;

  /// Rentang tipikal hari kerja per bulan kalender.
  static const minWorkDays = 26;
  static const maxWorkDays = 27;

  /// Alias UI — fallback 26×45.
  static const monthlyPointTarget = fallbackWorkDays * dailyCorePoints; // 1170

  /// Target level 5 = hari kerja terjadwal bulan ini × inti harian 45.
  /// Kalau jadwal ada: pakai jumlah aktual (clamp 26–27).
  /// Kalau belum ada jadwal: fallback 26 hari.
  static int targetFromWorkDays(int scheduledWorkDays) {
    final days = scheduledWorkDays > 0
        ? scheduledWorkDays.clamp(minWorkDays, maxWorkDays)
        : fallbackWorkDays;
    return days * dailyCorePoints;
  }

  /// Progres 0…1 dari poin aktual — satu sumber untuk level & UI.
  static double progressFromPoints(int totalPoin, {required int target}) {
    if (totalPoin <= 0 || target <= 0) return 0;
    return (totalPoin / target).clamp(0.0, 1.0);
  }

  /// Poin per band level (+20% target). Mis. target 1040 → 208.
  static int pointsPerLevel(int target) {
    final t = target > 0 ? target : monthlyPointTarget;
    return (t / 5).round().clamp(1, t);
  }

  /// Rentang poin untuk level 1…5 — selaras [StreakFireLevel.forKpiProgress].
  /// L1: 0…20% · L2: 20%+1…40% · … · L5: 80%+1…100%.
  static ({int lo, int hi}) pointBandForLevel(int level, int target) {
    final t = target > 0 ? target : monthlyPointTarget;
    final lv = level.clamp(1, 5);
    final band = pointsPerLevel(t);
    if (lv == 1) {
      return (lo: 0, hi: band);
    }
    final lo = (lv - 1) * band + 1;
    final hi = lv >= 5 ? t : lv * band;
    return (lo: lo, hi: hi);
  }

  /// Poin minimum untuk masuk [level] (2…5). Level 1 = 0.
  static int minPointsForLevel(int level, int target) {
    final lv = level.clamp(1, 5);
    if (lv <= 1) return 0;
    return pointBandForLevel(lv, target).lo;
  }

  /// Sisa poin ke level berikutnya (0 kalau sudah max).
  int pointsToNextLevel() {
    final lv = fire.level.clamp(1, 5);
    if (lv >= 5) return 0;
    final need = minPointsForLevel(lv + 1, pointTarget);
    return (need - totalPoin).clamp(0, pointTarget);
  }

  /// Sinkronkan level/progres ke [poin] (harus dipanggil tiap kali poin berubah).
  KpiFireSnapshot syncedWithPoints(int poin) {
    final target = pointTarget > 0 ? pointTarget : monthlyPointTarget;
    final p = progressFromPoints(poin, target: target);
    return KpiFireSnapshot(
      progress: p,
      totalPoin: poin,
      pointTarget: target,
      sTetap: sTetap,
      sToko: sToko,
      fairShare: fairShare,
      aktualPct: aktualPct,
      unitOrang: unitOrang,
      unitTim: unitTim,
      peerCount: peerCount,
      hariValid: hariValid,
      layer: layer,
      fire: StreakFireLevel.forKpiProgress(p),
    );
  }

  factory KpiFireSnapshot.empty({OfficeLayer layer = OfficeLayer.front}) {
    return KpiFireSnapshot(
      progress: 0,
      totalPoin: 0,
      pointTarget: monthlyPointTarget,
      sTetap: 0,
      sToko: 0,
      fairShare: 0,
      aktualPct: 0,
      unitOrang: 0,
      unitTim: 0,
      peerCount: 0,
      hariValid: 0,
      layer: layer,
      fire: StreakFireLevel.forKpiProgress(0),
    );
  }
}

/// Ringkasan Api KPI satu bulan kalender (untuk riwayat setahun).
class KpiMonthHistoryRecord {
  const KpiMonthHistoryRecord({
    required this.year,
    required this.month,
    required this.totalPoin,
    required this.pointTarget,
    required this.workDays,
    required this.fire,
    required this.progress,
  });

  final int year;
  final int month;
  final int totalPoin;
  final int pointTarget;
  final int workDays;
  final StreakFireLevel fire;
  final double progress;

  bool get isEmptyMonth => totalPoin == 0;

  String get monthKey =>
      '$year-${month.toString().padLeft(2, '0')}';
}

/// Hitung progres Api KPI: absen/SOP tetap + % fair share per toko.
class KpiFireService {
  KpiFireService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;
  static final _dateKey = DateFormat('yyyy-MM-dd');

  Future<KpiFireSnapshot> computeMonth({
    required String karyawanId,
    required String tokoId,
    required String? jabatan,
    required int totalPoinBulan,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final layer = officeLayerOf(jabatan);
    final monthStart = DateTime(n.year, n.month, 1);
    final monthEnd = DateTime(n.year, n.month + 1, 0);
    final today = DateTime(n.year, n.month, n.day);
    final startKey = _dateKey.format(monthStart);
    final endKey = _dateKey.format(monthEnd);
    final todayKey = _dateKey.format(today);
    final tid = tokoId.trim();

    if (karyawanId.isEmpty || tid.isEmpty) {
      return KpiFireSnapshot.empty(layer: layer).syncedWithPoints(totalPoinBulan);
    }

    // Jadwal sebulan penuh → target realistis; validDays ≤ hari ini untuk skor tetap.
    final monthWorkDays = await _validWorkDays(
      karyawanId: karyawanId,
      startKey: startKey,
      endKey: endKey,
    );
    final validDays = monthWorkDays
        .where((d) => d.compareTo(todayKey) <= 0)
        .toSet();
    final pointTarget =
        KpiFireSnapshot.targetFromWorkDays(monthWorkDays.length);

    final sTetap = await _scoreTetap(
      karyawanId: karyawanId,
      validDays: validDays,
      startKey: startKey,
      endKey: todayKey,
    );

    final tokoScore = await _scoreToko(
      karyawanId: karyawanId,
      tokoId: tid,
      layer: layer,
      startKey: startKey,
      endKey: endKey,
    );

    // Level & progres api = total poin bulan / target hari-kerja×40.
    final progress = KpiFireSnapshot.progressFromPoints(
      totalPoinBulan,
      target: pointTarget,
    );

    return KpiFireSnapshot(
      progress: progress,
      totalPoin: totalPoinBulan,
      pointTarget: pointTarget,
      sTetap: sTetap,
      sToko: tokoScore.sToko,
      fairShare: tokoScore.fair,
      aktualPct: tokoScore.aktual,
      unitOrang: tokoScore.unitOrang,
      unitTim: tokoScore.unitTim,
      peerCount: tokoScore.peers,
      hariValid: validDays.length,
      layer: layer,
      fire: StreakFireLevel.forKpiProgress(progress),
    );
  }

  /// Riwayat Jan tahun lalu → bulan ini (cukup untuk kalender 2 tahun).
  /// Level tiap bulan dari total poin_logs / target hari kerja terjadwal.
  Future<List<KpiMonthHistoryRecord>> loadYearHistory({
    required String karyawanId,
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final start = DateTime(n.year - 1, 1, 1);
    final end = DateTime(n.year, n.month + 1, 0);
    final startKey = _dateKey.format(start);
    final endKey = _dateKey.format(end);
    final kid = karyawanId.trim();
    if (kid.isEmpty) return const [];

    final poinByMonth = <String, int>{};
    try {
      final rows = await _db
          .from('poin_logs')
          .select('poin, tanggal')
          .eq('karyawan_id', kid)
          .gte('tanggal', startKey)
          .lte('tanggal', endKey);
      for (final r in rows as List) {
        final t = r['tanggal']?.toString() ?? '';
        if (t.length < 7) continue;
        final key = t.substring(0, 7); // yyyy-MM
        poinByMonth[key] =
            (poinByMonth[key] ?? 0) + ((r['poin'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}

    final workDaysByMonth = <String, int>{};
    try {
      final jadwal = await _db
          .from('jadwal_kerja')
          .select('tanggal, is_libur')
          .eq('karyawan_id', kid)
          .gte('tanggal', startKey)
          .lte('tanggal', endKey);
      for (final r in jadwal as List) {
        if (r['is_libur'] == true) continue;
        final t = r['tanggal']?.toString() ?? '';
        if (t.length < 7) continue;
        final key = t.substring(0, 7);
        workDaysByMonth[key] = (workDaysByMonth[key] ?? 0) + 1;
      }
    } catch (_) {}

    final out = <KpiMonthHistoryRecord>[];
    // Urutan terbaru dulu: bulan ini → mundur sampai Jan tahun lalu.
    var cursor = DateTime(n.year, n.month, 1);
    final stop = start;
    while (!cursor.isBefore(stop)) {
      final key =
          '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}';
      final poin = poinByMonth[key] ?? 0;
      final workDays = workDaysByMonth[key] ?? 0;
      final target = KpiFireSnapshot.targetFromWorkDays(workDays);
      final progress =
          KpiFireSnapshot.progressFromPoints(poin, target: target);
      out.add(
        KpiMonthHistoryRecord(
          year: cursor.year,
          month: cursor.month,
          totalPoin: poin,
          pointTarget: target,
          workDays: workDays > 0
              ? workDays.clamp(
                  KpiFireSnapshot.minWorkDays,
                  KpiFireSnapshot.maxWorkDays,
                )
              : KpiFireSnapshot.fallbackWorkDays,
          progress: progress,
          fire: StreakFireLevel.forKpiProgress(progress),
        ),
      );
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
    }
    return out;
  }

  /// Hari jadwal kerja (bukan libur) ∩ belum ijin/cuti approved ∩ ≤ hari ini.
  Future<Set<String>> _validWorkDays({
    required String karyawanId,
    required String startKey,
    required String endKey,
  }) async {
    final jadwal = await _db
        .from('jadwal_kerja')
        .select('tanggal, is_libur')
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', startKey)
        .lte('tanggal', endKey);

    final leave = <String>{};
    try {
      final rows = await _db
          .from('jadwal_pengajuan')
          .select('tanggal, tipe, status')
          .eq('karyawan_id', karyawanId)
          .eq('status', 'APPROVED')
          .gte('tanggal', startKey)
          .lte('tanggal', endKey);
      for (final r in rows as List) {
        final tipe = (r['tipe'] ?? '').toString().toUpperCase();
        if (tipe == 'IJIN' || tipe == 'CUTI') {
          final t = r['tanggal']?.toString();
          if (t != null && t.isNotEmpty) leave.add(t.length >= 10 ? t.substring(0, 10) : t);
        }
      }
    } catch (_) {}

    final out = <String>{};
    for (final r in jadwal as List) {
      if (r['is_libur'] == true) continue;
      final t = r['tanggal']?.toString() ?? '';
      final key = t.length >= 10 ? t.substring(0, 10) : t;
      if (key.isEmpty || leave.contains(key)) continue;
      out.add(key);
    }
    return out;
  }

  Future<double> _scoreTetap({
    required String karyawanId,
    required Set<String> validDays,
    required String startKey,
    required String endKey,
  }) async {
    if (validDays.isEmpty) return 0;

    final rows = await _db
        .from('poin_logs')
        .select('poin, tanggal, sumber')
        .eq('karyawan_id', karyawanId)
        .gte('tanggal', startKey)
        .lte('tanggal', endKey);

    final perDay = <String, int>{};
    for (final r in rows as List) {
      final sumber = (r['sumber'] ?? '').toString().toUpperCase();
      // Tetap: absen ontime + SOP saja (bukan telat/curang/invoice/lab).
      if (sumber != AttendanceVerificationConfig.sumberPoinAbsen &&
          sumber != 'SOP') {
        continue;
      }
      final t = r['tanggal']?.toString() ?? '';
      final key = t.length >= 10 ? t.substring(0, 10) : t;
      if (!validDays.contains(key)) continue;
      perDay[key] = (perDay[key] ?? 0) + ((r['poin'] as num?)?.toInt() ?? 0);
    }

    var sum = 0.0;
    final span = (KpiFireSnapshot.tetapEnvelope - KpiFireSnapshot.tetapMinDaily)
        .clamp(1, 9999);
    for (final day in validDays) {
      final raw = perDay[day] ?? 0;
      final clipped = raw.clamp(
        KpiFireSnapshot.tetapMinDaily,
        KpiFireSnapshot.tetapEnvelope,
      );
      final s = (clipped - KpiFireSnapshot.tetapMinDaily) / span;
      sum += s.clamp(0.0, 1.0);
    }
    return (sum / validDays.length).clamp(0.0, 1.0);
  }

  Future<
      ({
        double sToko,
        double fair,
        double aktual,
        int unitOrang,
        int unitTim,
        int peers,
      })> _scoreToko({
    required String karyawanId,
    required String tokoId,
    required OfficeLayer layer,
    required String startKey,
    required String endKey,
  }) async {
    final peers = await _peerIdsSameLayer(tokoId: tokoId, layer: layer);
    if (peers.isEmpty) {
      return (
        sToko: 0.0,
        fair: 0.0,
        aktual: 0.0,
        unitOrang: 0,
        unitTim: 0,
        peers: 0,
      );
    }

    final fair = 1.0 / peers.length;
    late final int unitOrang;
    late final int unitTim;

    if (layer == OfficeLayer.front) {
      final counts = await _frontUnitsByKaryawan(
        tokoId: tokoId,
        peerIds: peers,
        startKey: startKey,
        endKey: endKey,
      );
      unitOrang = counts[karyawanId] ?? 0;
      unitTim = counts.values.fold<int>(0, (a, b) => a + b);
    } else {
      final counts = await _backUnitsByKaryawan(
        tokoId: tokoId,
        peerIds: peers,
        startKey: startKey,
        endKey: endKey,
      );
      unitOrang = counts[karyawanId] ?? 0;
      unitTim = counts.values.fold<int>(0, (a, b) => a + b);
    }

    if (unitTim <= 0) {
      return (
        sToko: 0.0,
        fair: fair,
        aktual: 0.0,
        unitOrang: unitOrang,
        unitTim: 0,
        peers: peers.length,
      );
    }

    final aktual = unitOrang / unitTim;
    final sToko = (aktual / fair).clamp(0.0, 1.0);
    return (
      sToko: sToko,
      fair: fair,
      aktual: aktual,
      unitOrang: unitOrang,
      unitTim: unitTim,
      peers: peers.length,
    );
  }

  Future<List<String>> _peerIdsSameLayer({
    required String tokoId,
    required OfficeLayer layer,
  }) async {
    final rows = await _db
        .from('karyawan')
        .select('id, jabatan, status_approval')
        .eq('toko_id', tokoId);

    final ids = <String>[];
    for (final r in rows as List) {
      final status = (r['status_approval'] ?? '').toString().toLowerCase().trim();
      if (status != 'aktif' && status != 'active' && status != 'approved') {
        continue;
      }
      if (officeLayerOf(r['jabatan']?.toString()) != layer) continue;
      final id = r['id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Future<Map<String, int>> _frontUnitsByKaryawan({
    required String tokoId,
    required List<String> peerIds,
    required String startKey,
    required String endKey,
  }) async {
    // Sales cabang bulan ini → terlibat.
    final sales = await _db
        .from('sales')
        .select('id')
        .eq('toko_id', tokoId)
        .gte('created_at', '${startKey}T00:00:00')
        .lte('created_at', '${endKey}T23:59:59');

    final saleIds = <String>[
      for (final s in sales as List)
        if (s['id'] != null) s['id'].toString(),
    ];
    if (saleIds.isEmpty) return {for (final id in peerIds) id: 0};

    final counts = {for (final id in peerIds) id: 0};
    // Chunk inFilter biar aman.
    const chunk = 80;
    for (var i = 0; i < saleIds.length; i += chunk) {
      final slice = saleIds.sublist(
        i,
        i + chunk > saleIds.length ? saleIds.length : i + chunk,
      );
      final rows = await _db
          .from('sales_karyawan_terlibat')
          .select('karyawan_id, sale_id')
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

  Future<Map<String, int>> _backUnitsByKaryawan({
    required String tokoId,
    required List<String> peerIds,
    required String startKey,
    required String endKey,
  }) async {
    final counts = {for (final id in peerIds) id: 0};
    final sales = await _db
        .from('sales')
        .select('pembuat_kacamata_id')
        .eq('toko_id', tokoId)
        .gte('created_at', '${startKey}T00:00:00')
        .lte('created_at', '${endKey}T23:59:59')
        .not('pembuat_kacamata_id', 'is', null);

    for (final s in sales as List) {
      final kid = s['pembuat_kacamata_id']?.toString();
      if (kid != null && counts.containsKey(kid)) {
        counts[kid] = (counts[kid] ?? 0) + 1;
      }
    }
    return counts;
  }
}
