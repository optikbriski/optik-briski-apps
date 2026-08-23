import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/product_identity.dart';

void main() {
  test('sellPriceOf pakai harga, fallback harga_jual', () {
    expect(ProductIdentity.sellPriceOf({'harga': 150000}), 150000);
    expect(ProductIdentity.sellPriceOf({'harga_jual': 99000}), 99000);
    expect(
      ProductIdentity.sellPriceOf({'harga': 1, 'harga_jual': 9}),
      1,
    );
    expect(ProductIdentity.sellPriceOf({}), 0);
  });

  test('catalog fields menulis harga + harga_jual + foto', () {
    expect(
      ProductIdentity.catalogPriceFields(250000, modal: 100000),
      {
        'harga': 250000,
        'harga_jual': 250000,
        'harga_modal': 100000,
      },
    );
    expect(
      ProductIdentity.catalogImageFields('https://x/a.jpg'),
      {
        'image_url': 'https://x/a.jpg',
        'foto_url': 'https://x/a.jpg',
      },
    );
    expect(ProductIdentity.catalogImageFields(''), isEmpty);
  });
}
