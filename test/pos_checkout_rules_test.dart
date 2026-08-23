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

  test('LUNAS 2 SKU: bayar penuh tidak dipotong saat baris pertama masuk', () {
    final afterFirst = PosCheckoutRules.recomputeHeader(
      itemSubtotalSum: 100000,
      voucherDiscount: 0,
      intendedBayar: 200000,
    );
    expect(afterFirst.dibayar, 200000);
    expect(afterFirst.sisa, 0);
    expect(afterFirst.status, 'LUNAS');

    final afterBoth = PosCheckoutRules.recomputeHeader(
      itemSubtotalSum: 200000,
      voucherDiscount: 0,
      intendedBayar: 200000,
    );
    expect(afterBoth.total, 200000);
    expect(afterBoth.dibayar, 200000);
    expect(afterBoth.sisa, 0);
    expect(afterBoth.status, 'LUNAS');
  });

  test('laci kasir: Tunai dan CASH sama-sama tunai', () {
    expect(PosCheckoutRules.isCashMethod('Tunai'), isTrue);
    expect(PosCheckoutRules.isCashMethod('CASH'), isTrue);
    expect(PosCheckoutRules.isCashMethod('QRIS'), isFalse);
    expect(PosCheckoutRules.isCashMethod('Transfer'), isFalse);
  });

  test('DP 2 SKU: uang muka tetap, sisa naik setelah semua baris', () {
    final afterFirst = PosCheckoutRules.recomputeHeader(
      itemSubtotalSum: 100000,
      voucherDiscount: 0,
      intendedBayar: 50000,
    );
    expect(afterFirst.status, 'DP');
    expect(afterFirst.dibayar, 50000);
    expect(afterFirst.sisa, 50000);

    final afterBoth = PosCheckoutRules.recomputeHeader(
      itemSubtotalSum: 200000,
      voucherDiscount: 0,
      intendedBayar: 50000,
    );
    expect(afterBoth.status, 'DP');
    expect(afterBoth.dibayar, 50000);
    expect(afterBoth.sisa, 150000);
  });
}
