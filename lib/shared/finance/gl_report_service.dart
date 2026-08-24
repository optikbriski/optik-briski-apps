import 'package:supabase_flutter/supabase_flutter.dart';

import '../logistics/product_identity.dart';

class GlAccountBalance {
  const GlAccountBalance({
    required this.kode,
    required this.nama,
    required this.tipe,
    required this.normalBalance,
    required this.debit,
    required this.kredit,
  });

  final String kode;
  final String nama;
  final String tipe;
  final String normalBalance;
  final int debit;
  final int kredit;

  int get saldo {
    final net = debit - kredit;
    return normalBalance == 'DEBIT' ? net : -net;
  }

  factory GlAccountBalance.fromRow(Map<String, dynamic> r) {
    return GlAccountBalance(
      kode: r['kode']?.toString() ?? '',
      nama: r['nama']?.toString() ?? '',
      tipe: r['tipe']?.toString() ?? 'ASSET',
      normalBalance: r['normal_balance']?.toString() ?? 'DEBIT',
      debit: ProductIdentity.moneyOf(r['debit']),
      kredit: ProductIdentity.moneyOf(r['kredit']),
    );
  }
}

class GlAgingBucket {
  const GlAgingBucket({
    required this.label,
    required this.count,
    required this.amount,
  });

  final String label;
  final int count;
  final int amount;
}

class GlAgingRow {
  const GlAgingRow({
    required this.ref,
    required this.nama,
    required this.tokoId,
    required this.tanggal,
    required this.umurHari,
    required this.nominal,
    required this.bucket,
  });

  final String ref;
  final String nama;
  final String tokoId;
  final DateTime tanggal;
  final int umurHari;
  final int nominal;
  final String bucket;

  factory GlAgingRow.fromRpc(Map<String, dynamic> r) {
    final tgl = DateTime.tryParse(r['tanggal']?.toString() ?? '') ??
        DateTime.now();
    return GlAgingRow(
      ref: r['ref']?.toString() ?? '-',
      nama: r['nama']?.toString() ?? '-',
      tokoId: r['toko_id']?.toString() ?? '-',
      tanggal: tgl,
      umurHari: int.tryParse('${r['umur_hari'] ?? 0}') ?? 0,
      nominal: int.tryParse('${r['nominal'] ?? 0}') ?? 0,
      bucket: r['bucket']?.toString() ?? '0-30',
    );
  }
}

class GlTokoConsolidate {
  const GlTokoConsolidate({
    required this.tokoId,
    required this.pendapatan,
    required this.beban,
    required this.laba,
    required this.kasBank,
    required this.piutang,
    required this.hutang,
  });

  final String tokoId;
  final int pendapatan;
  final int beban;
  final int laba;
  final int kasBank;
  final int piutang;
  final int hutang;

  factory GlTokoConsolidate.fromRow(Map<String, dynamic> r) {
    return GlTokoConsolidate(
      tokoId: r['toko_id']?.toString() ?? '-',
      pendapatan: int.tryParse('${r['pendapatan'] ?? 0}') ?? 0,
      beban: int.tryParse('${r['beban'] ?? 0}') ?? 0,
      laba: int.tryParse('${r['laba'] ?? 0}') ?? 0,
      kasBank: int.tryParse('${r['kas_bank'] ?? 0}') ?? 0,
      piutang: int.tryParse('${r['piutang'] ?? 0}') ?? 0,
      hutang: int.tryParse('${r['hutang'] ?? 0}') ?? 0,
    );
  }
}

class GlBudgetRow {
  const GlBudgetRow({
    required this.akunKode,
    required this.akunNama,
    required this.anggaran,
    required this.aktual,
    required this.selisih,
  });

  final String akunKode;
  final String akunNama;
  final int anggaran;
  final int aktual;
  final int selisih;

  factory GlBudgetRow.fromRow(Map<String, dynamic> r) {
    return GlBudgetRow(
      akunKode: r['akun_kode']?.toString() ?? '',
      akunNama: r['akun_nama']?.toString() ?? '',
      anggaran: int.tryParse('${r['anggaran'] ?? 0}') ?? 0,
      aktual: int.tryParse('${r['aktual'] ?? 0}') ?? 0,
      selisih: int.tryParse('${r['selisih'] ?? 0}') ?? 0,
    );
  }
}

class GlLedgerLine {
  const GlLedgerLine({
    required this.id,
    required this.akunKode,
    required this.debit,
    required this.kredit,
    required this.lineMemo,
    required this.entryId,
    required this.tanggal,
    required this.tokoId,
    required this.sumber,
    required this.referensiId,
    required this.entryMemo,
    required this.createdAt,
  });

  final String id;
  final String akunKode;
  final int debit;
  final int kredit;
  final String lineMemo;
  final String entryId;
  final DateTime tanggal;
  final String tokoId;
  final String sumber;
  final String referensiId;
  final String entryMemo;
  final DateTime createdAt;

  factory GlLedgerLine.fromRow(Map<String, dynamic> r) {
    final je = Map<String, dynamic>.from(
      (r['journal_entries'] as Map?) ?? const {},
    );
    return GlLedgerLine(
      id: r['id']?.toString() ?? '',
      akunKode: r['akun_kode']?.toString() ?? '',
      debit: int.tryParse('${r['debit'] ?? 0}') ?? 0,
      kredit: int.tryParse('${r['kredit'] ?? 0}') ?? 0,
      lineMemo: r['memo']?.toString() ?? '',
      entryId: je['id']?.toString() ?? '',
      tanggal: DateTime.tryParse(je['tanggal']?.toString() ?? '') ??
          DateTime.now(),
      tokoId: je['toko_id']?.toString() ?? '-',
      sumber: je['sumber']?.toString() ?? '-',
      referensiId: je['referensi_id']?.toString() ?? '',
      entryMemo: je['memo']?.toString() ?? '',
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ??
          DateTime.tryParse(je['tanggal']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class GlAuditFinding {
  const GlAuditFinding({
    required this.tokoId,
    required this.ref,
    required this.detail,
    required this.raw,
  });

  final String tokoId;
  final String ref;
  final String detail;
  final Map<String, dynamic> raw;

  factory GlAuditFinding.fromJson(Map<String, dynamic> r) {
    return GlAuditFinding(
      tokoId: r['toko_id']?.toString() ?? '-',
      ref: r['ref']?.toString() ?? '-',
      detail: r['detail']?.toString() ?? '-',
      raw: r,
    );
  }
}

class GlAuditMetric {
  const GlAuditMetric({
    required this.key,
    required this.label,
    required this.amount,
  });

  final String key;
  final String label;
  final int amount;

  factory GlAuditMetric.fromJson(Map<String, dynamic> r) {
    return GlAuditMetric(
      key: r['key']?.toString() ?? '',
      label: r['label']?.toString() ?? '',
      amount: int.tryParse('${r['amount'] ?? 0}') ?? 0,
    );
  }
}

class GlAuditFinance {
  const GlAuditFinance({
    required this.periode,
    required this.tahun,
    required this.bulan,
    required this.scopeToko,
    required this.omzetBrutoSales,
    required this.omzetDppSales,
    required this.ppnSales,
    required this.omzetBrutoGl,
    required this.omzetDppGl,
    required this.ppnGl,
    required this.pengeluaranFt,
    required this.pengeluaranGl,
    required this.pengeluaranManualFt,
    required this.bersihGl,
    required this.bersihOps,
    required this.selisihOmzetBruto,
    required this.selisihOmzetDpp,
    required this.selisihPengeluaran,
  });

  final String periode;
  final int tahun;
  final int bulan;
  final String scopeToko;
  final int omzetBrutoSales;
  final int omzetDppSales;
  final int ppnSales;
  final int omzetBrutoGl;
  final int omzetDppGl;
  final int ppnGl;
  final int pengeluaranFt;
  final int pengeluaranGl;
  final int pengeluaranManualFt;
  final int bersihGl;
  final int bersihOps;
  final int selisihOmzetBruto;
  final int selisihOmzetDpp;
  final int selisihPengeluaran;

  bool get omzetBrutoMatch => selisihOmzetBruto == 0;
  bool get omzetDppMatch => selisihOmzetDpp == 0;
  bool get pengeluaranMatch => selisihPengeluaran == 0;

  factory GlAuditFinance.fromJson(Map<String, dynamic> r) {
    return GlAuditFinance(
      periode: r['periode']?.toString() ?? '-',
      tahun: int.tryParse('${r['tahun'] ?? 0}') ?? 0,
      bulan: int.tryParse('${r['bulan'] ?? 0}') ?? 0,
      scopeToko: r['scope_toko']?.toString() ?? 'ALL',
      omzetBrutoSales:
          int.tryParse('${r['omzet_bruto_sales'] ?? 0}') ?? 0,
      omzetDppSales: int.tryParse('${r['omzet_dpp_sales'] ?? 0}') ?? 0,
      ppnSales: int.tryParse('${r['ppn_sales'] ?? 0}') ?? 0,
      omzetBrutoGl: int.tryParse('${r['omzet_bruto_gl'] ?? 0}') ?? 0,
      omzetDppGl: int.tryParse('${r['omzet_dpp_gl'] ?? 0}') ?? 0,
      ppnGl: int.tryParse('${r['ppn_gl'] ?? 0}') ?? 0,
      pengeluaranFt: int.tryParse('${r['pengeluaran_ft'] ?? 0}') ?? 0,
      pengeluaranGl: int.tryParse('${r['pengeluaran_gl'] ?? 0}') ?? 0,
      pengeluaranManualFt:
          int.tryParse('${r['pengeluaran_manual_ft'] ?? 0}') ?? 0,
      bersihGl: int.tryParse('${r['bersih_gl'] ?? 0}') ?? 0,
      bersihOps: int.tryParse('${r['bersih_ops'] ?? 0}') ?? 0,
      selisihOmzetBruto:
          int.tryParse('${r['selisih_omzet_bruto'] ?? 0}') ?? 0,
      selisihOmzetDpp:
          int.tryParse('${r['selisih_omzet_dpp'] ?? 0}') ?? 0,
      selisihPengeluaran:
          int.tryParse('${r['selisih_pengeluaran'] ?? 0}') ?? 0,
    );
  }
}

class GlAuditCheck {
  const GlAuditCheck({
    required this.id,
    required this.title,
    required this.severity,
    required this.passed,
    required this.count,
    required this.definition,
    required this.metrics,
    required this.findings,
  });

  final String id;
  final String title;
  final String severity;
  final bool passed;
  final int count;
  final String definition;
  final List<GlAuditMetric> metrics;
  final List<GlAuditFinding> findings;

  factory GlAuditCheck.fromJson(Map<String, dynamic> r) {
    final rawFindings = r['findings'];
    final findings = <GlAuditFinding>[];
    if (rawFindings is List) {
      for (final f in rawFindings) {
        if (f is Map) {
          findings.add(
              GlAuditFinding.fromJson(Map<String, dynamic>.from(f)));
        }
      }
    }
    final rawMetrics = r['metrics'];
    final metrics = <GlAuditMetric>[];
    if (rawMetrics is List) {
      for (final m in rawMetrics) {
        if (m is Map) {
          metrics.add(GlAuditMetric.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }
    return GlAuditCheck(
      id: r['id']?.toString() ?? '',
      title: r['title']?.toString() ?? '',
      severity: r['severity']?.toString() ?? 'INFO',
      passed: r['passed'] == true,
      count: int.tryParse('${r['count'] ?? findings.length}') ??
          findings.length,
      definition: r['definition']?.toString() ?? '',
      metrics: metrics,
      findings: findings,
    );
  }
}

class GlAuditReport {
  const GlAuditReport({
    required this.generatedAt,
    required this.scopeToko,
    required this.criticalFailed,
    required this.highFailed,
    required this.mediumFailed,
    required this.infoChecks,
    required this.checksRun,
    required this.allClear,
    required this.checks,
    this.finance,
  });

  final DateTime generatedAt;
  final String scopeToko;
  final int criticalFailed;
  final int highFailed;
  final int mediumFailed;
  final int infoChecks;
  final int checksRun;
  final bool allClear;
  final List<GlAuditCheck> checks;
  final GlAuditFinance? finance;

  factory GlAuditReport.fromJson(Map<String, dynamic> r) {
    final summary = Map<String, dynamic>.from(
        (r['summary'] as Map?) ?? const {});
    final rawChecks = r['checks'];
    final checks = <GlAuditCheck>[];
    if (rawChecks is List) {
      for (final c in rawChecks) {
        if (c is Map) {
          checks.add(GlAuditCheck.fromJson(Map<String, dynamic>.from(c)));
        }
      }
    }
    final rawFinance = r['finance'];
    return GlAuditReport(
      generatedAt:
          DateTime.tryParse(r['generated_at']?.toString() ?? '') ??
              DateTime.now(),
      scopeToko: r['scope_toko']?.toString() ?? 'ALL',
      criticalFailed:
          int.tryParse('${summary['critical_failed'] ?? 0}') ?? 0,
      highFailed: int.tryParse('${summary['high_failed'] ?? 0}') ?? 0,
      mediumFailed: int.tryParse('${summary['medium_failed'] ?? 0}') ?? 0,
      infoChecks: int.tryParse('${summary['info_checks'] ?? 0}') ?? 0,
      checksRun: int.tryParse('${summary['checks_run'] ?? checks.length}') ??
          checks.length,
      allClear: summary['all_clear'] == true,
      checks: checks,
      finance: rawFinance is Map
          ? GlAuditFinance.fromJson(Map<String, dynamic>.from(rawFinance))
          : null,
    );
  }
}

/// Laporan GL skala 600 toko — agregasi di SQL/RPC, bukan di client.
class GlReportService {
  GlReportService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> fetchCoa() async {
    final res = await _db
        .from('chart_of_accounts')
        .select()
        .order('kode', ascending: true);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchPeriods() async {
    final res = await _db
        .from('fiscal_periods')
        .select()
        .order('tahun', ascending: false)
        .order('bulan', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchJournals({
    String? tokoId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
  }) async {
    var q = _db.from('journal_entries').select(
        '*, journal_lines(id, akun_kode, debit, kredit, memo, chart_of_accounts(nama))');
    if (tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId.toUpperCase());
    }
    if (start != null) {
      q = q.gte('tanggal', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      q = q.lte('tanggal', end.toIso8601String().split('T').first);
    }
    final res =
        await q.order('tanggal', ascending: false).limit(limit.clamp(20, 300));
    return List<Map<String, dynamic>>.from(res);
  }

  /// Mutasi akun (atau beberapa akun turunan) di rentang tanggal.
  Future<List<GlLedgerLine>> fetchAccountLedger({
    required List<String> akunKodes,
    String? tokoId,
    DateTime? start,
    DateTime? end,
    int limit = 200,
  }) async {
    if (akunKodes.isEmpty) return const [];
    var q = _db.from('journal_lines').select(
      'id, akun_kode, debit, kredit, memo, created_at, '
      'journal_entries!inner(id, tanggal, toko_id, sumber, referensi_id, memo, status)',
    );
    if (akunKodes.length == 1) {
      q = q.eq('akun_kode', akunKodes.first);
    } else {
      q = q.inFilter('akun_kode', akunKodes);
    }
    q = q.eq('journal_entries.status', 'POSTED');
    if (tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('journal_entries.toko_id', tokoId.toUpperCase());
    }
    if (start != null) {
      q = q.gte(
          'journal_entries.tanggal', start.toIso8601String().split('T').first);
    }
    if (end != null) {
      q = q.lte(
          'journal_entries.tanggal', end.toIso8601String().split('T').first);
    }
    final res = await q
        .order('created_at', ascending: false)
        .limit(limit.clamp(20, 500));
    final rows = List<Map<String, dynamic>>.from(res)
        .map(GlLedgerLine.fromRow)
        .toList();
    rows.sort((a, b) {
      final c = b.tanggal.compareTo(a.tanggal);
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
    return rows;
  }

  Future<List<GlAccountBalance>> trialBalance({
    String? tokoId,
    required int tahun,
    required int bulan,
  }) async {
    final res = await _db.rpc('gl_trial_balance', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
      'p_toko_id': tokoId,
    });
    return List<Map<String, dynamic>>.from(res as List)
        .map(GlAccountBalance.fromRow)
        .toList();
  }

  Future<List<GlAccountBalance>> incomeStatement({
    String? tokoId,
    required int tahun,
    required int bulan,
  }) async {
    final all = await trialBalance(tokoId: tokoId, tahun: tahun, bulan: bulan);
    return all
        .where((a) =>
            a.tipe == 'REVENUE' || a.tipe == 'COGS' || a.tipe == 'EXPENSE')
        .toList();
  }

  Future<({List<GlAccountBalance> rows, int labaBerjalan})> balanceSheet({
    String? tokoId,
    required int tahun,
    required int bulan,
  }) async {
    final all = await trialBalance(tokoId: tokoId, tahun: tahun, bulan: bulan);
    var pendapatan = 0;
    var beban = 0;
    for (final a in all) {
      if (a.tipe == 'REVENUE') {
        pendapatan += a.kredit - a.debit;
      } else if (a.tipe == 'COGS' || a.tipe == 'EXPENSE') {
        beban += a.debit - a.kredit;
      }
    }
    final rows = all
        .where((a) =>
            a.tipe == 'ASSET' || a.tipe == 'LIABILITY' || a.tipe == 'EQUITY')
        .toList();
    return (rows: rows, labaBerjalan: pendapatan - beban);
  }

  Future<List<GlTokoConsolidate>> consolidateByToko({
    required int tahun,
    required int bulan,
  }) async {
    final res = await _db.rpc('gl_consolidate_by_toko', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
    });
    return List<Map<String, dynamic>>.from(res as List)
        .map(GlTokoConsolidate.fromRow)
        .toList();
  }

  static List<GlAgingBucket> bucketsFrom(List<GlAgingRow> rows) {
    final amt = <String, int>{
      '0-30': 0,
      '31-60': 0,
      '61-90': 0,
      '90+': 0,
    };
    final cnt = <String, int>{
      '0-30': 0,
      '31-60': 0,
      '61-90': 0,
      '90+': 0,
    };
    for (final r in rows) {
      amt[r.bucket] = (amt[r.bucket] ?? 0) + r.nominal;
      cnt[r.bucket] = (cnt[r.bucket] ?? 0) + 1;
    }
    return [
      for (final k in ['0-30', '31-60', '61-90', '90+'])
        GlAgingBucket(label: k, count: cnt[k] ?? 0, amount: amt[k] ?? 0),
    ];
  }

  Future<({List<GlAgingRow> rows, List<GlAgingBucket> buckets})>
      agingPiutang({String? tokoId, int limit = 500}) async {
    final res = await _db.rpc('gl_aging_piutang', params: {
      'p_toko_id': tokoId,
      'p_limit': limit,
    });
    final rows = List<Map<String, dynamic>>.from(res as List)
        .map(GlAgingRow.fromRpc)
        .toList();
    return (rows: rows, buckets: bucketsFrom(rows));
  }

  Future<({List<GlAgingRow> rows, List<GlAgingBucket> buckets})>
      agingHutang({String? tokoId, int limit = 500}) async {
    final res = await _db.rpc('gl_aging_hutang', params: {
      'p_toko_id': tokoId,
      'p_limit': limit,
    });
    final rows = List<Map<String, dynamic>>.from(res as List)
        .map(GlAgingRow.fromRpc)
        .toList();
    return (rows: rows, buckets: bucketsFrom(rows));
  }

  Future<List<GlBudgetRow>> budgetVsActual({
    String? tokoId,
    required int tahun,
    required int bulan,
  }) async {
    final res = await _db.rpc('gl_budget_vs_actual', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
      'p_toko_id': tokoId,
    });
    return List<Map<String, dynamic>>.from(res as List)
        .map(GlBudgetRow.fromRow)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchBankAccounts({String? tokoId}) async {
    var q = _db.from('bank_accounts').select().eq('aktif', true);
    if (tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId.toUpperCase());
    }
    return List<Map<String, dynamic>>.from(await q.order('nama'));
  }

  Future<List<Map<String, dynamic>>> fetchBankStatements({
    required String bankAccountId,
    int limit = 100,
  }) async {
    final res = await _db
        .from('bank_statement_lines')
        .select()
        .eq('bank_account_id', bankAccountId)
        .order('tanggal', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> addBankAccount({
    required String tokoId,
    required String nama,
    required String bankName,
    String? noRekening,
  }) async {
    await _db.from('bank_accounts').insert({
      'toko_id': tokoId.toUpperCase(),
      'nama': nama,
      'bank_name': bankName,
      'no_rekening': noRekening,
      'akun_gl': '1102',
    });
  }

  Future<void> addBankStatementLine({
    required String bankAccountId,
    required DateTime tanggal,
    required String deskripsi,
    required int debit,
    required int kredit,
  }) async {
    await _db.from('bank_statement_lines').insert({
      'bank_account_id': bankAccountId,
      'tanggal': tanggal.toIso8601String().split('T').first,
      'deskripsi': deskripsi,
      'debit': debit,
      'kredit': kredit,
      'status': 'OPEN',
    });
  }

  Future<void> matchBankLine({
    required String lineId,
    required String journalEntryId,
  }) async {
    await _db.rpc('gl_match_bank_line', params: {
      'p_line_id': lineId,
      'p_journal_entry_id': journalEntryId,
    });
  }

  Future<void> upsertBudget({
    required String tokoId,
    required int tahun,
    required int bulan,
    required String akunKode,
    required int anggaran,
  }) async {
    await _db.from('gl_budgets').upsert({
      'toko_id': tokoId.toUpperCase(),
      'tahun': tahun,
      'bulan': bulan,
      'akun_kode': akunKode,
      'anggaran': anggaran,
    }, onConflict: 'toko_id,tahun,bulan,akun_kode');
  }

  Future<List<Map<String, dynamic>>> fetchEfaktur({
    String? tokoId,
    int limit = 200,
  }) async {
    var q = _db.from('e_faktur_drafts').select();
    if (tokoId != null && tokoId.isNotEmpty) {
      q = q.eq('toko_id', tokoId.toUpperCase());
    }
    return List<Map<String, dynamic>>.from(
        await q.order('tanggal', ascending: false).limit(limit));
  }

  Future<({int created, int skipped})> buildEfaktur({
    required int tahun,
    required int bulan,
    String? tokoId,
  }) async {
    final res = await _db.rpc('gl_build_efaktur_from_sales', params: {
      'p_tahun': tahun,
      'p_bulan': bulan,
      'p_toko_id': tokoId,
      'p_limit': 500,
    });
    final map = Map<String, dynamic>.from(res as Map);
    return (
      created: int.tryParse('${map['created'] ?? 0}') ?? 0,
      skipped: int.tryParse('${map['skipped'] ?? 0}') ?? 0,
    );
  }

  Future<void> markEfakturExported(List<String> ids) async {
    if (ids.isEmpty) return;
    await _db
        .from('e_faktur_drafts')
        .update({
          'status': 'EXPORTED',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .inFilter('id', ids);
  }

  /// Audit E2E ketat (owner/pusat). Jalankan manual — tidak otomatis saat reload.
  Future<GlAuditReport> runFullAudit({
    String? tokoId,
    int limitPerCheck = 80,
    int? tahun,
    int? bulan,
  }) async {
    final res = await _db.rpc('gl_run_full_audit', params: {
      'p_toko_id': (tokoId == null || tokoId.isEmpty)
          ? null
          : tokoId.toUpperCase(),
      'p_limit_per_check': limitPerCheck.clamp(10, 200),
      'p_tahun': tahun,
      'p_bulan': bulan,
    });
    if (res is! Map) {
      throw StateError('Respons audit GL tidak valid');
    }
    return GlAuditReport.fromJson(Map<String, dynamic>.from(res));
  }
}
