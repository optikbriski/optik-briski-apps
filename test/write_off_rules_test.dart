import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/write_off_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('alasan write-off minimal 3 karakter setelah trim', () {
    expect(WriteOffRules.alasanCukup('ab'), isFalse);
    expect(WriteOffRules.alasanCukup('  x  '), isFalse);
    expect(WriteOffRules.alasanCukup('   rusak   '), isTrue);
    expect(WriteOffRules.alasanCukup('retur pabrik'), isTrue);
  });

  test('qty write-off harus positif', () {
    expect(WriteOffRules.qtyValid(0), isFalse);
    expect(WriteOffRules.qtyValid(-1), isFalse);
    expect(WriteOffRules.qtyValid(2), isTrue);
  });

  test('owner / kasir tidak boleh buka tile write-off', () {
    expect(WriteOffRules.bolehBuka(p('owner', 'PUSAT')), isFalse);
    expect(WriteOffRules.bolehBuka(p('kasir', 'CABANG-A')), isFalse);
    expect(WriteOffRules.bolehBuka(p('admin_toko', 'CABANG-A')), isTrue);
    expect(WriteOffRules.bolehBuka(p('admin_pusat', 'PUSAT')), isTrue);
  });

  test('admin_toko hanya toko sendiri; pusat semua cabang tenant', () {
    final cabang = p('admin_toko', 'CABANG-A');
    expect(WriteOffRules.bolehWriteOffToko(cabang, 'CABANG-A'), isTrue);
    expect(WriteOffRules.bolehWriteOffToko(cabang, 'CABANG-B'), isFalse);
    expect(
      WriteOffRules.bolehWriteOffToko(p('admin_pusat', 'PUSAT'), 'CABANG-B'),
      isTrue,
    );
    expect(
      WriteOffRules.bolehWriteOffToko(p('owner', 'PUSAT'), 'PUSAT'),
      isFalse,
    );
  });

  test('tidak boleh write-off melebihi stok tersedia', () {
    expect(
      WriteOffRules.tersediaCukup(real: 10, reserved: 4, qty: 7),
      isFalse,
    );
    expect(
      WriteOffRules.tersediaCukup(real: 10, reserved: 4, qty: 6),
      isTrue,
    );
    expect(
      WriteOffRules.tersediaCukup(real: 2, reserved: 0, qty: 0),
      isFalse,
    );
  });

  test('delta write-off selalu negatif', () {
    expect(WriteOffRules.qtyDelta(3), -3);
    expect(WriteOffRules.qtyDelta(-3), -3);
  });
}
