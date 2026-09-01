import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/payroll/payroll_compute_engine.dart';
import 'package:optik_b_riski/shared/payroll/payroll_service.dart';

void main() {
  group('PayrollComputeEngine bonus', () {
    test('rp_per_poin multiplies including negative poin', () {
      expect(
        PayrollComputeEngine.bonusForPerson(
          mode: PayrollBonusMode.rpPerPoin,
          poin: 10,
          teamPoinSum: 100,
          rpPerPoin: 5000,
        ),
        50000,
      );
      expect(
        PayrollComputeEngine.bonusForPerson(
          mode: PayrollBonusMode.rpPerPoin,
          poin: -4,
          teamPoinSum: 100,
          rpPerPoin: 1000,
        ),
        -4000,
      );
    });

    test('pool splits floor and remainder to top poin', () {
      final result = PayrollComputeEngine.compute(
        people: const [
          PayrollPersonInput(
            karyawanId: 'a',
            nama: 'Ana',
            gajiPokok: 1000000,
            poin: 3,
          ),
          PayrollPersonInput(
            karyawanId: 'b',
            nama: 'Budi',
            gajiPokok: 1000000,
            poin: 1,
          ),
        ],
        bonus: const PayrollPeriodBonusInput(
          mode: PayrollBonusMode.pool,
          poolRp: 100000,
        ),
      );
      // 3/4 * 100000 = 75000, 1/4 = 25000, remainder 0
      final ana = result.lines.firstWhere((e) => e.karyawanId == 'a');
      final budi = result.lines.firstWhere((e) => e.karyawanId == 'b');
      expect(ana.bonusRp + budi.bonusRp, 100000);
      expect(ana.bonusRp, greaterThan(budi.bonusRp));
    });

    test('pool remainder attaches to highest poin', () {
      final result = PayrollComputeEngine.compute(
        people: const [
          PayrollPersonInput(
            karyawanId: 'a',
            nama: 'Ana',
            gajiPokok: 0,
            poin: 2,
          ),
          PayrollPersonInput(
            karyawanId: 'b',
            nama: 'Budi',
            gajiPokok: 0,
            poin: 1,
          ),
        ],
        bonus: const PayrollPeriodBonusInput(
          mode: PayrollBonusMode.pool,
          poolRp: 100,
        ),
      );
      // floor: 66 + 33 = 99, remainder 1 → Ana
      expect(result.poolRemainder, 1);
      expect(
        result.lines.firstWhere((e) => e.karyawanId == 'a').bonusRp,
        67,
      );
      expect(
        result.lines.firstWhere((e) => e.karyawanId == 'b').bonusRp,
        33,
      );
    });

    test('pool with zero team poin does not dump onto one person', () {
      final result = PayrollComputeEngine.compute(
        people: const [
          PayrollPersonInput(
            karyawanId: 'a',
            nama: 'Ana',
            gajiPokok: 1000000,
            poin: 0,
          ),
          PayrollPersonInput(
            karyawanId: 'b',
            nama: 'Budi',
            gajiPokok: 1000000,
            poin: 0,
          ),
        ],
        bonus: const PayrollPeriodBonusInput(
          mode: PayrollBonusMode.pool,
          poolRp: 500000,
        ),
      );
      expect(result.undistributedBonusRp, 500000);
      expect(result.lines.every((e) => e.bonusRp == 0), isTrue);
      expect(result.lines.every((e) => e.nett == 1000000), isTrue);
    });

    test('rp_per_poin mode requires rp', () {
      expect(
        () => PayrollComputeEngine.bonusForPerson(
          mode: PayrollBonusMode.rpPerPoin,
          poin: 1,
          teamPoinSum: 1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('overtime + tax', () {
    test('overtime jam × rate', () {
      expect(
        PayrollComputeEngine.overtimeAmount(jam: 2.5, rateRp: 20000),
        50000,
      );
      expect(
        PayrollComputeEngine.overtimeAmount(jam: 0, rateRp: 20000),
        0,
      );
    });

    test('tax percent and nominal', () {
      expect(
        PayrollComputeEngine.taxAmount(
          mode: PayrollTaxMode.percent,
          brutoForTax: 1000000,
          percent: 5,
        ),
        50000,
      );
      expect(
        PayrollComputeEngine.taxAmount(
          mode: PayrollTaxMode.nominal,
          brutoForTax: 1000000,
          nominal: 75000,
        ),
        75000,
      );
      expect(
        PayrollComputeEngine.taxAmount(
          mode: PayrollTaxMode.off,
          brutoForTax: 1000000,
        ),
        0,
      );
    });
  });

  group('full line nett', () {
    test('pokok + allow + ot + bonus - ded - tax', () {
      final r = PayrollComputeEngine.compute(
        people: [
          PayrollPersonInput(
            karyawanId: '1',
            nama: 'X',
            gajiPokok: 2000000,
            poin: 10,
            overtimeRp: 100000,
            allowances: const [
              (key: 'makan', label: 'Makan', amount: 300000),
            ],
            deductions: const [
              (key: 'bpjs', label: 'BPJS', amount: 50000),
            ],
            taxMode: PayrollTaxMode.percent,
            taxPercent: 5,
          ),
        ],
        bonus: const PayrollPeriodBonusInput(
          mode: PayrollBonusMode.rpPerPoin,
          rpPerPoin: 1000,
        ),
      );
      final line = r.lines.single;
      // bruto = 2_000_000 + 300_000 + 100_000 + 10_000 = 2_410_000
      // tax 5% = 120_500; pot = 50_000 + 120_500 = 170_500
      // nett = 2_410_000 - 170_500 = 2_239_500
      expect(line.bonusRp, 10000);
      expect(line.tunjangan, 410000);
      expect(line.potongan, 170500);
      expect(line.nett, 2239500);
      expect(line.components.any((c) => c.kind == 'tax'), isTrue);
    });
  });

  group('parsers', () {
    test('bonus and tax modes', () {
      expect(
        PayrollComputeEngine.parseBonusMode('pool'),
        PayrollBonusMode.pool,
      );
      expect(
        PayrollComputeEngine.parseBonusMode('rp_per_poin'),
        PayrollBonusMode.rpPerPoin,
      );
      expect(
        PayrollComputeEngine.parseTaxMode('percent'),
        PayrollTaxMode.percent,
      );
      expect(PayrollComputeEngine.parseTaxMode(null), PayrollTaxMode.off);
    });

    test('asInt and asMapList tolerate jsonb strings', () {
      expect(PayrollComputeEngine.asInt('4.200.000'), 4200000);
      expect(PayrollComputeEngine.asInt('-50'), -50);
      expect(PayrollComputeEngine.asInt(null), 0);
      expect(
        PayrollComputeEngine.asMapList('[{"a":1},{"a":2}]').length,
        2,
      );
      expect(PayrollComputeEngine.asMapList('not-json'), isEmpty);
    });
  });

  group('saved preview + override', () {
    test('fromSavedLines restores nett and components', () {
      final r = PayrollComputeEngine.fromSavedLines([
        {
          'karyawan_id': '1',
          'nama': 'X',
          'jabatan': 'Kasir',
          'gaji_pokok': 2000000,
          'tunjangan': 100000,
          'potongan': 50000,
          'nett': 2050000,
          'meta': {'poin': 8, 'bonus_rp': 100000},
          'components': [
            {
              'key': 'base_salary',
              'label': 'Gaji pokok',
              'kind': 'base_salary',
              'amount': 2000000,
            },
            {
              'key': 'bonus_points',
              'label': 'Bonus poin',
              'kind': 'bonus_points',
              'amount': 100000,
            },
            {
              'key': 'tax',
              'label': 'PPh',
              'kind': 'tax',
              'amount': 50000,
            },
          ],
        },
      ]);
      expect(r.lines.single.nett, 2050000);
      expect(r.lines.single.bonusRp, 100000);
      expect(r.totalNett, 2050000);
    });

    test('lineFromComponents applies Admin override', () {
      final line = PayrollComputeEngine.lineFromComponents(
        karyawanId: '1',
        nama: 'X',
        poin: 3,
        components: const [
          PayrollComponentAmount(
            key: 'base_salary',
            label: 'Gaji pokok',
            kind: 'base_salary',
            amount: 1000000,
          ),
          PayrollComponentAmount(
            key: 'bonus_points',
            label: 'Bonus',
            kind: 'bonus_points',
            amount: 25000,
          ),
        ],
      );
      expect(line.nett, 1025000);
      expect(line.bonusRp, 25000);
    });
  });

  group('template → assignment overrides', () {
    test('maps pokok, allowance, OT rate, and percent tax', () {
      final ov = PayrollService.overridesFromTemplate({
        'components': [
          {
            'kind': 'base_salary',
            'default_value': 3500000,
          },
          {
            'kind': 'allowance',
            'key': 'makan',
            'label': 'Makan',
            'default_value': 300000,
          },
          {
            'kind': 'overtime',
            'overtime_rate_rp': 25000,
          },
          {
            'kind': 'tax',
            'tax_mode': 'percent',
            'tax_percent': 5,
          },
        ],
      });
      expect(ov['gaji_pokok'], 3500000);
      expect(ov['overtime_rate_rp'], 25000);
      expect(ov['tax_mode'], 'percent');
      expect(ov['tax_percent'], 5);
      expect((ov['allowances'] as List).single['amount'], 300000);
    });
  });
}
