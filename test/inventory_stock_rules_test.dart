import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_admin_scope.dart';
import 'package:optik_b_riski/shared/logistics/inventory_stock_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  group('move machine', () {
    test('PREPARING to TRANSIT to SUCCESS', () {
      expect(
        InventoryStockRules.moveTransitionOk('PREPARING', 'TRANSIT'),
        isTrue,
      );
      expect(
        InventoryStockRules.moveTransitionOk('TRANSIT', 'SUCCESS'),
        isTrue,
      );
      expect(
        InventoryStockRules.moveTransitionOk('PREPARING', 'SUCCESS'),
        isFalse,
      );
    });

    test('cannot reopen SUCCESS', () {
      expect(
        InventoryStockRules.moveTransitionOk('SUCCESS', 'TRANSIT'),
        isFalse,
      );
      expect(
        InventoryStockRules.moveTransitionOk('SUCCESS', 'PREPARING'),
        isFalse,
      );
    });

    test('WAITING alias and PENDING legacy receive', () {
      expect(
        InventoryStockRules.moveTransitionOk('WAITING', 'TRANSIT'),
        isTrue,
      );
      expect(
        InventoryStockRules.moveTransitionOk('PENDING', 'SUCCESS'),
        isTrue,
      );
    });
  });

  group('who may scan', () {
    test('destination cabang cannot mark TRANSIT', () {
      expect(
        InventoryStockRules.canMarkTransit(
          scannerToko: 'CABANG-A',
          dari: 'PUSAT',
          ke: 'CABANG-A',
        ),
        isFalse,
      );
      expect(
        InventoryStockRules.canMarkTransit(
          scannerToko: 'PUSAT',
          dari: 'PUSAT',
          ke: 'CABANG-A',
        ),
        isTrue,
      );
    });

    test('receive only at tujuan + TRANSIT', () {
      expect(
        InventoryStockRules.canReceiveMove(
          receiverToko: 'CABANG-A',
          ke: 'CABANG-A',
          status: 'TRANSIT',
        ),
        isTrue,
      );
      expect(
        InventoryStockRules.canReceiveMove(
          receiverToko: 'CABANG-B',
          ke: 'CABANG-A',
          status: 'TRANSIT',
        ),
        isFalse,
      );
      expect(
        InventoryStockRules.canReceiveMove(
          receiverToko: 'CABANG-A',
          ke: 'CABANG-A',
          status: 'PREPARING',
        ),
        isFalse,
      );
    });
  });

  group('RO machine', () {
    test('forward only', () {
      expect(
        InventoryStockRules.roTransitionOk('PENDING', 'SENT_TO_HQ'),
        isTrue,
      );
      expect(
        InventoryStockRules.roTransitionOk('PREPARING', 'SHIPPING'),
        isTrue,
      );
      expect(
        InventoryStockRules.roTransitionOk('SHIPPING', 'SUCCESS'),
        isTrue,
      );
      expect(
        InventoryStockRules.roTransitionOk('PENDING', 'SUCCESS'),
        isFalse,
      );
      expect(
        InventoryStockRules.roTransitionOk('SUCCESS', 'PREPARING'),
        isFalse,
      );
      expect(
        InventoryStockRules.roTransitionOk('SHIPPING', 'REJECTED'),
        isFalse,
      );
    });

    test('qty request 1–999', () {
      expect(InventoryStockRules.clampRequestQty(0), 1);
      expect(InventoryStockRules.clampRequestQty(12), 12);
      expect(InventoryStockRules.clampRequestQty(5000), 999);
    });
  });

  group('siapa yang boleh stok', () {
    test('owner etalase tidak mutasi stok / buka logistik', () {
      expect(AttendanceAdminScope.canManageInventory(p('owner', 'PUSAT')),
          isFalse);
      expect(AttendanceAdminScope.canOpenLogistics(p('owner', 'PUSAT')),
          isFalse);
      expect(
        AttendanceAdminScope.canManageInventoryToko(p('owner', 'PUSAT'), 'PUSAT'),
        isFalse,
      );
    });

    test('admin_toko hanya toko sendiri', () {
      final cabang = p('admin_toko', 'CABANG-A');
      expect(AttendanceAdminScope.canManageInventory(cabang), isTrue);
      expect(
        AttendanceAdminScope.canManageInventoryToko(cabang, 'CABANG-A'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canManageInventoryToko(cabang, 'CABANG-B'),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canViewAllStores(p('admin_toko', 'PUSAT')),
        isFalse,
      );
    });

    test('kasir boleh RO toko sendiri, bukan write-off cabang orang', () {
      final kasir = p('kasir', 'CABANG-A');
      expect(AttendanceAdminScope.canManageInventory(kasir), isFalse);
      expect(
        AttendanceAdminScope.canRequestRoToko(kasir, 'CABANG-A'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canRequestRoToko(kasir, 'CABANG-B'),
        isFalse,
      );
    });

    test('admin_pusat semua toko tenant', () {
      expect(
        AttendanceAdminScope.canManageInventoryToko(
          p('admin_pusat', 'PUSAT'),
          'CABANG-A',
        ),
        isTrue,
      );
    });
  });
}
