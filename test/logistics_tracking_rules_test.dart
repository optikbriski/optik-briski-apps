import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/logistics_tracking_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('owner / kasir tidak boleh buka tracking', () {
    expect(LogisticsTrackingRules.bolehBuka(p('owner', 'PUSAT')), isFalse);
    expect(LogisticsTrackingRules.bolehBuka(p('kasir', 'CABANG-A')), isFalse);
    expect(LogisticsTrackingRules.bolehBuka(p('admin_toko', 'CABANG-A')), isTrue);
    expect(LogisticsTrackingRules.bolehBuka(p('admin_pusat', 'PUSAT')), isTrue);
  });

  test('hub tracking hanya admin_pusat / super_admin', () {
    expect(LogisticsTrackingRules.isHub(p('admin_pusat', 'PUSAT')), isTrue);
    expect(LogisticsTrackingRules.isHub(p('super_admin', 'PUSAT')), isTrue);
    expect(LogisticsTrackingRules.isHub(p('admin_toko', 'PUSAT')), isFalse);
    expect(LogisticsTrackingRules.isHub(p('owner', 'PUSAT')), isFalse);
  });

  test('cabang tujuan tidak ganti kurir DO Pusat', () {
    final cabang = p('admin_toko', 'CABANG-A');
    expect(
      LogisticsTrackingRules.bolehAssignKurir(
        profile: cabang,
        dari: 'PUSAT',
        status: 'TRANSIT',
      ),
      isFalse,
    );
    expect(
      LogisticsTrackingRules.bolehAssignKurir(
        profile: cabang,
        dari: 'CABANG-A',
        status: 'PENDING',
      ),
      isTrue,
    );
    expect(
      LogisticsTrackingRules.bolehAssignKurir(
        profile: p('admin_pusat', 'PUSAT'),
        dari: 'PUSAT',
        status: 'TRANSIT',
      ),
      isTrue,
    );
  });

  test('kurir terkunci setelah SUCCESS / BATAL', () {
    expect(LogisticsTrackingRules.statusBolehKurir('PREPARING'), isTrue);
    expect(LogisticsTrackingRules.statusBolehKurir('TRANSIT'), isTrue);
    expect(LogisticsTrackingRules.statusBolehKurir('SUCCESS'), isFalse);
    expect(LogisticsTrackingRules.statusBolehKurir('BATAL'), isFalse);
    expect(
      LogisticsTrackingRules.bolehAssignKurir(
        profile: p('admin_pusat', 'PUSAT'),
        dari: 'PUSAT',
        status: 'SUCCESS',
      ),
      isFalse,
    );
  });
}
