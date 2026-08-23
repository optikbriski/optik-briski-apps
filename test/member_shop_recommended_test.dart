import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/member/pages/member_shop_home_page.dart';

void main() {
  Map<String, dynamic> p({
    required String sku,
    String kategori = 'Frame',
    int harga = 100000,
    int? hargaAsli,
    int? availableQty,
    bool omitAvailableQty = false,
  }) =>
      {
        'sku': sku,
        'nama': sku,
        'kategori': kategori,
        'harga': harga,
        if (hargaAsli != null) 'harga_asli': hargaAsli,
        if (!omitAvailableQty && availableQty != null)
          'available_qty': availableQty,
      };

  test('excludes lensa and zero/invalid harga', () {
    final out = pickMemberShopRecommended([
      p(sku: 'L1', kategori: 'Lensa', availableQty: 5),
      p(sku: 'L2', kategori: 'LENSA', availableQty: 5),
      p(sku: 'F0', harga: 0, availableQty: 5),
      p(sku: 'F1', availableQty: 3),
    ]);
    expect(out.map((e) => e['sku']), ['F1']);
  });

  test('keeps OOS Frame/Lainnya for pre-order but ranks in-stock first', () {
    final out = pickMemberShopRecommended([
      p(sku: 'OOS', availableQty: 0, hargaAsli: 200000),
      p(sku: 'ACC', kategori: 'Lainnya', availableQty: 0),
      p(sku: 'OK', availableQty: 2, hargaAsli: 110000),
    ]);
    expect(out.map((e) => e['sku']), ['OK', 'OOS', 'ACC']);
  });

  test('among same stock rank, larger discount wins; respects limit', () {
    final out = pickMemberShopRecommended(
      [
        p(sku: 'A', availableQty: 1, harga: 80, hargaAsli: 100), // disc 20
        p(sku: 'B', availableQty: 1, harga: 50, hargaAsli: 100), // disc 50
        p(sku: 'C', availableQty: 1, harga: 90, hargaAsli: 100), // disc 10
      ],
      limit: 2,
    );
    expect(out.map((e) => e['sku']), ['B', 'A']);
  });

  test('dedupes SKU case-insensitively; skips empty SKU', () {
    final out = pickMemberShopRecommended([
      p(sku: '', availableQty: 9, hargaAsli: 500),
      p(sku: 'f1', availableQty: 0, hargaAsli: 200), // worse rank
      p(sku: 'F1', availableQty: 3, hargaAsli: 150), // better; keep first after sort
      p(sku: 'F2', availableQty: 1),
    ]);
    expect(out.map((e) => e['sku']), ['F1', 'F2']);
    expect(out.first['available_qty'], 3);
  });

  test('harga_jual-only frame is buyable', () {
    final out = pickMemberShopRecommended([
      {
        'sku': 'HJ1',
        'nama': 'HJ1',
        'kategori': 'Frame',
        'harga_jual': 175000,
        'available_qty': 2,
      },
    ]);
    expect(out.map((e) => e['sku']), ['HJ1']);
  });

  test('missing available_qty is not treated as out-of-stock', () {
    expect(memberShopIsOutOfStock(p(sku: 'X', omitAvailableQty: true)), isFalse);
    expect(memberShopIsOutOfStock(p(sku: 'Y', availableQty: 0)), isTrue);
    expect(memberShopIsOutOfStock(p(sku: 'Z', availableQty: 2)), isFalse);

    final out = pickMemberShopRecommended([
      p(sku: 'OOS', availableQty: 0, hargaAsli: 300),
      p(sku: 'UNK', omitAvailableQty: true, hargaAsli: 100),
    ]);
    expect(out.map((e) => e['sku']), ['UNK', 'OOS']);
  });
}
