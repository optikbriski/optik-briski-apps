import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/attendance_admin_scope.dart';
import 'package:optik_b_riski/shared/invoice/invoice_lifecycle_rules.dart';

void main() {
  Map<String, dynamic> sale({
    String pay = 'DP',
    int sisa = 100000,
    int dibayar = 50000,
    int total = 150000,
    String track = 'PENDING_PO',
    String? diambilAt,
  }) =>
      {
        'status_pembayaran': pay,
        'sisa_tagihan': sisa,
        'dibayarkan': dibayar,
        'total_harga': total,
        'tracking_status': track,
        'diambil_at': diambilAt,
      };

  group('board bucket', () {
    test('DP if pay DP or sisa > 0', () {
      expect(InvoiceLifecycleRules.isDp(sale()), isTrue);
      expect(
        InvoiceLifecycleRules.isDp(sale(pay: 'LUNAS', sisa: 1)),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.isDp(sale(pay: 'LUNAS', sisa: 0)),
        isFalse,
      );
    });

    test('READY is lunas + SIAP_DIAMBIL, not DP', () {
      expect(
        InvoiceLifecycleRules.isReady(
          sale(pay: 'LUNAS', sisa: 0, track: 'SIAP_DIAMBIL'),
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.isReady(
          sale(pay: 'DP', sisa: 1, track: 'SIAP_DIAMBIL'),
        ),
        isFalse,
      );
      expect(
        InvoiceLifecycleRules.isReady(
          sale(pay: 'LUNAS', sisa: 0, track: 'CLEAR'),
        ),
        isTrue,
      );
    });

    test('CLEAR is DIAMBIL / diambil_at', () {
      expect(
        InvoiceLifecycleRules.isClear(sale(track: 'DIAMBIL', sisa: 0, pay: 'LUNAS')),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.isClear(
          sale(pay: 'LUNAS', sisa: 0, track: 'SIAP_DIAMBIL', diambilAt: 'x'),
        ),
        isTrue,
      );
    });

    test('PENDING is lunas belum ready', () {
      expect(
        InvoiceLifecycleRules.isPending(
          sale(pay: 'LUNAS', sisa: 0, track: 'PENDING_PO'),
        ),
        isTrue,
      );
    });
  });

  group('pelunasan dari baris', () {
    test('pakai sisa_tagihan jika > 0', () {
      expect(InvoiceLifecycleRules.remainingFromRow(sale(sisa: 80000)), 80000);
    });

    test('uang JSON 150000.0 dan 7.0 tidak jadi 0', () {
      expect(InvoiceLifecycleRules.moneyOf(150000.0), 150000);
      expect(InvoiceLifecycleRules.moneyOf('150.000'), 150000);
      expect(
        InvoiceLifecycleRules.remainingFromRow({
          'sisa_tagihan': 50000.0,
          'dibayarkan': 100000.0,
          'total_harga': 150000.0,
        }),
        50000,
      );
      expect(
        InvoiceLifecycleRules.isDp({
          'status_pembayaran': 'LUNAS',
          'sisa_tagihan': 1.0,
        }),
        isTrue,
      );
    });

    test('PUSAT = CABANG-PUSAT', () {
      expect(InvoiceLifecycleRules.sameStore('PUSAT', 'CABANG-PUSAT'), isTrue);
      expect(InvoiceLifecycleRules.isPusatToko('CABANG-PUSAT'), isTrue);
      expect(InvoiceLifecycleRules.sameStore('PUSAT', 'CABANG-A'), isFalse);
    });

    test('fallback total - dibayar, tidak negatif', () {
      expect(
        InvoiceLifecycleRules.remainingFromRow(
          sale(sisa: 0, total: 100, dibayar: 40),
        ),
        60,
      );
      expect(
        InvoiceLifecycleRules.remainingFromRow(
          sale(sisa: 0, total: 100, dibayar: 140),
        ),
        0,
      );
    });
  });

  group('line machine', () {
    test('PENDING_RO to READY to DIAMBIL', () {
      expect(
        InvoiceLifecycleRules.lineTransitionOk('PENDING_RO', 'READY'),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.lineTransitionOk('READY', 'DIAMBIL'),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.lineTransitionOk('PENDING_RO', 'DIAMBIL'),
        isFalse,
      );
    });

    test('cannot un-DIAMBIL to RO; READY rollback OK', () {
      expect(
        InvoiceLifecycleRules.lineTransitionOk('DIAMBIL', 'PENDING_RO'),
        isFalse,
      );
      expect(
        InvoiceLifecycleRules.lineTransitionOk('DIAMBIL', 'READY'),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.lineTransitionOk('READY', 'PENDING_RO'),
        isTrue,
      );
    });
  });

  group('tracking machine', () {
    test('DP hanya PENDING_PO <-> SIAP_PELUNASAN', () {
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'SIAP_PELUNASAN',
          wasDp: true,
          nowDp: true,
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'SIAP_DIAMBIL',
          wasDp: true,
          nowDp: true,
        ),
        isFalse,
      );
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'DIAMBIL',
          wasDp: true,
          nowDp: true,
        ),
        isFalse,
      );
    });

    test('pelunasan setelah ready → SIAP_DIAMBIL', () {
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'SIAP_PELUNASAN',
          to: 'SIAP_DIAMBIL',
          wasDp: true,
          nowDp: false,
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'PENDING_PO',
          wasDp: true,
          nowDp: false,
        ),
        isTrue,
      );
    });

    test('lunas tidak boleh lompat PENDING → DIAMBIL', () {
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'DIAMBIL',
          wasDp: false,
          nowDp: false,
        ),
        isFalse,
      );
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'PENDING_PO',
          to: 'SIAP_DIAMBIL',
          wasDp: false,
          nowDp: false,
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.trackingTransitionOk(
          from: 'SIAP_DIAMBIL',
          to: 'DIAMBIL',
          wasDp: false,
          nowDp: false,
        ),
        isTrue,
      );
    });

    test('LUNAS tidak boleh dibuka jadi DP', () {
      expect(
        InvoiceLifecycleRules.paymentTransitionOk('LUNAS', 'DP'),
        isFalse,
      );
      expect(
        InvoiceLifecycleRules.paymentTransitionOk('DP', 'LUNAS'),
        isTrue,
      );
    });
  });

  group('QR phase', () {
    test('DP QR only at SIAP_PELUNASAN', () {
      expect(
        InvoiceLifecycleRules.qrPhaseOk(
          phase: 'DP',
          isDp: true,
          tracking: 'SIAP_PELUNASAN',
          diambil: false,
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.qrPhaseOk(
          phase: 'DP',
          isDp: true,
          tracking: 'PENDING_PO',
          diambil: false,
        ),
        isFalse,
      );
    });

    test('LUNAS QR only when lunas + ready', () {
      expect(
        InvoiceLifecycleRules.qrPhaseOk(
          phase: 'LUNAS',
          isDp: false,
          tracking: 'SIAP_DIAMBIL',
          diambil: false,
        ),
        isTrue,
      );
      expect(
        InvoiceLifecycleRules.qrPhaseOk(
          phase: 'LUNAS',
          isDp: true,
          tracking: 'SIAP_DIAMBIL',
          diambil: false,
        ),
        isFalse,
      );
    });
  });

  group('siapa yang boleh buka board', () {
    Map<String, dynamic> p(String role, String toko) => {
          'role': role,
          'toko_id': toko,
        };

    test('owner etalase tidak jual / tidak board kasir', () {
      expect(AttendanceAdminScope.canOpenPos(p('owner', 'PUSAT')), isFalse);
      expect(
        AttendanceAdminScope.canPosCheckoutToko(p('owner', 'PUSAT'), 'PUSAT'),
        isFalse,
      );
    });

    test('admin_toko PUSAT bukan operator semua cabang', () {
      expect(
        AttendanceAdminScope.canViewAllStores(p('admin_toko', 'PUSAT')),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canPosCheckoutToko(
          p('admin_toko', 'PUSAT'),
          'CABANG-X',
        ),
        isFalse,
      );
      expect(
        AttendanceAdminScope.canPosCheckoutToko(p('admin_toko', 'PUSAT'), 'PUSAT'),
        isTrue,
      );
    });

    test('kasir hanya toko sendiri', () {
      expect(
        AttendanceAdminScope.canPosCheckoutToko(p('kasir', 'CABANG-A'), 'CABANG-A'),
        isTrue,
      );
      expect(
        AttendanceAdminScope.canPosCheckoutToko(p('kasir', 'CABANG-A'), 'CABANG-B'),
        isFalse,
      );
    });
  });
}
