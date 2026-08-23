import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/product_identity.dart';
import 'package:optik_b_riski/shared/logistics/stock_mutation_service.dart';
import 'package:optik_b_riski/shared/logistics/warehouse_asset_rules.dart';

void main() {
  test('modalPriceOf baca angka JSON dan ribuan Indonesia', () {
    expect(ProductIdentity.modalPriceOf({'harga_modal': 80000}), 80000);
    expect(ProductIdentity.modalPriceOf({'harga_modal': 80000.0}), 80000);
    expect(ProductIdentity.modalPriceOf({'harga_modal': '150.000'}), 150000);
    expect(ProductIdentity.modalPriceOf({}), 0);
  });

  test('stok double tidak jadi 0', () {
    expect(StockQty.parseCount(12.0), 12);
    expect(StockQty.parseCount('8.0'), 8);
    expect(StockQty.realOf({'stock': 5.0}), 5);
    expect(StockQty.pendingOf({'reserved_qty': 2.0}), 2);
  });

  test('parseSigned baca qty_delta negatif JSON', () {
    expect(StockQty.parseSigned(-2.0), -2);
    expect(StockQty.parseSigned('-2.0'), -2);
    expect(StockQty.parseSigned(-2), -2);
    expect(StockQty.parseCount(-2.0), 0);
  });

  test('satu SKU: aset = stok × modal, omzet = stok × jual', () {
    final line = WarehouseAssetRules.fromProduct({
      'stock': 4,
      'harga_modal': 50000,
      'harga_jual': 120000,
    });
    expect(line.aset, 200000);
    expect(line.omzet, 480000);
    expect(line.margin, 280000);
    expect(line.volume, 4);
  });

  test('stok 0 atau negatif tidak masuk neraca', () {
    expect(WarehouseAssetRules.fromProduct({'stock': 0, 'harga_modal': 9}).aset, 0);
    expect(
      WarehouseAssetRules.fromProduct({'stock': -2, 'harga_modal': 9}).volume,
      0,
    );
  });

  test('reserved tetap dihitung aset (barang masih di rak)', () {
    final line = WarehouseAssetRules.fromProduct({
      'stock': 10,
      'reserved_qty': 3,
      'harga_modal': 10000,
      'harga': 20000,
    });
    expect(line.volume, 10);
    expect(line.aset, 100000);
  });

  test('jumlah banyak SKU dan RPC map', () {
    final sum = WarehouseAssetRules.fromProducts([
      {'stock': 2, 'harga_modal': 10000, 'harga_jual': 15000},
      {'stock': 1, 'harga_modal': '20.000', 'harga_jual': 30000},
    ]);
    expect(sum.aset, 40000);
    expect(sum.omzet, 60000);
    expect(sum.volume, 3);

    final rpc = WarehouseAssetRules.fromRpc({
      'aset_pokok': 40000,
      'potensi_omzet': 60000,
      'proyeksi_margin': 20000,
      'volume': 3,
    });
    expect(rpc!.aset, 40000);
    expect(rpc.omzet, 60000);
    expect(rpc.margin, 20000);
    expect(rpc.volume, 3);
  });
}
