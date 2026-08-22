import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_admin_scope.dart';
import 'package:optik_b_riski/shared/logistics/do_lifecycle_rules.dart';
import 'package:optik_b_riski/shared/logistics/inventory_stock_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  group('DO machine 000027', () {
    test('PREPARING to TRANSIT to SUCCESS, not PENDING skip', () {
      expect(
        DoLifecycleRules.moveTransitionOk('PREPARING', 'TRANSIT'),
        isTrue,
      );
      expect(
        DoLifecycleRules.moveTransitionOk('TRANSIT', 'SUCCESS'),
        isTrue,
      );
      expect(
        DoLifecycleRules.moveTransitionOk('PREPARING', 'PENDING'),
        isFalse,
      );
      expect(
        DoLifecycleRules.moveTransitionOk('PREPARING', 'SUCCESS'),
        isFalse,
      );
      expect(
        InventoryStockRules.moveTransitionOk('PREPARING', 'PENDING'),
        isFalse,
      );
    });

    test('BATAL only before ship; PENDING legacy can receive', () {
      expect(DoLifecycleRules.canCancelMove('PREPARING'), isTrue);
      expect(DoLifecycleRules.canCancelMove('TRANSIT'), isFalse);
      expect(
        DoLifecycleRules.moveTransitionOk('TRANSIT', 'BATAL'),
        isFalse,
      );
      expect(
        DoLifecycleRules.moveTransitionOk('PENDING', 'SUCCESS'),
        isTrue,
      );
      expect(DoLifecycleRules.isReceiveReady('PENDING'), isTrue);
      expect(
        DoLifecycleRules.moveTransitionOk('WAITING', 'PREPARING'),
        isTrue,
      );
    });

    test('cannot insert TRANSIT/SUCCESS; PENDING only retur', () {
      expect(
        DoLifecycleRules.canInsertStatus('DELIVERY', 'PREPARING'),
        isTrue,
      );
      expect(
        DoLifecycleRules.canInsertStatus('DELIVERY', 'TRANSIT'),
        isFalse,
      );
      expect(
        DoLifecycleRules.canInsertStatus('DELIVERY', 'PENDING'),
        isFalse,
      );
      expect(
        DoLifecycleRules.canInsertStatus('RETUR', 'PENDING'),
        isTrue,
      );
    });

    test('DO/RO from Pusat; retur to Pusat', () {
      expect(DoLifecycleRules.deliveryOriginOk('PUSAT'), isTrue);
      expect(DoLifecycleRules.deliveryOriginOk('CABANG-PUSAT'), isTrue);
      expect(DoLifecycleRules.deliveryOriginOk('CABANG-A'), isFalse);
      expect(DoLifecycleRules.returDestinationOk('PUSAT'), isTrue);
      expect(DoLifecycleRules.returDestinationOk('CABANG-A'), isFalse);
    });
  });

  group('siapa terima DO', () {
    test('owner tidak terima; admin_toko hanya tujuan sendiri', () {
      expect(
        AttendanceAdminScope.canReceiveStockToko(p('owner', 'PUSAT'), 'PUSAT'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canReceiveStockToko(
          p('admin_toko', 'CABANG-A'),
          'CABANG-A',
        ),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canReceiveStockToko(
          p('admin_toko', 'CABANG-A'),
          'CABANG-B',
        ),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canReceiveStockToko(
          p('kasir', 'CABANG-A'),
          'CABANG-A',
        ),
        isFalse,
      );
    });
  });
}
