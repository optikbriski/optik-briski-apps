import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_online_order_labels.dart';

void main() {
  group('MemberOnlineOrderLabels', () {
    test('known statuses are humanized', () {
      expect(
        MemberOnlineOrderLabels.status('pending_payment'),
        'Menunggu pembayaran',
      );
      expect(MemberOnlineOrderLabels.status('fulfilled'), 'Selesai');
    });

    test('unknown SCREAMING_SNAKE is title-cased not raw', () {
      expect(
        MemberOnlineOrderLabels.status('FOO_BAR'),
        'Foo Bar',
      );
      expect(MemberOnlineOrderLabels.status('FOO_BAR').contains('_'), isFalse);
    });

    test('fulfillment labels', () {
      expect(MemberOnlineOrderLabels.fulfillment('pickup'), 'Ambil di toko');
      expect(
        MemberOnlineOrderLabels.fulfillment('delivery'),
        'Kirim ke alamat',
      );
    });

    test('salesTrackingLabel does not leak raw keys', () {
      expect(
        MemberOnlineOrderLabels.salesTrackingLabel('SIAP_DIAMBIL'),
        'Siap diambil',
      );
      expect(
        MemberOnlineOrderLabels.salesTrackingLabel('WEIRD_STATUS'),
        'Weird Status',
      );
    });
  });
}
