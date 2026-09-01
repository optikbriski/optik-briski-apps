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

  group('omzetRangeJakartaUtc', () {
    test('hari ini = midnight Jakarta → midnight berikutnya (UTC)', () {
      // 28 Aug 2026 03:00 WIB = 27 Aug 20:00 UTC
      final r = omzetRangeJakartaUtc(
        bulanIni: false,
        now: DateTime.utc(2026, 8, 27, 20),
      );
      expect(r.startUtc, DateTime.utc(2026, 8, 27, 17));
      expect(r.endExclusiveUtc, DateTime.utc(2026, 8, 28, 17));
    });

    test('bulan ini = 1 Aug 00:00 WIB → 1 Sep 00:00 WIB', () {
      final r = omzetRangeJakartaUtc(
        bulanIni: true,
        now: DateTime.utc(2026, 8, 27, 20),
      );
      expect(r.startUtc, DateTime.utc(2026, 7, 31, 17));
      expect(r.endExclusiveUtc, DateTime.utc(2026, 8, 31, 17));
    });
  });

  group('saleDalamRentangUtc', () {
    final start = DateTime.utc(2026, 8, 27, 17);
    final end = DateTime.utc(2026, 8, 28, 17);

    test('nota jam 01:00 WIB masuk hari Jakarta', () {
      expect(
        saleDalamRentangUtc(
          {'created_at': '2026-08-27T18:00:00.000Z'},
          startUtc: start,
          endExclusiveUtc: end,
        ),
        isTrue,
      );
    });

    test('nota sebelum midnight Jakarta tidak masuk', () {
      expect(
        saleDalamRentangUtc(
          {'created_at': '2026-08-27T16:59:00.000Z'},
          startUtc: start,
          endExclusiveUtc: end,
        ),
        isFalse,
      );
    });
  });
}
