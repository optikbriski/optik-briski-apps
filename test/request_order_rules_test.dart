import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/logistics/request_order_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  test('owner tidak buka RO; kasir/admin cabang boleh antrian toko sendiri', () {
    expect(RequestOrderRules.bolehBukaCabang(p('owner', 'PUSAT')), isFalse);
    expect(RequestOrderRules.bolehBukaCabang(p('kasir', 'CABANG-A')), isTrue);
    expect(RequestOrderRules.bolehBukaCabang(p('admin_toko', 'CABANG-A')), isTrue);
  });

  test('hanya gudang Pusat yang approve / kirim', () {
    expect(RequestOrderRules.bolehProsesPusat(p('admin_toko', 'CABANG-A')), isFalse);
    expect(RequestOrderRules.bolehProsesPusat(p('kasir', 'CABANG-A')), isFalse);
    expect(RequestOrderRules.bolehProsesPusat(p('owner', 'PUSAT')), isFalse);
    expect(RequestOrderRules.bolehProsesPusat(p('admin_pusat', 'PUSAT')), isTrue);
    expect(RequestOrderRules.bolehProsesPusat(p('admin_toko', 'PUSAT')), isTrue);
    expect(RequestOrderRules.openStatuses.contains('SHIPPING'), isTrue);
    expect(RequestOrderRules.openStatuses.contains('SUCCESS'), isFalse);
  });

  test('cabang hanya kirim PENDING ke Pusat; tidak SHIPPING sendiri', () {
    final cabang = p('admin_toko', 'CABANG-A');
    expect(
      RequestOrderRules.bolehKirimKePusat(
        profile: cabang,
        tokoId: 'CABANG-A',
        status: 'PENDING',
      ),
      isTrue,
    );
    expect(
      RequestOrderRules.bolehKirim(
        profile: cabang,
        status: 'PREPARING',
      ),
      isFalse,
    );
    expect(
      RequestOrderRules.bolehApprove(
        profile: cabang,
        status: 'SENT_TO_HQ',
      ),
      isFalse,
    );
    expect(
      RequestOrderRules.bolehKirimKePusat(
        profile: cabang,
        tokoId: 'CABANG-A',
        status: 'SENT_TO_HQ',
      ),
      isFalse,
    );
    expect(
      RequestOrderRules.bolehKirimKePusat(
        profile: cabang,
        tokoId: 'CABANG-B',
        status: 'PENDING',
      ),
      isFalse,
    );
  });

  test('tidak boleh tolak setelah barang jalan / selesai', () {
    final pusat = p('admin_pusat', 'PUSAT');
    expect(
      RequestOrderRules.bolehTolak(profile: pusat, status: 'PREPARING'),
      isTrue,
    );
    expect(
      RequestOrderRules.bolehTolak(profile: pusat, status: 'SHIPPING'),
      isFalse,
    );
    expect(
      RequestOrderRules.transisiOk('SHIPPING', 'REJECTED'),
      isFalse,
    );
    expect(
      RequestOrderRules.transisiOk('PENDING', 'SUCCESS'),
      isFalse,
    );
  });

  test('idOf / qtyOf baca JSON 123.0 dan 2.0', () {
    expect(RequestOrderRules.idOf(123.0), 123);
    expect(RequestOrderRules.idOf('123.0'), 123);
    expect(RequestOrderRules.idOf(0), isNull);
    expect(RequestOrderRules.qtyOf(2.0), 2);
    expect(RequestOrderRules.qtyOf('2.0'), 2);
    expect(RequestOrderRules.qtyOf(0), 0);
    expect(RequestOrderRules.qtyOf(2000), 999);
  });
}
