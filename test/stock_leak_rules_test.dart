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

  test('stockOf baca JSON 8.0; negatif jadi 0', () {
    expect(StockLeakRules.stockOf(8.0), 8);
    expect(StockLeakRules.stockOf('8.0'), 8);
    expect(StockLeakRules.stockOf(-2), 0);
  });

  test('deltaOf baca WRITE_OFF -2.0 tetap negatif', () {
    expect(StockLeakRules.deltaOf(-2.0), -2);
    expect(StockLeakRules.deltaOf('-2.0'), -2);
    expect(StockLeakRules.writeOffPcs(-2.0), 2);
    expect(StockLeakRules.writeOffPcsOf({'WRITE_OFF': -2, 'OPENING': 10}), 2);
  });

  test('PUSAT dan CABANG-PUSAT satu kunci toko', () {
    expect(StockLeakRules.tokoKey('cabang-pusat'), 'PUSAT');
    expect(StockLeakRules.tokoKey('PUSAT'), 'PUSAT');
    expect(StockLeakRules.tokoKey('CABANG-A'), 'CABANG-A');
  });

  test('WRITE_OFF -2.0 masuk Σ ledger — bukan bocor palsu', () {
    final stock = StockLeakRules.stockOf(8.0);
    final ledger = StockLeakRules.deltaOf(10.0) + StockLeakRules.deltaOf(-2.0);
    expect(stock, 8);
    expect(ledger, 8);
    expect(StockLeakRules.sinkron(stock: stock, ledgerSum: ledger), isTrue);
    expect(
      StockLeakRules.sinkron(
        stock: StockLeakRules.stockOf(8.0),
        ledgerSum: StockLeakRules.deltaOf(10.0),
      ),
      isFalse,
    );
  });
}
