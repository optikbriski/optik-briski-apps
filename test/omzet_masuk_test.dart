import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/finance/omzet_masuk.dart';

void main() {
  group('uangMasukDariSale', () {
    test('lunas counts full total, not leftover debt', () {
      expect(
        uangMasukDariSale({
          'total_harga': 1000000,
          'sisa_tagihan': 0,
          'status_pembayaran': 'LUNAS',
        }),
        1000000,
      );
    });

    test('DP counts only money already received', () {
      expect(
        uangMasukDariSale({
          'total_harga': 1000000,
          'sisa_tagihan': 700000,
          'status_pembayaran': 'DP',
          'dibayarkan': 300000,
        }),
        300000,
      );
    });

    test('cancelled sale is zero even if totals remain', () {
      expect(
        uangMasukDariSale({
          'total_harga': 500000,
          'sisa_tagihan': 0,
          'status_pembayaran': 'BATAL',
        }),
        0,
      );
    });

    test('parses numeric strings and never goes negative', () {
      expect(
        uangMasukDariSale({
          'total_harga': '250000.0',
          'sisa_tagihan': '400000',
          'status_pembayaran': 'DP',
        }),
        0,
      );
    });
  });

  group('omzetRangeLokal', () {
    final now = DateTime(2026, 8, 22, 15, 30);

    test('today is local midnight to next midnight', () {
      final r = omzetRangeLokal(bulanIni: false, now: now);
      expect(r.start, DateTime(2026, 8, 22));
      expect(r.endExclusive, DateTime(2026, 8, 23));
    });

    test('this month is calendar month', () {
      final r = omzetRangeLokal(bulanIni: true, now: now);
      expect(r.start, DateTime(2026, 8, 1));
      expect(r.endExclusive, DateTime(2026, 9, 1));
    });
  });

  group('saleDalamRentangLokal', () {
    final start = DateTime(2026, 8, 22);
    final end = DateTime(2026, 8, 23);

    test('counts a sale created inside the local window', () {
      expect(
        saleDalamRentangLokal(
          {'created_at': '2026-08-22T15:00:00.000'},
          start: start,
          endExclusive: end,
        ),
        isTrue,
      );
    });

    test('excludes a sale created before the window', () {
      expect(
        saleDalamRentangLokal(
          {'created_at': '2026-08-21T23:00:00.000'},
          start: start,
          endExclusive: end,
        ),
        isFalse,
      );
    });
  });
}
