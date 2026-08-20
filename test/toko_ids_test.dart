import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/toko_ids.dart';

void main() {
  test('Optik PUSAT and CABANG-PUSAT are pusat', () {
    expect(TokoIds.isPusat('PUSAT'), isTrue);
    expect(TokoIds.isPusat('cabang-pusat'), isTrue);
  });

  test('UMKM pusat uses suffix, not Optik PUSAT', () {
    expect(TokoIds.isPusat('MAJU-PUSAT'), isTrue);
    expect(TokoIds.isPusat('CABANG-CIMAHI'), isFalse);
    expect(TokoIds.isPusat('MAJU-CABANG-1'), isFalse);
  });

  test('bound pusat_toko_id wins', () {
    expect(
      TokoIds.isPusat('ABC123-PUSAT', tenantPusatTokoId: 'ABC123-PUSAT'),
      isTrue,
    );
  });
}
