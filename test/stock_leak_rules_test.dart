import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/stock_leak_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('alasan rekognisi minimal 3 karakter setelah trim', () {
    expect(StockLeakRules.alasanCukup('ab'), isFalse);
    expect(StockLeakRules.alasanCukup('  x  '), isFalse);
    expect(StockLeakRules.alasanCukup('   opname   '), isTrue);
  });

  test('owner / kasir tidak boleh buka cek kebocoran', () {
    expect(StockLeakRules.bolehBuka(p('owner', 'PUSAT')), isFalse);
    expect(StockLeakRules.bolehBuka(p('kasir', 'CABANG-A')), isFalse);
    expect(StockLeakRules.bolehBuka(p('admin_toko', 'CABANG-A')), isTrue);
    expect(StockLeakRules.bolehBuka(p('admin_pusat', 'PUSAT')), isTrue);
  });

  test('admin_toko hanya catat selisih toko sendiri', () {
    final cabang = p('admin_toko', 'CABANG-A');
    expect(StockLeakRules.bolehRecognizeToko(cabang, 'CABANG-A'), isTrue);
    expect(StockLeakRules.bolehRecognizeToko(cabang, 'CABANG-B'), isFalse);
    expect(
      StockLeakRules.bolehRecognizeToko(p('admin_pusat', 'PUSAT'), 'CABANG-B'),
      isTrue,
    );
    expect(
      StockLeakRules.bolehRecognizeToko(p('owner', 'PUSAT'), 'PUSAT'),
      isFalse,
    );
  });

  test('hanya admin_pusat / super_admin yang scan semua cabang', () {
    expect(StockLeakRules.scanSemuaToko(p('admin_pusat', 'PUSAT')), isTrue);
    expect(StockLeakRules.scanSemuaToko(p('super_admin', 'PUSAT')), isTrue);
    expect(StockLeakRules.scanSemuaToko(p('admin_toko', 'PUSAT')), isFalse);
    expect(StockLeakRules.scanSemuaToko(p('owner', 'PUSAT')), isFalse);
  });

  test('rekognisi tidak boleh mengubah stok rak', () {
    expect(StockLeakRules.stokTetap(stockBefore: 10, stockAfter: 10), isTrue);
    expect(StockLeakRules.stokTetap(stockBefore: 10, stockAfter: 9), isFalse);
    expect(StockLeakRules.adaSelisih(0), isFalse);
    expect(StockLeakRules.adaSelisih(-3), isTrue);
  });
}
