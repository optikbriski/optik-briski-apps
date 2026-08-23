import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/do_cart_lines.dart';
import 'package:optik_b_riski/shared/logistics/do_lifecycle_rules.dart';
import 'package:optik_b_riski/shared/logistics/product_identity.dart';

void main() {
  test('baris DO pakai modal/jual/foto yang sama dengan katalog', () {
    final line = DoCartLines.fromProduct({
      'id': 'p1',
      'nama': 'Frame A',
      'sku': 'SKU-1',
      'barcode': 'B1',
      'harga_modal': 150000.0,
      'harga_jual': '250.000',
      'image_url': 'https://cdn.example/a.jpg',
      'kategori': 'FRAME',
      'warna': 'Hitam',
    }, 2);
    expect(line['sku'], 'SKU-1');
    expect(line['qty'], 2);
    expect(line['harga_modal'], 150000);
    expect(line['harga_jual'], 250000);
    expect(line['harga'], 250000);
    expect(line['image_url'], 'https://cdn.example/a.jpg');
    expect(line['foto_url'], 'https://cdn.example/a.jpg');
  });

  test('keterangan dengan prefix dan spasi setelah [ tetap terbaca', () {
    const raw =
        'RequestOrder#9 | Invoice INV-1 | [ { "sku": "A", "qty": 2.0 } ]';
    final items = DoCartLines.parseKeterangan(raw);
    expect(items, hasLength(1));
    expect(ProductIdentity.skuOf(items.first), 'A');
    expect(DoCartLines.qtyOf(items.first), 2);
  });

  test('array kosong / tanpa kurung = tidak ada item', () {
    expect(DoCartLines.parseKeterangan(''), isEmpty);
    expect(DoCartLines.parseKeterangan('tanpa json'), isEmpty);
    expect(DoCartLines.parseKeterangan('[]'), isEmpty);
  });

  test('normalize draf: 150.000 modal dan qty 3.0', () {
    final n = DoCartLines.normalize({
      'sku': 'X',
      'qty': 3.0,
      'harga_modal': '150.000',
      'harga': 200000,
    });
    expect(n['qty'], 3);
    expect(n['harga_modal'], 150000);
    expect(n['harga_jual'], 200000);
  });

  test('mesin status DO tidak berubah: buat PREPARING, kirim TRANSIT, terima SUCCESS', () {
    expect(DoLifecycleRules.canInsertStatus('DELIVERY', 'PREPARING'), isTrue);
    expect(DoLifecycleRules.moveTransitionOk('PREPARING', 'TRANSIT'), isTrue);
    expect(DoLifecycleRules.moveTransitionOk('TRANSIT', 'SUCCESS'), isTrue);
    expect(DoLifecycleRules.moveTransitionOk('PREPARING', 'SUCCESS'), isFalse);
  });
}
