import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/finance/gl_posting_service.dart';

void main() {
  test('PPN 11% berimbang ke omzet', () {
    final tax = GlPostingService.splitPpn(111000);
    expect(tax.dpp + tax.ppn, 111000);
    expect(tax.dpp, 100000);
    expect(tax.ppn, 11000);
  });

  test('omzet 0 tidak pecah PPN', () {
    final tax = GlPostingService.splitPpn(0);
    expect(tax.dpp, 0);
    expect(tax.ppn, 0);
  });

  test('Tunai/CASH ke kas, QRIS ke bank', () {
    expect(GlPostingService.cashOrBank('Tunai'), GlPostingService.akunKas);
    expect(GlPostingService.cashOrBank('CASH'), GlPostingService.akunKas);
    expect(GlPostingService.cashOrBank(''), GlPostingService.akunKas);
    expect(GlPostingService.cashOrBank('QRIS'), GlPostingService.akunBank);
    expect(GlPostingService.cashOrBank('Transfer'), GlPostingService.akunBank);
  });

  test('tanggal buku Jakarta UTC+7', () {
    final utc = DateTime.utc(2026, 8, 23, 17, 30); // 00:30 WIB 24 Agu
    expect(GlPostingService.dateJakartaYmd(utc), '2026-08-24');
    final morning = DateTime.utc(2026, 8, 23, 10, 0); // 17:00 WIB
    expect(GlPostingService.dateJakartaYmd(morning), '2026-08-23');
  });

  test('SETTLE skip saat total nota masih bergerak', () {
    expect(
      GlPostingService.shouldPostSettle(
        oldTotal: 200000,
        newTotal: 100000,
        oldSisa: 150000,
        newSisa: 50000,
      ),
      isFalse,
    );
    expect(
      GlPostingService.shouldPostSettle(
        oldTotal: 200000,
        newTotal: 200000,
        oldSisa: 150000,
        newSisa: 0,
      ),
      isTrue,
    );
  });
}
