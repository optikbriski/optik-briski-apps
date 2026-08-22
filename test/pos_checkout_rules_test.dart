import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/pos/pos_checkout_rules.dart';

void main() {
  test('qty 1–99', () {
    expect(PosCheckoutRules.clampQty(0), 1);
    expect(PosCheckoutRules.clampQty(2), 2);
    expect(PosCheckoutRules.clampQty(200), 99);
  });

  test('diskon header hanya dari voucher', () {
    expect(
      PosCheckoutRules.headerDiscount(voucherCode: null, voucherNominal: 50000),
      0,
    );
    expect(
      PosCheckoutRules.headerDiscount(voucherCode: '', voucherNominal: 50000),
      0,
    );
    expect(
      PosCheckoutRules.headerDiscount(voucherCode: 'HEMAT20', voucherNominal: 20000),
      20000,
    );
  });

  test('total tidak bisa negatif', () {
    expect(
      PosCheckoutRules.totalAkhir(
        subtotal: 10000,
        voucherCode: 'X',
        voucherNominal: 99999,
      ),
      0,
    );
    expect(
      PosCheckoutRules.totalAkhir(
        subtotal: 100000,
        voucherCode: null,
        voucherNominal: 90000,
      ),
      100000,
    );
  });
}
