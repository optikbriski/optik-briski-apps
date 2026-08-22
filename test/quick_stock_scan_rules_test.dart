import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/quick_stock_scan_rules.dart';
import 'package:optik_b_riski/shared/qr/product_code.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('owner / kasir tidak buka tile scan; admin toko boleh', () {
    expect(QuickStockScanRules.bolehBuka(p('owner', 'PUSAT')), isFalse);
    expect(QuickStockScanRules.bolehBuka(p('kasir', 'CABANG-A')), isFalse);
    expect(QuickStockScanRules.bolehBuka(p('admin_toko', 'CABANG-A')), isTrue);
    expect(QuickStockScanRules.bolehBuka(p('admin_pusat', 'PUSAT')), isTrue);
  });

  test('admin_toko hanya scan toko sendiri; bukan cabang orang', () {
    final cabang = p('admin_toko', 'CABANG-A');
    expect(QuickStockScanRules.bolehScanToko(cabang, 'CABANG-A'), isTrue);
    expect(QuickStockScanRules.bolehScanToko(cabang, 'CABANG-B'), isFalse);
    expect(
      QuickStockScanRules.bolehScanToko(p('admin_pusat', 'PUSAT'), 'CABANG-B'),
      isTrue,
    );
    expect(
      QuickStockScanRules.bolehScanToko(p('owner', 'PUSAT'), 'PUSAT'),
      isFalse,
    );
  });

  test('hanya kode produk; invoice / absensi / JSON ditolak', () {
    expect(QuickStockScanRules.codeOk('SKU-123'), isTrue);
    expect(
      QuickStockScanRules.codeOk(ProductCode.encode(sku: 'SKU-123')),
      isTrue,
    );
    expect(QuickStockScanRules.codeOk('OBRATT|v1|x'), isFalse);
    expect(QuickStockScanRules.codeOk('{"resi":"DO-1"}'), isFalse);
    expect(
      QuickStockScanRules.codeOk('https://app.example/i/abc'),
      isFalse,
    );
    expect(QuickStockScanRules.codeOk(''), isFalse);
    expect(QuickStockScanRules.codeOk('x' * 201), isFalse);
  });

  test('scan tidak boleh mengubah angka stok', () {
    expect(
      QuickStockScanRules.stokTetap(stockBefore: 7, stockAfter: 7),
      isTrue,
    );
    expect(
      QuickStockScanRules.stokTetap(stockBefore: 7, stockAfter: 6),
      isFalse,
    );
  });
}
