import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/product_identity.dart';

void main() {
  test('sellPriceOf pakai harga_jual, fallback harga', () {
    expect(ProductIdentity.sellPriceOf({'harga': 150000}), 150000);
    expect(ProductIdentity.sellPriceOf({'harga_jual': 99000}), 99000);
    expect(
      ProductIdentity.sellPriceOf({'harga': 200000, 'harga_jual': 150000}),
      150000,
    );
    expect(ProductIdentity.sellPriceOf({'harga': 0, 'harga_jual': 88000}), 88000);
    expect(ProductIdentity.sellPriceOf({}), 0);
    expect(ProductIdentity.sellPriceOf({'harga_jual': 150000.0}), 150000);
    expect(ProductIdentity.sellPriceOf({'harga_jual': '150.000'}), 150000);
    expect(ProductIdentity.sellPriceOf({'harga_jual': '150.000,50'}), 150001);
    expect(ProductIdentity.moneyOf(150000.0), 150000);
    expect(ProductIdentity.countOf(7.0), 7);
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
      ProductIdentity.cartPriceFields(175000),
      {
        'harga': 175000,
        'harga_jual': 175000,
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
    expect(ProductIdentity.catalogImageFields('-'), isEmpty);
  });

  test('catalogImageOf pakai image_url, fallback foto_url', () {
    expect(
      ProductIdentity.catalogImageOf({'image_url': 'https://a/x.jpg'}),
      'https://a/x.jpg',
    );
    expect(
      ProductIdentity.catalogImageOf({'foto_url': 'https://b/y.jpg'}),
      'https://b/y.jpg',
    );
    expect(
      ProductIdentity.catalogImageOf({
        'image_url': '-',
        'foto_url': 'https://c/z.jpg',
      }),
      'https://c/z.jpg',
    );
    expect(ProductIdentity.catalogImageOf({}), '');
  });
}
