import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/qr/qr_route.dart';
import 'package:optik_b_riski/shared/qr/qr_scan_rules.dart';

void main() {
  group('attendance toko aliases', () {
    test('PUSAT = CABANG-PUSAT', () {
      expect(QrScanRules.sameStore('PUSAT', 'CABANG-PUSAT'), isTrue);
      expect(QrScanRules.sameStore('CABANG-PUSAT', 'PUSAT'), isTrue);
      expect(
        QrScanRules.attendanceTokoAliases('PUSAT'),
        ['PUSAT', 'CABANG-PUSAT'],
      );
      expect(
        QrScanRules.attendanceTokoAliases('CABANG-PUSAT'),
        ['PUSAT', 'CABANG-PUSAT'],
      );
      expect(
        QrScanRules.attendancePayloadMatchesToko(
          payloadToko: 'CABANG-PUSAT',
          tokenToko: 'PUSAT',
        ),
        isTrue,
      );
      expect(
        QrScanRules.attendancePayloadMatchesToko(
          payloadToko: 'CABANG-A',
          tokenToko: 'CABANG-B',
        ),
        isFalse,
      );
    });

    test('router mengenali OBRATT CABANG-PUSAT', () {
      final r = QrRouter.classify(
        'OBRATT|v1|CABANG-PUSAT|abcdefghijklmnop',
      );
      expect(r.type, QrPayloadType.attendance);
      expect(r.attendanceTokoId, 'CABANG-PUSAT');
      expect(QrScanRules.isAttendancePayload(r.raw), isTrue);
    });
  });

  group('invoice customer QR', () {
    test('fake OBRINV terklasifikasi lifecycle, bukan view-only', () {
      const raw = 'OBRINV|v1|INV-FAKE-000055|DP|tokensecure99|OFFLINE';
      expect(QrScanRules.isCustomerLifecyclePayload(raw), isTrue);
      final r = QrRouter.classify(raw);
      expect(r.type, QrPayloadType.invoice);
      expect(r.invoiceCustomerLifecycle, isTrue);
      expect(r.invoiceViewOnly, isFalse);
      expect(r.invoiceNo, 'INV-FAKE-000055');
    });

    test('QR DP hanya SIAP_PELUNASAN + token cocok', () {
      expect(
        QrScanRules.customerScanReason(
          phase: 'DP',
          isDp: true,
          tracking: 'SIAP_PELUNASAN',
          diambil: false,
          tokenUsed: false,
          tokenMatch: true,
        ),
        isNull,
      );
      expect(
        QrScanRules.customerScanReason(
          phase: 'DP',
          isDp: true,
          tracking: 'PENDING_PO',
          diambil: false,
          tokenUsed: false,
          tokenMatch: true,
        ),
        'qr_dp_belum_ready',
      );
      expect(
        QrScanRules.customerScanReason(
          phase: 'DP',
          isDp: false,
          tracking: 'SIAP_PELUNASAN',
          diambil: false,
          tokenUsed: false,
          tokenMatch: true,
        ),
        'qr_dp_sudah_lunas',
      );
      expect(
        QrScanRules.customerScanReason(
          phase: 'DP',
          isDp: true,
          tracking: 'SIAP_PELUNASAN',
          diambil: false,
          tokenUsed: false,
          tokenMatch: false,
        ),
        'token_tidak_cocok',
      );
    });

    test('QR LUNAS wajib item READY', () {
      expect(
        QrScanRules.customerScanReason(
          phase: 'LUNAS',
          isDp: false,
          tracking: 'SIAP_DIAMBIL',
          diambil: false,
          tokenUsed: false,
          tokenMatch: true,
          readyCount: 1,
        ),
        isNull,
      );
      expect(
        QrScanRules.customerScanReason(
          phase: 'LUNAS',
          isDp: false,
          tracking: 'SIAP_DIAMBIL',
          diambil: false,
          tokenUsed: false,
          tokenMatch: true,
        ),
        'qr_lunas_belum_ada_ready',
      );
    });
  });

  group('staff NIK', () {
    test('NIK harus toko nota; PUSAT = CABANG-PUSAT', () {
      expect(
        QrScanRules.staffNikSameStore(staffToko: 'PUSAT', notaToko: 'CABANG-PUSAT'),
        isTrue,
      );
      expect(
        QrScanRules.staffNikSameStore(staffToko: 'CABANG-A', notaToko: 'CABANG-B'),
        isFalse,
      );
      expect(
        QrScanRules.staffNikSameStore(staffToko: 'CABANG-A', notaToko: ''),
        isTrue,
      );
    });
  });
}
