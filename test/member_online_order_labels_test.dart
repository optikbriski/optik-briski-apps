import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_online_order_labels.dart';
import 'package:optik_b_riski/shared/member/member_online_order_rules.dart';

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

  group('MemberOnlineOrderRules', () {
    test('CABANG-PUSAT staff sees Pusat orders', () {
      expect(
        MemberOnlineOrderRules.orderBelongsToStaff(
          pusatRole: false,
          staffTokoId: 'CABANG-PUSAT',
          orderTokoId: 'PUSAT',
        ),
        isTrue,
      );
      expect(
        MemberOnlineOrderRules.orderBelongsToStaff(
          pusatRole: false,
          staffTokoId: 'CABANG-A',
          orderTokoId: 'CABANG-B',
        ),
        isFalse,
      );
      expect(
        MemberOnlineOrderRules.orderBelongsToStaff(
          pusatRole: true,
          staffTokoId: 'CABANG-A',
          orderTokoId: 'CABANG-B',
        ),
        isTrue,
      );
    });

    test('preorder qty JSON 2.0 is still preorder', () {
      expect(
        MemberOnlineOrderRules.hasPreorder({
          'items': [
            {'preorder_qty': 2.0},
          ],
        }),
        isTrue,
      );
      expect(
        MemberOnlineOrderRules.hasPreorder({
          'items': [
            {'preorder_qty': '0.0'},
          ],
        }),
        isFalse,
      );
    });

    test('money/qty JSON', () {
      expect(MemberOnlineOrderRules.moneyOf('150000.0'), 150000);
      expect(MemberOnlineOrderRules.countOf('7.0'), 7);
    });
  });
}
