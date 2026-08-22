import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_admin_scope.dart';
import 'package:optik_b_riski/shared/logistics/stock_move_report_rules.dart';

void main() {
  Map<String, dynamic> p(String role, String toko) => {
        'role': role,
        'toko_id': toko,
      };

  group('siapa lihat laporan mutasi', () {
    test('admin_pusat hub semua cabang; admin_toko PUSAT bukan hub', () {
      expect(
        StockMoveReportRules.isTenantWideHistoryView(p('admin_pusat', 'PUSAT')),
        isTrue,
      );
      expect(
        StockMoveReportRules.isTenantWideHistoryView(p('super_admin', 'PUSAT')),
        isTrue,
      );
      expect(
        StockMoveReportRules.isTenantWideHistoryView(p('admin_toko', 'PUSAT')),
        isFalse,
      );
      expect(
        StockMoveReportRules.isTenantWideHistoryView(p('owner', 'PUSAT')),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canViewAllStores(p('admin_toko', 'PUSAT')),
        isFalse,
      );
    });

    test('cabang tujuan tidak edit item / tidak BATAL DO Pusat', () {
      final cabang = p('admin_toko', 'CABANG-A');
      expect(
        StockMoveReportRules.canEditMoveLineItems(
          profile: cabang,
          dari: 'PUSAT',
          status: 'PREPARING',
        ),
        isFalse,
      );
      expect(
        StockMoveReportRules.canCancelFromReport(
          profile: cabang,
          dari: 'PUSAT',
          status: 'PREPARING',
        ),
        isFalse,
      );
      expect(
        StockMoveReportRules.canReceiverRestPatchMove(cabang),
        isFalse,
      );
    });

    test('gudang asal boleh ubah item saat PREPARING', () {
      expect(
        StockMoveReportRules.canEditMoveLineItems(
          profile: p('admin_pusat', 'PUSAT'),
          dari: 'PUSAT',
          status: 'PREPARING',
        ),
        isTrue,
      );
      expect(
        StockMoveReportRules.canEditMoveLineItems(
          profile: p('admin_pusat', 'PUSAT'),
          dari: 'PUSAT',
          status: 'TRANSIT',
        ),
        isFalse,
      );
    });

    test('kurir hanya status terbuka; terima hanya tujuan', () {
      expect(StockMoveReportRules.canAssignKurir('TRANSIT'), isTrue);
      expect(StockMoveReportRules.canAssignKurir('SUCCESS'), isFalse);
      expect(
        StockMoveReportRules.canReceiveFromReport(
          profile: p('admin_toko', 'CABANG-A'),
          ke: 'CABANG-A',
          status: 'TRANSIT',
        ),
        isTrue,
      );
      expect(
        StockMoveReportRules.canReceiveFromReport(
          profile: p('admin_toko', 'CABANG-A'),
          ke: 'CABANG-B',
          status: 'TRANSIT',
        ),
        isFalse,
      );
      expect(
        StockMoveReportRules.canReceiveFromReport(
          profile: p('admin_toko', 'CABANG-A'),
          ke: 'CABANG-A',
          status: 'PREPARING',
        ),
        isFalse,
      );
    });
  });
}
