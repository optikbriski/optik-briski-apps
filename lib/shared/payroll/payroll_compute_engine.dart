/// Pure payroll math — no business rates hardcoded; all amounts from caller.
library;

import 'dart:convert';

enum PayrollBonusMode { pool, rpPerPoin }

enum PayrollTaxMode { off, percent, nominal }

/// One component on a payslip line.
class PayrollComponentAmount {
  const PayrollComponentAmount({
    required this.key,
    required this.label,
    required this.kind,
    required this.amount,
    this.meta = const {},
  });

  final String key;
  final String label;
  /// base_salary | allowance | deduction | overtime | bonus_points | tax | adjustment
  final String kind;
  final int amount;
  final Map<String, Object?> meta;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'kind': kind,
        'amount': amount,
        'meta': meta,
      };
}

class PayrollPersonInput {
  const PayrollPersonInput({
    required this.karyawanId,
    required this.nama,
    this.jabatan,
    required this.gajiPokok,
    this.poin = 0,
    this.overtimeRp = 0,
    this.allowances = const [],
    this.deductions = const [],
    this.taxMode = PayrollTaxMode.off,
    this.taxPercent,
    this.taxNominal,
  });

  final String karyawanId;
  final String nama;
  final String? jabatan;
  final int gajiPokok;
  final int poin;
  final int overtimeRp;
  /// Extra fixed allowances (label, amount) — from assignment overrides.
  final List<({String key, String label, int amount})> allowances;
  final List<({String key, String label, int amount})> deductions;
  final PayrollTaxMode taxMode;
  final double? taxPercent;
  final int? taxNominal;
}

class PayrollPeriodBonusInput {
  const PayrollPeriodBonusInput({
    required this.mode,
    this.poolRp,
    this.rpPerPoin,
  });

  final PayrollBonusMode mode;
  final int? poolRp;
  final int? rpPerPoin;
}

class PayrollPersonResult {
  const PayrollPersonResult({
    required this.karyawanId,
    required this.nama,
    this.jabatan,
    required this.gajiPokok,
    required this.tunjangan,
    required this.potongan,
    required this.nett,
    required this.components,
    required this.poin,
    required this.bonusRp,
  });

  final String karyawanId;
  final String nama;
  final String? jabatan;
  final int gajiPokok;
  final int tunjangan;
  final int potongan;
  final int nett;
  final List<PayrollComponentAmount> components;
  final int poin;
  final int bonusRp;
}

class PayrollComputeResult {
  const PayrollComputeResult({
    required this.lines,
    required this.totalPokok,
    required this.totalTunjangan,
    required this.totalPotongan,
    required this.totalNett,
    this.poolRemainder = 0,
    this.undistributedBonusRp = 0,
  });

  final List<PayrollPersonResult> lines;
  final int totalPokok;
  final int totalTunjangan;
  final int totalPotongan;
  final int totalNett;
  /// Sisa pembagian pool (setelah floor) yang dilampirkan ke orang poin terbanyak.
  final int poolRemainder;
  /// Pool yang tidak dibagi karena poin tim 0 — jangan menumpuk ke satu orang.
  final int undistributedBonusRp;
}

abstract final class PayrollComputeEngine {
  static int asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.round();
    final s = v.toString().trim().replaceAll(RegExp(r'[^0-9\-]'), '');
    if (s.isEmpty || s == '-') return fallback;
    return int.tryParse(s) ?? fallback;
  }

  static double? asDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim().replaceAll(',', '.'));
  }

  static Map<String, dynamic> asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) return {};
      try {
        final decoded = jsonDecode(t);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return {};
      }
    }
    return {};
  }

  static List<Map<String, dynamic>> asMapList(dynamic v) {
    var cur = v;
    if (cur is String) {
      final t = cur.trim();
      if (t.isEmpty) return const [];
      try {
        cur = jsonDecode(t);
      } catch (_) {
        return const [];
      }
    }
    if (cur is! List) return const [];
    return [
      for (final e in cur)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static Map<String, dynamic> asMapOrEmpty(dynamic v) {
    if (v == null) return {};
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) return asMap(v);
    return {};
  }

  /// Rebuild one line after Admin override of component amounts.
  static PayrollPersonResult lineFromComponents({
    required String karyawanId,
    required String nama,
    String? jabatan,
    required int poin,
    required List<PayrollComponentAmount> components,
  }) {
    var pokok = 0;
    var allowSum = 0;
    var dedSum = 0;
    var bonusRp = 0;
    for (final c in components) {
      switch (c.kind) {
        case 'base_salary':
          pokok += c.amount < 0 ? 0 : c.amount;
        case 'bonus_points':
          bonusRp += c.amount;
          allowSum += c.amount;
        case 'allowance':
        case 'overtime':
        case 'adjustment':
          allowSum += c.amount < 0 ? 0 : c.amount;
        case 'deduction':
        case 'tax':
          dedSum += c.amount < 0 ? 0 : c.amount;
        default:
          if (c.amount >= 0) {
            allowSum += c.amount;
          } else {
            dedSum += -c.amount;
          }
      }
    }
    return PayrollPersonResult(
      karyawanId: karyawanId,
      nama: nama,
      jabatan: jabatan,
      gajiPokok: pokok,
      tunjangan: allowSum,
      potongan: dedSum,
      nett: pokok + allowSum - dedSum,
      components: components,
      poin: poin,
      bonusRp: bonusRp,
    );
  }

  static PayrollComputeResult retotal(
    List<PayrollPersonResult> lines, {
    int poolRemainder = 0,
    int undistributedBonusRp = 0,
  }) {
    final sorted = [...lines]..sort((a, b) => a.nama.compareTo(b.nama));
    return PayrollComputeResult(
      lines: sorted,
      totalPokok: sorted.fold<int>(0, (a, l) => a + l.gajiPokok),
      totalTunjangan: sorted.fold<int>(0, (a, l) => a + l.tunjangan),
      totalPotongan: sorted.fold<int>(0, (a, l) => a + l.potongan),
      totalNett: sorted.fold<int>(0, (a, l) => a + l.nett),
      poolRemainder: poolRemainder,
      undistributedBonusRp: undistributedBonusRp,
    );
  }

  /// Restore preview from saved `payroll_lines` (+ nested components).
  static PayrollComputeResult fromSavedLines(dynamic rawLines) {
    final lines = <PayrollPersonResult>[];
    for (final raw in asMapList(rawLines)) {
      final compsRaw = raw['components'] ?? raw['payroll_line_components'];
      var comps = <PayrollComponentAmount>[];
      for (final c in asMapList(compsRaw)) {
        final meta = asMapOrEmpty(c['meta']);
        comps.add(PayrollComponentAmount(
          key: (c['key'] ?? 'x').toString(),
          label: (c['label'] ?? c['key'] ?? 'Komponen').toString(),
          kind: (c['kind'] ?? 'manual').toString(),
          amount: asInt(c['amount']),
          meta: Map<String, Object?>.from(meta),
        ));
      }
      if (comps.isEmpty) {
        final pokok = asInt(raw['gaji_pokok']);
        final tunj = asInt(raw['tunjangan']);
        final pot = asInt(raw['potongan']);
        comps = [
          PayrollComponentAmount(
            key: 'base_salary',
            label: 'Gaji pokok',
            kind: 'base_salary',
            amount: pokok,
          ),
          if (tunj > 0)
            PayrollComponentAmount(
              key: 'tunjangan',
              label: 'Tunjangan',
              kind: 'allowance',
              amount: tunj,
            ),
          if (pot > 0)
            PayrollComponentAmount(
              key: 'potongan',
              label: 'Potongan',
              kind: 'deduction',
              amount: pot,
            ),
        ];
      }
      final meta = asMapOrEmpty(raw['meta']);
      lines.add(lineFromComponents(
        karyawanId: (raw['karyawan_id'] ?? '').toString(),
        nama: (raw['nama'] ?? '-').toString(),
        jabatan: raw['jabatan']?.toString(),
        poin: asInt(meta['poin']),
        components: comps,
      ));
    }
    return retotal(lines);
  }

  /// Bonus uang dari poin untuk satu orang (tanpa sisa pool).
  static int bonusForPerson({
    required PayrollBonusMode mode,
    required int poin,
    required int teamPoinSum,
    int? poolRp,
    int? rpPerPoin,
  }) {
    if (mode == PayrollBonusMode.rpPerPoin) {
      final rp = rpPerPoin;
      if (rp == null) {
        throw ArgumentError('rp_per_poin wajib untuk mode rp_per_poin');
      }
      return poin * rp;
    }
    final pool = poolRp;
    if (pool == null) {
      throw ArgumentError('bonus_pool_rp wajib untuk mode pool');
    }
    if (teamPoinSum <= 0) return 0;
    // Poin negatif: kontribusi 0 ke pembagian (tidak menarik pool negatif).
    final p = poin < 0 ? 0 : poin;
    return (pool * p) ~/ teamPoinSum;
  }

  static int overtimeAmount({required num jam, required int rateRp}) {
    if (jam <= 0 || rateRp < 0) return 0;
    return (jam * rateRp).round();
  }

  static int taxAmount({
    required PayrollTaxMode mode,
    required int brutoForTax,
    double? percent,
    int? nominal,
  }) {
    switch (mode) {
      case PayrollTaxMode.off:
        return 0;
      case PayrollTaxMode.percent:
        final pct = percent;
        if (pct == null) {
          throw ArgumentError('tax percent wajib untuk mode percent');
        }
        if (brutoForTax <= 0 || pct <= 0) return 0;
        return ((brutoForTax * pct) / 100).round();
      case PayrollTaxMode.nominal:
        final n = nominal;
        if (n == null) {
          throw ArgumentError('tax nominal wajib untuk mode nominal');
        }
        return n < 0 ? 0 : n;
    }
  }

  static PayrollComputeResult compute({
    required List<PayrollPersonInput> people,
    required PayrollPeriodBonusInput bonus,
  }) {
    final teamPoin = people.fold<int>(0, (a, p) => a + (p.poin < 0 ? 0 : p.poin));

    final rawBonus = <String, int>{};
    var distributed = 0;
    for (final p in people) {
      final b = bonusForPerson(
        mode: bonus.mode,
        poin: p.poin,
        teamPoinSum: teamPoin,
        poolRp: bonus.poolRp,
        rpPerPoin: bonus.rpPerPoin,
      );
      rawBonus[p.karyawanId] = b;
      if (bonus.mode == PayrollBonusMode.pool) {
        distributed += b;
      }
    }

    var remainder = 0;
    var undistributed = 0;
    if (bonus.mode == PayrollBonusMode.pool && bonus.poolRp != null) {
      remainder = bonus.poolRp! - distributed;
      if (teamPoin <= 0) {
        // Jangan dump seluruh pool ke satu nama kalau poin tim 0.
        undistributed = bonus.poolRp!;
        remainder = 0;
      } else if (remainder != 0 && people.isNotEmpty) {
        // Sisa ke orang dengan poin tertinggi (stabil: nama jika seri).
        final sorted = [...people]..sort((a, b) {
            final pa = a.poin < 0 ? 0 : a.poin;
            final pb = b.poin < 0 ? 0 : b.poin;
            if (pb != pa) return pb.compareTo(pa);
            return a.nama.compareTo(b.nama);
          });
        final top = sorted.first.karyawanId;
        rawBonus[top] = (rawBonus[top] ?? 0) + remainder;
      }
    }

    final lines = <PayrollPersonResult>[];
    var totalPokok = 0;
    var totalTunj = 0;
    var totalPot = 0;
    var totalNett = 0;

    for (final p in people) {
      final comps = <PayrollComponentAmount>[];
      final pokok = p.gajiPokok < 0 ? 0 : p.gajiPokok;
      comps.add(PayrollComponentAmount(
        key: 'base_salary',
        label: 'Gaji pokok',
        kind: 'base_salary',
        amount: pokok,
      ));

      var allowSum = 0;
      for (final a in p.allowances) {
        final amt = a.amount < 0 ? 0 : a.amount;
        allowSum += amt;
        comps.add(PayrollComponentAmount(
          key: a.key,
          label: a.label,
          kind: 'allowance',
          amount: amt,
        ));
      }

      final ot = p.overtimeRp < 0 ? 0 : p.overtimeRp;
      if (ot > 0) {
        allowSum += ot;
        comps.add(PayrollComponentAmount(
          key: 'overtime',
          label: 'Lembur',
          kind: 'overtime',
          amount: ot,
        ));
      }

      final bonusRp = rawBonus[p.karyawanId] ?? 0;
      if (bonusRp != 0) {
        allowSum += bonusRp;
        comps.add(PayrollComponentAmount(
          key: 'bonus_points',
          label: 'Bonus poin',
          kind: 'bonus_points',
          amount: bonusRp,
          meta: {
            'poin': p.poin,
            'mode': bonus.mode == PayrollBonusMode.pool ? 'pool' : 'rp_per_poin',
          },
        ));
      }

      var dedSum = 0;
      for (final d in p.deductions) {
        final amt = d.amount < 0 ? 0 : d.amount;
        dedSum += amt;
        comps.add(PayrollComponentAmount(
          key: d.key,
          label: d.label,
          kind: 'deduction',
          amount: amt,
        ));
      }

      final bruto = pokok + allowSum;
      final tax = taxAmount(
        mode: p.taxMode,
        brutoForTax: bruto,
        percent: p.taxPercent,
        nominal: p.taxNominal,
      );
      if (tax > 0) {
        dedSum += tax;
        comps.add(PayrollComponentAmount(
          key: 'tax',
          label: 'PPh',
          kind: 'tax',
          amount: tax,
          meta: {
            'mode': p.taxMode.name,
            if (p.taxPercent != null) 'percent': p.taxPercent,
            if (p.taxNominal != null) 'nominal': p.taxNominal,
          },
        ));
      }

      final nett = bruto - dedSum;
      lines.add(PayrollPersonResult(
        karyawanId: p.karyawanId,
        nama: p.nama,
        jabatan: p.jabatan,
        gajiPokok: pokok,
        tunjangan: allowSum,
        potongan: dedSum,
        nett: nett,
        components: comps,
        poin: p.poin,
        bonusRp: bonusRp,
      ));
      totalPokok += pokok;
      totalTunj += allowSum;
      totalPot += dedSum;
      totalNett += nett;
    }

    lines.sort((a, b) => a.nama.compareTo(b.nama));
    return PayrollComputeResult(
      lines: lines,
      totalPokok: totalPokok,
      totalTunjangan: totalTunj,
      totalPotongan: totalPot,
      totalNett: totalNett,
      poolRemainder: remainder,
      undistributedBonusRp: undistributed,
    );
  }

  static PayrollBonusMode parseBonusMode(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'pool':
        return PayrollBonusMode.pool;
      case 'rp_per_poin':
      case 'rp-per-poin':
      case 'rppoin':
        return PayrollBonusMode.rpPerPoin;
      default:
        throw ArgumentError('bonus_mode tidak valid: $raw');
    }
  }

  static PayrollTaxMode parseTaxMode(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case '':
      case 'off':
      case 'none':
        return PayrollTaxMode.off;
      case 'percent':
      case 'pct':
      case '%':
        return PayrollTaxMode.percent;
      case 'nominal':
      case 'fixed':
        return PayrollTaxMode.nominal;
      default:
        throw ArgumentError('tax_mode tidak valid: $raw');
    }
  }
}
