import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../bootstrap.dart';
import '../tenant/tenant_service.dart';
import 'payroll_compute_engine.dart';

/// Admin + Karyawan payroll API (flexible, Admin-driven).
class PayrollService {
  PayrollService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> listTemplates({String? tokoId}) async {
    final rows = await _db.from('payroll_rule_templates').select().order('nama');
    final all = PayrollComputeEngine.asMapList(rows);
    final id = (tokoId ?? '').trim();
    if (id.isEmpty) return all;
    return [
      for (final t in all)
        if (t['toko_id'] == null || t['toko_id'].toString() == id) t,
    ];
  }

  Future<Map<String, dynamic>> upsertTemplate({
    String? id,
    required String nama,
    String? tokoId,
    required List<Map<String, dynamic>> components,
    bool aktif = true,
  }) async {
    final tid = TenantService.instance.id;
    final payload = <String, dynamic>{
      'nama': nama.trim(),
      'toko_id': (tokoId ?? '').trim().isEmpty ? null : tokoId!.trim(),
      'components': components,
      'aktif': aktif,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (tid != null && tid.isNotEmpty) 'tenant_id': tid,
    };
    if (id != null && id.isNotEmpty) {
      final row = await _db
          .from('payroll_rule_templates')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      return Map<String, dynamic>.from(row);
    }
    final row =
        await _db.from('payroll_rule_templates').insert(payload).select().single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> deleteTemplate(String id) async {
    await _db.from('payroll_rule_templates').delete().eq('id', id);
  }

  /// Group apply: same template + overrides to many karyawan.
  Future<Map<String, dynamic>> assignToGroup({
    required List<String> karyawanIds,
    String? templateId,
    Map<String, dynamic> overrides = const {},
  }) async {
    final res = await _db.rpc('admin_upsert_payroll_assignments', params: {
      'p_karyawan_ids': karyawanIds,
      'p_template_id': templateId,
      'p_overrides': overrides,
    });
    final map = PayrollComputeEngine.asMap(res);
    return map.isEmpty ? {'ok': true} : map;
  }

  Future<Map<String, dynamic>?> assignmentFor(String karyawanId) async {
    final row = await _db
        .from('payroll_rule_assignments')
        .select()
        .eq('karyawan_id', karyawanId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  /// Rate lembur dari assignment (overrides), 0 jika belum di-set Admin.
  Future<int> overtimeRateFor(String karyawanId) async {
    final a = await assignmentFor(karyawanId);
    if (a == null) return 0;
    final ov = a['overrides'];
    if (ov is Map) {
      return PayrollComputeEngine.asInt(ov['overtime_rate_rp']);
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> listAssignmentsForToko(String tokoId) async {
    final kary = await _db
        .from('karyawan')
        .select('id, nama, jabatan, gaji_pokok, nama_bank, no_rekening, status_approval')
        .eq('toko_id', tokoId)
        .eq('status_approval', 'Aktif')
        .order('nama');
    final list = PayrollComputeEngine.asMapList(kary);
    if (list.isEmpty) return list;
    final ids = list.map((e) => e['id'].toString()).toList();
    final assigns = await _db
        .from('payroll_rule_assignments')
        .select()
        .inFilter('karyawan_id', ids);
    final byId = <String, Map<String, dynamic>>{
      for (final a in PayrollComputeEngine.asMapList(assigns))
        a['karyawan_id'].toString(): a,
    };
    return [
      for (final k in list)
        {
          ...k,
          'assignment': byId[k['id'].toString()],
        },
    ];
  }

  Future<Map<String, int>> poinByKaryawan({
    required String tokoId,
    required String periodeYm,
  }) async {
    final parts = periodeYm.split('-');
    if (parts.length != 2) return {};
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final start =
        '$y-${m.toString().padLeft(2, '0')}-01';
    final endDate = m == 12
        ? DateTime(y + 1, 1, 1)
        : DateTime(y, m + 1, 1);
    final end =
        '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-01';

    final kary = await _db
        .from('karyawan')
        .select('id')
        .eq('toko_id', tokoId)
        .eq('status_approval', 'Aktif');
    final ids = PayrollComputeEngine.asMapList(kary)
        .map((e) => e['id'].toString())
        .toList();
    if (ids.isEmpty) return {};

    final logs = await _db
        .from('poin_logs')
        .select('karyawan_id, poin')
        .inFilter('karyawan_id', ids)
        .gte('tanggal', start)
        .lt('tanggal', end);

    final out = <String, int>{};
    for (final raw in PayrollComputeEngine.asMapList(logs)) {
      final id = raw['karyawan_id'].toString();
      out[id] = (out[id] ?? 0) + PayrollComputeEngine.asInt(raw['poin']);
    }
    return out;
  }

  Future<Map<String, int>> overtimeSumByKaryawan({
    required String tokoId,
    required String periodeYm,
  }) async {
    final rows = await _db
        .from('payroll_overtime_entries')
        .select('karyawan_id, jumlah_rp')
        .eq('toko_id', tokoId)
        .eq('periode_ym', periodeYm)
        .eq('status', 'approved');
    final out = <String, int>{};
    for (final raw in PayrollComputeEngine.asMapList(rows)) {
      final id = raw['karyawan_id'].toString();
      out[id] = (out[id] ?? 0) + PayrollComputeEngine.asInt(raw['jumlah_rp']);
    }
    return out;
  }

  Future<Map<String, dynamic>> upsertOvertime({
    String? id,
    required String karyawanId,
    required String tokoId,
    required String periodeYm,
    required num jam,
    required int rateRp,
    String status = 'approved',
    DateTime? tanggal,
    Map<String, dynamic>? meta,
  }) async {
    final jumlah = PayrollComputeEngine.overtimeAmount(jam: jam, rateRp: rateRp);
    final payload = {
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'periode_ym': periodeYm,
      'jam': jam,
      'rate_rp': rateRp,
      'jumlah_rp': jumlah,
      'status': status,
      'tanggal': tanggal?.toIso8601String().substring(0, 10),
      'meta': meta ?? {},
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (id != null && id.isNotEmpty) {
      final row = await _db
          .from('payroll_overtime_entries')
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      return Map<String, dynamic>.from(row);
    }
    final row = await _db
        .from('payroll_overtime_entries')
        .insert({
          ...payload,
          'created_by': supabase.auth.currentUser?.id,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> listOvertime({
    required String tokoId,
    required String periodeYm,
  }) async {
    final rows = await _db
        .from('payroll_overtime_entries')
        .select(
          '*, karyawan:karyawan_id(id, nama)',
        )
        .eq('toko_id', tokoId)
        .eq('periode_ym', periodeYm)
        .order('created_at');
    return PayrollComputeEngine.asMapList(rows);
  }

  Future<void> submitKaryawanOvertime({
    required String karyawanId,
    required String tokoId,
    required DateTime tanggal,
    required num jam,
    required String alasan,
  }) async {
    if (jam <= 0) throw 'Jam lembur harus lebih dari 0.';
    if (alasan.trim().isEmpty) throw 'Alasan wajib diisi.';
    if (tokoId.trim().isEmpty) throw 'Toko karyawan belum terisi.';
    final ym =
        '${tanggal.year.toString().padLeft(4, '0')}-${tanggal.month.toString().padLeft(2, '0')}';
    final day =
        '${tanggal.year.toString().padLeft(4, '0')}-${tanggal.month.toString().padLeft(2, '0')}-${tanggal.day.toString().padLeft(2, '0')}';
    await _db.from('payroll_overtime_entries').insert({
      'karyawan_id': karyawanId,
      'toko_id': tokoId,
      'periode_ym': ym,
      'tanggal': day,
      'jam': jam,
      'rate_rp': 0,
      'jumlah_rp': 0,
      'status': 'draft',
      'meta': {'alasan': alasan.trim(), 'source': 'karyawan'},
      'created_by': _db.auth.currentUser?.id,
    });
  }

  Future<List<Map<String, dynamic>>> listMineOvertime(String karyawanId) async {
    final rows = await _db
        .from('payroll_overtime_entries')
        .select()
        .eq('karyawan_id', karyawanId)
        .order('created_at', ascending: false)
        .limit(40);
    return PayrollComputeEngine.asMapList(rows);
  }

  Future<List<Map<String, dynamic>>> listOvertimeDrafts({
    String? tokoId,
    bool allToko = false,
  }) async {
    var q = _db.from('payroll_overtime_entries').select(
          '*, karyawan:karyawan_id(id, nama)',
        );
    q = q.eq('status', 'draft');
    if (!allToko && tokoId != null && tokoId.isNotEmpty) {
      final keys = AttendanceAdminScope.storeIdAliases(tokoId);
      q = q.inFilter('toko_id', keys.isEmpty ? [tokoId] : keys);
    }
    final rows = await q.order('created_at');
    return PayrollComputeEngine.asMapList(rows);
  }

  Future<void> decideOvertime({
    required String id,
    required bool approve,
    int rateRp = 0,
    String? note,
  }) async {
    if (approve && rateRp <= 0) {
      throw 'Tarif lembur per jam wajib diisi.';
    }
    await _db.rpc('decide_payroll_overtime', params: {
      'p_id': id,
      'p_approve': approve,
      'p_rate_rp': rateRp,
      'p_note': note,
    });
  }

  static Map<String, dynamic> overridesFromTemplate(Map<String, dynamic> template) {
    final comps = PayrollComputeEngine.asMapList(template['components']);
    final ov = <String, dynamic>{'tax_mode': 'off'};
    final allowances = <Map<String, dynamic>>[];
    final deductions = <Map<String, dynamic>>[];
    for (final c in comps) {
      final kind = (c['kind'] ?? '').toString();
      switch (kind) {
        case 'base_salary':
          final v = PayrollComputeEngine.asInt(
            c['default_value'] ?? c['amount'],
          );
          if (v > 0) ov['gaji_pokok'] = v;
        case 'overtime':
          final r = PayrollComputeEngine.asInt(
            c['overtime_rate_rp'] ?? c['default_value'] ?? c['amount'],
          );
          if (r > 0) ov['overtime_rate_rp'] = r;
        case 'tax':
          var mode = (c['tax_mode'] ?? c['calc'] ?? 'off').toString();
          if (mode == 'pct' || mode == '%') mode = 'percent';
          if (mode == 'fixed' || mode == 'manual') {
            mode = (c['tax_mode'] ?? 'off').toString();
          }
          if (mode == 'percent') {
            ov['tax_mode'] = 'percent';
            ov['tax_percent'] =
                PayrollComputeEngine.asDoubleOrNull(
                  c['tax_percent'] ?? c['default_value'],
                ) ??
                0;
          } else if (mode == 'nominal') {
            ov['tax_mode'] = 'nominal';
            ov['tax_nominal'] = PayrollComputeEngine.asInt(
              c['tax_nominal'] ?? c['default_value'] ?? c['amount'],
            );
          } else {
            ov['tax_mode'] = 'off';
          }
        case 'allowance':
          allowances.add({
            'key': (c['key'] ?? 'allow').toString(),
            'label': (c['label'] ?? 'Tunjangan').toString(),
            'amount': PayrollComputeEngine.asInt(
              c['default_value'] ?? c['amount'],
            ),
          });
        case 'deduction':
          deductions.add({
            'key': (c['key'] ?? 'ded').toString(),
            'label': (c['label'] ?? 'Potongan').toString(),
            'amount': PayrollComputeEngine.asInt(
              c['default_value'] ?? c['amount'],
            ),
          });
      }
    }
    if (allowances.isNotEmpty) ov['allowances'] = allowances;
    if (deductions.isNotEmpty) ov['deductions'] = deductions;
    return ov;
  }

  PayrollPersonInput personFromRow({
    required Map<String, dynamic> karyawan,
    required Map<String, dynamic>? assignment,
    required int poin,
    required int overtimeRp,
  }) {
    final ov = PayrollComputeEngine.asMapOrEmpty(assignment?['overrides']);
    final pokok = ov['gaji_pokok'] != null
        ? PayrollComputeEngine.asInt(ov['gaji_pokok'])
        : PayrollComputeEngine.asInt(karyawan['gaji_pokok']);

    List<({String key, String label, int amount})> parseList(String field) {
      final items = PayrollComputeEngine.asMapList(ov[field]);
      if (items.isEmpty) return const [];
      return [
        for (final e in items)
          (
            key: (e['key'] ?? 'x').toString(),
            label: (e['label'] ?? e['key'] ?? 'Komponen').toString(),
            amount: PayrollComputeEngine.asInt(e['amount']),
          ),
      ];
    }

    final taxMode = PayrollComputeEngine.parseTaxMode(ov['tax_mode']?.toString());
    return PayrollPersonInput(
      karyawanId: karyawan['id'].toString(),
      nama: (karyawan['nama'] ?? '-').toString(),
      jabatan: karyawan['jabatan']?.toString(),
      gajiPokok: pokok,
      poin: poin,
      overtimeRp: overtimeRp,
      allowances: parseList('allowances'),
      deductions: parseList('deductions'),
      taxMode: taxMode,
      taxPercent: PayrollComputeEngine.asDoubleOrNull(ov['tax_percent']),
      taxNominal: ov['tax_nominal'] == null
          ? null
          : PayrollComputeEngine.asInt(ov['tax_nominal']),
    );
  }

  Future<PayrollComputeResult> previewCompute({
    required String tokoId,
    required String periodeYm,
    required PayrollPeriodBonusInput bonus,
  }) async {
    final staff = await listAssignmentsForToko(tokoId);
    final poin = await poinByKaryawan(tokoId: tokoId, periodeYm: periodeYm);
    final ot = await overtimeSumByKaryawan(tokoId: tokoId, periodeYm: periodeYm);
    final people = [
      for (final k in staff)
        personFromRow(
          karyawan: k,
          assignment: k['assignment'] is Map
              ? Map<String, dynamic>.from(k['assignment'] as Map)
              : null,
          poin: poin[k['id'].toString()] ?? 0,
          overtimeRp: ot[k['id'].toString()] ?? 0,
        ),
    ];
    return PayrollComputeEngine.compute(people: people, bonus: bonus);
  }

  Future<Map<String, dynamic>> savePeriod({
    required String tokoId,
    required String periodeYm,
    required PayrollPeriodBonusInput bonus,
    int? omzetReferensi,
    String? notes,
    required bool lock,
    bool markPaid = false,
    PayrollComputeResult? precomputed,
  }) async {
    final settings = {
      'bonus_mode':
          bonus.mode == PayrollBonusMode.pool ? 'pool' : 'rp_per_poin',
      if (bonus.poolRp != null) 'bonus_pool_rp': bonus.poolRp,
      if (bonus.rpPerPoin != null) 'rp_per_poin': bonus.rpPerPoin,
      if (omzetReferensi != null) 'omzet_referensi': omzetReferensi,
      if (notes != null) 'notes': notes,
    };

    if (markPaid) {
      final res = await _db.rpc('admin_save_payroll_period', params: {
        'p_toko_id': tokoId,
        'p_periode_ym': periodeYm,
        'p_settings': settings,
        'p_lines': <dynamic>[],
        'p_lock': false,
        'p_mark_paid': true,
      });
      return PayrollComputeEngine.asMap(res);
    }

    final computed = precomputed ??
        await previewCompute(tokoId: tokoId, periodeYm: periodeYm, bonus: bonus);
    final lines = [
      for (final l in computed.lines)
        {
          'karyawan_id': l.karyawanId,
          'nama': l.nama,
          'jabatan': l.jabatan,
          'gaji_pokok': l.gajiPokok,
          'tunjangan': l.tunjangan,
          'potongan': l.potongan,
          'nett': l.nett,
          'meta': {
            'poin': l.poin,
            'bonus_rp': l.bonusRp,
          },
          'components': [for (final c in l.components) c.toJson()],
        },
    ];
    final res = await _db.rpc('admin_save_payroll_period', params: {
      'p_toko_id': tokoId,
      'p_periode_ym': periodeYm,
      'p_settings': settings,
      'p_lines': lines,
      'p_lock': lock,
      'p_mark_paid': false,
    });
    return PayrollComputeEngine.asMap(res);
  }

  Future<Map<String, dynamic>> unlockPeriod({
    required String tokoId,
    required String periodeYm,
  }) async {
    final res = await _db.rpc('admin_unlock_payroll_period', params: {
      'p_toko_id': tokoId,
      'p_periode_ym': periodeYm,
    });
    return PayrollComputeEngine.asMap(res);
  }

  Future<Map<String, dynamic>?> loadPeriod({
    required String tokoId,
    required String periodeYm,
  }) async {
    final row = await _db
        .from('payroll_period')
        .select()
        .eq('toko_id', tokoId)
        .eq('periode_ym', periodeYm)
        .maybeSingle();
    if (row == null) return null;
    final period = Map<String, dynamic>.from(row);
    final settings = await _db
        .from('payroll_period_settings')
        .select()
        .eq('period_id', period['id'])
        .maybeSingle();
    final lines = await _loadLinesWithComponents(period['id'].toString());
    return {
      ...period,
      'settings': settings,
      'lines': lines,
    };
  }

  Future<List<Map<String, dynamic>>> _loadLinesWithComponents(
    String periodId,
  ) async {
    try {
      final rows = await _db
          .from('payroll_lines')
          .select('*, payroll_line_components(*)')
          .eq('period_id', periodId)
          .order('nama');
      return PayrollComputeEngine.asMapList(rows);
    } catch (_) {
      final rows = await _db
          .from('payroll_lines')
          .select()
          .eq('period_id', periodId)
          .order('nama');
      final lines = PayrollComputeEngine.asMapList(rows);
      if (lines.isEmpty) return lines;
      final ids = lines.map((e) => e['id'].toString()).toList();
      final comps = await _db
          .from('payroll_line_components')
          .select()
          .inFilter('line_id', ids);
      final byLine = <String, List<Map<String, dynamic>>>{};
      for (final c in PayrollComputeEngine.asMapList(comps)) {
        byLine
            .putIfAbsent(c['line_id'].toString(), () => [])
            .add(c);
      }
      return [
        for (final l in lines)
          {
            ...l,
            'payroll_line_components': byLine[l['id'].toString()] ?? const [],
            'components': byLine[l['id'].toString()] ?? const [],
          },
      ];
    }
  }

  Future<List<Map<String, dynamic>>> mySlips({int limit = 12}) async {
    final res = await _db.rpc('karyawan_my_payroll_slips', params: {
      'p_limit': limit,
    });
    return PayrollComputeEngine.asMapList(res);
  }

  /// CSV bank transfer export (no hardcoded bank format beyond columns).
  String bankExportCsv(List<Map<String, dynamic>> linesWithBank) {
    final buf = StringBuffer('nama,bank,rekening,nett,keterangan\n');
    for (final l in linesWithBank) {
      final nama = _csv((l['nama'] ?? '').toString());
      final bank = _csv((l['nama_bank'] ?? l['bank'] ?? '').toString());
      final rek = _csv((l['no_rekening'] ?? l['rekening'] ?? '').toString());
      final nett = PayrollComputeEngine.asInt(l['nett']).toString();
      final ket = _csv((l['periode_ym'] ?? l['keterangan'] ?? '').toString());
      buf.writeln('$nama,$bank,$rek,$nett,$ket');
    }
    return buf.toString();
  }

  static String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
