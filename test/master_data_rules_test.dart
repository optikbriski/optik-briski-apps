import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/master_data_rules.dart';
import 'package:optik_b_riski/shared/logistics/master_data_service.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('kasir tidak buka Master Data; admin/owner boleh', () {
    expect(MasterDataRules.bolehBuka(p('kasir', 'CABANG-A')), isFalse);
    expect(MasterDataRules.bolehBuka(p('admin_toko', 'CABANG-A')), isTrue);
    expect(MasterDataRules.bolehBuka(p('admin_pusat', 'PUSAT')), isTrue);
    expect(MasterDataRules.bolehBuka(p('owner', 'PUSAT')), isTrue);
  });

  test('PUSAT = CABANG-PUSAT; cabang orang bukan gudang Pusat', () {
    expect(MasterDataRules.lihatSemuaToko(p('admin_toko', 'CABANG-PUSAT')), isTrue);
    expect(MasterDataRules.lihatSemuaToko(p('admin_toko', 'PUSAT')), isTrue);
    expect(MasterDataRules.lihatSemuaToko(p('admin_toko', 'CABANG-A')), isFalse);
    expect(MasterDataRules.isCabangToko('CABANG-A'), isTrue);
    expect(MasterDataRules.isCabangToko('PUSAT'), isFalse);
    expect(MasterDataRules.isCabangToko('CABANG-PUSAT'), isFalse);
    expect(MasterDataRules.sameStore('PUSAT', 'CABANG-PUSAT'), isTrue);
  });

  test('harga / stok baca JSON 150000.0 dan 7.0', () {
    expect(MasterDataRules.hargaOf(150000.0), 150000);
    expect(MasterDataRules.hargaOf('150.000'), 150000);
    expect(MasterDataRules.stokOf(7.0), 7);
    expect(MasterDataRules.stokOf('7.0'), 7);
  });

  test('PUSAT + CABANG-PUSAT satu slot, stok tidak dobel', () {
    expect(MasterDataRules.canonicalToko('CABANG-PUSAT'), 'PUSAT');
    expect(MasterDataRules.canonicalToko('cabang-a'), 'CABANG-A');
    final merged = MasterDataService.mergeBySku([
      {
        'id': '1',
        'sku': 'X',
        'toko_id': 'CABANG-PUSAT',
        'stock': 10,
        'reserved_qty': 0,
        'nama': 'Alias',
      },
      {
        'id': '2',
        'sku': 'X',
        'toko_id': 'PUSAT',
        'stock': 0,
        'reserved_qty': 0,
        'nama': 'Pusat',
      },
      {
        'id': '3',
        'sku': 'X',
        'toko_id': 'CABANG-A',
        'stock': 5,
        'reserved_qty': 0,
        'nama': 'Cabang',
      },
    ]);
    expect(merged, hasLength(1));
    expect(merged.first['total_stock'], 15);
    expect(merged.first['nama'], 'Pusat');
    final bd = (merged.first['breakdown_stok'] as List)
        .map((e) => (e as Map)['cabang'])
        .toList();
    expect(bd, containsAll(['PUSAT', 'CABANG-A']));
    expect(bd, hasLength(2));
  });
}
