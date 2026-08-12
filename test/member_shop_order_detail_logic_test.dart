import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/member/member_shop_order_detail_logic.dart';

void main() {
  group('pickDefaultShippingRate', () {
    final groups = [
      {
        'title': 'OBR',
        'options': [
          {'id': 'obr-a', 'price': 12000, 'is_obr': true},
          {'id': 'obr-b', 'price': 8000, 'is_obr': true},
        ],
      },
      {
        'title': 'Reguler',
        'options': [
          {'id': 'reg-a', 'price': 15000, 'is_obr': false},
          {'id': 'reg-b', 'price': 5000, 'is_obr': false},
        ],
      },
    ];

    test('keeps previous id when still present', () {
      final picked = pickDefaultShippingRate(groups, keepId: 'reg-a');
      expect(picked?['id'], 'reg-a');
    });

    test('defaults to cheapest OBR when no keepId', () {
      final picked = pickDefaultShippingRate(groups);
      expect(picked?['id'], 'obr-b');
    });

    test('falls back to cheapest any when no OBR', () {
      final noObr = [
        {
          'title': 'X',
          'options': [
            {'id': 'a', 'price': 9000, 'is_obr': false},
            {'id': 'b', 'price': 3000, 'is_obr': false},
          ],
        },
      ];
      expect(pickDefaultShippingRate(noObr)?['id'], 'b');
    });

    test('ignores missing keepId and picks OBR', () {
      expect(
        pickDefaultShippingRate(groups, keepId: 'gone')?['id'],
        'obr-b',
      );
    });
  });

  group('memberShopOrderDetailPayBlocked', () {
    test('blocks when no selection', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: false,
          isDelivery: false,
          addressConfirmed: true,
          loadingRates: false,
          hasSelectedRate: true,
          hasRateGroups: true,
          hasRateError: false,
        ),
        isTrue,
      );
    });

    test('pickup with selection is not blocked', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: false,
          addressConfirmed: false,
          loadingRates: false,
          hasSelectedRate: false,
          hasRateGroups: false,
          hasRateError: false,
        ),
        isFalse,
      );
    });

    test('delivery without address not blocked (opens picker)', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: true,
          addressConfirmed: false,
          loadingRates: false,
          hasSelectedRate: false,
          hasRateGroups: false,
          hasRateError: false,
        ),
        isFalse,
      );
    });

    test('delivery loading rates blocked', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: true,
          addressConfirmed: true,
          loadingRates: true,
          hasSelectedRate: false,
          hasRateGroups: false,
          hasRateError: false,
        ),
        isTrue,
      );
    });

    test('delivery rate error allows tap to retry', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: true,
          addressConfirmed: true,
          loadingRates: false,
          hasSelectedRate: false,
          hasRateGroups: false,
          hasRateError: true,
        ),
        isFalse,
      );
    });

    test('delivery without rate blocked', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: true,
          addressConfirmed: true,
          loadingRates: false,
          hasSelectedRate: false,
          hasRateGroups: false,
          hasRateError: false,
        ),
        isTrue,
      );
    });

    test('delivery ready not blocked', () {
      expect(
        memberShopOrderDetailPayBlocked(
          hasSelection: true,
          isDelivery: true,
          addressConfirmed: true,
          loadingRates: false,
          hasSelectedRate: true,
          hasRateGroups: true,
          hasRateError: false,
        ),
        isFalse,
      );
    });
  });

  group('storeAllowsPickup', () {
    test('null store false', () {
      expect(storeAllowsPickup(null), isFalse);
    });

    test('missing key means allowed', () {
      expect(storeAllowsPickup({'toko_id': 'A'}), isTrue);
    });

    test('explicit false blocked', () {
      expect(storeAllowsPickup({'pickup_enabled': false}), isFalse);
    });

    test('explicit true allowed', () {
      expect(storeAllowsPickup({'pickup_enabled': true}), isTrue);
    });
  });
}
