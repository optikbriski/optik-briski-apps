import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../attendance/attendance_dinas.dart';
import '../attendance/attendance_service.dart';
import '../tenant/tenant_service.dart';
import 'contribution_rekap.dart';
import 'contribution_rekap_service.dart';
import 'shift_auto_assign.dart';
import 'sop_daily_service.dart';
import 'sop_score.dart';

enum WorkDutyStatus { libur, belumMasuk, bertugas, pulang, noJadwal }

WorkDutyStatus workDutyStatus({
  required bool hasJadwal,
  required bool isLibur,
  required bool hasOpenShift,
  required bool hasMasuk,
  required bool hasPulang,
}) {
  if (!hasJadwal) return WorkDutyStatus.noJadwal;
  if (isLibur && !hasOpenShift && !hasMasuk) return WorkDutyStatus.libur;
  if (hasPulang && !hasOpenShift) return WorkDutyStatus.pulang;
  if (hasOpenShift || hasMasuk) return WorkDutyStatus.bertugas;
  return WorkDutyStatus.belumMasuk;
}

class WorkSummaryPerson {
  const WorkSummaryPerson({
    required this.id,
    required this.nama,
    required this.jabatan,
    required this.layer,
    required this.status,
    required this.sopPoin,
    required this.fatalStory,
    this.jamMasuk,
    this.jamPulang,
  });

  final String id;
  final String nama;
  final String jabatan;
  final OfficeLayer layer;
  final WorkDutyStatus status;
  final int sopPoin;
  final bool fatalStory;
  final String? jamMasuk;
  final String? jamPulang;
}

class WorkSummarySnapshot {
  const WorkSummarySnapshot({
    required this.tokoId,
    required this.tanggal,
    required this.sop,
    required this.people,
    required this.frontMonth,
    required this.backMonth,
  });

  final String tokoId;
  final String tanggal;
  final SopBranchState sop;
  final List<WorkSummaryPerson> people;
  final ContributionRekap frontMonth;
  final ContributionRekap backMonth;

  int get countBertugas =>
      people.where((p) => p.status == WorkDutyStatus.bertugas).length;
  int get countBelum =>
      people.where((p) => p.status == WorkDutyStatus.belumMasuk).length;
  int get countLibur =>
      people.where((p) => p.status == WorkDutyStatus.libur).length;
  int get countPulang =>
      people.where((p) => p.status == WorkDutyStatus.pulang).length;
}

/// Rangkuman kerja cabang: SOP hari ini + siapa bertugas + rekap bulan.
class WorkSummaryService {
  WorkSummaryService({
    SupabaseClient? client,
    SopDailyService? sop,
    ContributionRekapService? rekap,
  })  : _db = client ?? Supabase.instance.client,
        _sop = sop ?? SopDailyService(client: client),
        _rekap = rekap ?? ContributionRekapService(client: client);

  final SupabaseClient _db;
  final SopDailyService _sop;
  final ContributionRekapService _rekap;

  Future<WorkSummarySnapshot> load({
    required String tokoId,
    DateTime? now,
    bool forceStoryRefresh = false,
  }) async {
    final n = now ?? DateTime.now();
    final day = AttendanceDinas.todayKey(n);
    final keys = AttendanceAdminScope.storeIdAliases(tokoId);
    final storeKeys = keys.isEmpty ? [tokoId.trim()] : keys;
    final tid = TenantService.instance.id;

    final sop = await _sop.fetchBranchState(
      tokoId: tokoId,
      tanggal: day,
      forceStoryRefresh: forceStoryRefresh,
    );
    final staff = await _aktifStaff(keys: storeKeys, tenantId: tid);
    final ids = staff.map((s) => s.id).toList();

    final jadwal = await _jadwalHariIni(ids: ids, day: day);
    final shifts = await _shiftsHariIni(
      ids: ids,
      day: n,
      storeKeys: storeKeys,
      tenantId: tid,
    );

    final people = <WorkSummaryPerson>[
      for (final s in staff)
        _person(
          staff: s,
          jadwal: jadwal[s.id],
          shift: shifts[s.id],
          sop: sop,
        ),
    ]..sort((a, b) {
        final la = a.layer == OfficeLayer.front ? 0 : 1;
        final lb = b.layer == OfficeLayer.front ? 0 : 1;
        if (la != lb) return la.compareTo(lb);
        final sa = _statusRank(a.status);
        final sb = _statusRank(b.status);
        if (sa != sb) return sa.compareTo(sb);
        return a.nama.toLowerCase().compareTo(b.nama.toLowerCase());
      });

    final front = await _rekap.loadMonthForLayer(
      tokoId: tokoId,
      layer: OfficeLayer.front,
      now: AttendanceDinas.nowWall(n),
    );
    final back = await _rekap.loadMonthForLayer(
      tokoId: tokoId,
      layer: OfficeLayer.back,
      now: AttendanceDinas.nowWall(n),
    );

    return WorkSummarySnapshot(
      tokoId: tokoId,
      tanggal: day,
      sop: sop,
      people: people,
      frontMonth: front,
      backMonth: back,
    );
  }

  static int _statusRank(WorkDutyStatus s) {
    return switch (s) {
      WorkDutyStatus.bertugas => 0,
      WorkDutyStatus.belumMasuk => 1,
      WorkDutyStatus.pulang => 2,
      WorkDutyStatus.noJadwal => 3,
      WorkDutyStatus.libur => 4,
    };
  }

  WorkSummaryPerson _person({
    required ({String id, String nama, String jabatan}) staff,
    required Map<String, dynamic>? jadwal,
    required Map<String, dynamic>? shift,
    required SopBranchState sop,
  }) {
    final hasJadwal = jadwal != null;
    final isLibur = _asBool(jadwal?['is_libur']);
    final jamMasuk = jadwal?['jam_masuk']?.toString();
    final jamPulang = jadwal?['jam_pulang']?.toString();
    final statusShift = (shift?['status'] ?? '').toString().toUpperCase();
    final hasOpen = statusShift == 'OPEN';
    final hasMasuk = shift?['masuk_at'] != null;
    final hasPulang = shift?['pulang_at'] != null;
    final status = workDutyStatus(
      hasJadwal: hasJadwal,
      isLibur: isLibur,
      hasOpenShift: hasOpen,
      hasMasuk: hasMasuk,
      hasPulang: hasPulang,
    );
    final layer = officeLayerOf(staff.jabatan);
    final isAktif = hasJadwal && !isLibur;
    final score = SopScore.compute(
      SopScoreInput(
        layer: layer,
        isPagi: SopScore.isPagiShift(jamMasuk: jamMasuk),
        isAktif: isAktif,
        isLibur: isLibur || !hasJadwal,
        storyCount: sop.storyCount,
        displayDone: sop.displayDone,
        displayRequired: sop.displayRequired,
        stokDone: sop.stokDone,
        sapuDone: sop.sapuDone,
      ),
    );
    return WorkSummaryPerson(
      id: staff.id,
      nama: staff.nama,
      jabatan: staff.jabatan,
      layer: layer,
      status: status,
      sopPoin: score.poin,
      fatalStory: score.fatalStory,
      jamMasuk: _hhmm(jamMasuk),
      jamPulang: _hhmm(jamPulang),
    );
  }

  static bool _asBool(dynamic v) {
    if (v == true) return true;
    if (v == false || v == null) return false;
    final s = v.toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 't' || s == 'yes';
  }

  String? _hhmm(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
    if (m == null) return s;
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }

  Future<List<({String id, String nama, String jabatan})>> _aktifStaff({
    required List<String> keys,
    required String? tenantId,
  }) async {
    if (keys.isEmpty) return const [];
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

  Future<Map<String, Map<String, dynamic>>> _jadwalHariIni({
    required List<String> ids,
    required String day,
  }) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;
    final rows = await _db
        .from('jadwal_kerja')
        .select('karyawan_id, jam_masuk, jam_pulang, is_libur')
        .inFilter('karyawan_id', ids)
        .eq('tanggal', day);
    for (final r in rows as List) {
      final id = r['karyawan_id']?.toString();
      if (id == null || id.isEmpty) continue;
      out[id] = Map<String, dynamic>.from(r as Map);
    }
    return out;
  }

  Future<Map<String, Map<String, dynamic>>> _shiftsHariIni({
    required List<String> ids,
    required DateTime day,
    required List<String> storeKeys,
    required String? tenantId,
  }) async {
    final out = <String, Map<String, dynamic>>{};
    if (ids.isEmpty) return out;
    final start = AttendanceService.jakartaDayStartUtc(day);
    final end = start.add(const Duration(days: 1));

    Future<List<dynamic>> openRows() async {
      var q = _db
          .from('attendance_shifts')
          .select('karyawan_id, status, masuk_at, pulang_at, toko_id')
          .inFilter('karyawan_id', ids)
          .eq('status', 'OPEN');
      if (storeKeys.isNotEmpty) q = q.inFilter('toko_id', storeKeys);
      if (tenantId != null && tenantId.isNotEmpty) {
        q = q.eq('tenant_id', tenantId);
      }
      return await q as List<dynamic>;
    }

    try {
      for (final r in await openRows()) {
        final id = r['karyawan_id']?.toString();
        if (id == null || id.isEmpty) continue;
        out[id] = Map<String, dynamic>.from(r as Map);
      }
    } catch (_) {}

    var todayQ = _db
        .from('attendance_shifts')
        .select('karyawan_id, status, masuk_at, pulang_at, toko_id')
        .inFilter('karyawan_id', ids)
        .gte('masuk_at', start.toIso8601String())
        .lt('masuk_at', end.toIso8601String());
    if (storeKeys.isNotEmpty) todayQ = todayQ.inFilter('toko_id', storeKeys);
    if (tenantId != null && tenantId.isNotEmpty) {
      todayQ = todayQ.eq('tenant_id', tenantId);
    }
    final rows = await todayQ.order('masuk_at', ascending: false);
    for (final r in rows as List) {
      final id = r['karyawan_id']?.toString();
      if (id == null || id.isEmpty || out.containsKey(id)) continue;
      out[id] = Map<String, dynamic>.from(r as Map);
    }
    return out;
  }
}
