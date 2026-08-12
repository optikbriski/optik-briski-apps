import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/qr/qr_route.dart';
import 'package:optik_b_riski/shared/qr/universal_qr_nav.dart';

void main() {
  group('QrRouter.classify', () {
    test('empty / whitespace → unknown', () {
      expect(QrRouter.classify(null).type, QrPayloadType.unknown);
      expect(QrRouter.classify('').type, QrPayloadType.unknown);
      expect(QrRouter.classify('   ').type, QrPayloadType.unknown);
    });

    test('malformed OBR junk → unknown (no crash)', () {
      expect(QrRouter.classify('OBRINV|broken').type, QrPayloadType.unknown);
      expect(QrRouter.classify('OBRPROD|v1|').type, QrPayloadType.unknown);
      expect(QrRouter.classify('{not-json').type, QrPayloadType.unknown);
      expect(QrRouter.classify('OBRATT|v1|TOKO|short').type, QrPayloadType.unknown);
    });

    test('attendance OBRATT', () {
      final r = QrRouter.classify(
        'OBRATT|v1|PUSAT|abcdefghijklmnop',
      );
      expect(r.type, QrPayloadType.attendance);
      expect(r.attendanceTokoId, 'PUSAT');
      expect(r.attendanceToken, 'abcdefghijklmnop');
    });

    test('product OBRPROD', () {
      final r = QrRouter.classify('OBRPROD|v1|SKU-001|pid-9');
      expect(r.type, QrPayloadType.product);
      expect(r.productSku, 'SKU-001');
      expect(r.productId, 'pid-9');
    });

    test('invoice OBRTXN view-only + channel', () {
      final r = QrRouter.classify('OBRTXN|v1|INV-ABC|ONLINE');
      expect(r.type, QrPayloadType.invoice);
      expect(r.invoiceNo, 'INV-ABC');
      expect(r.invoiceViewOnly, isTrue);
      expect(r.invoiceCustomerLifecycle, isFalse);
      expect(r.invoiceChannel, 'online');
    });

    test('invoice OBRINV customer lifecycle', () {
      final r = QrRouter.classify(
        'OBRINV|v1|INV-XYZ|LUNAS|tokensecure99|OFFLINE',
      );
      expect(r.type, QrPayloadType.invoice);
      expect(r.invoiceNo, 'INV-XYZ');
      expect(r.invoiceCustomerLifecycle, isTrue);
      expect(r.invoicePaymentStatus, 'LUNAS');
      expect(r.invoiceChannel, 'offline');
    });

    test('https invoice link', () {
      final r = QrRouter.classify(
        'https://optik-briski-apps.vercel.app/i/INV-HTTPS1',
      );
      expect(r.type, QrPayloadType.invoice);
      expect(r.invoiceNo, 'INV-HTTPS1');
      expect(r.invoiceViewOnly, isTrue);
    });

    test('plain INV- / ON- invoice numbers', () {
      expect(QrRouter.classify('INV-CIMAHI-01').type, QrPayloadType.invoice);
      expect(QrRouter.classify('ON-2024-99').invoiceNo, 'ON-2024-99');
    });

    test('receive stock DO/RO', () {
      final r = QrRouter.classify('OBRDO|v1|DO-1|CIMAHI');
      expect(r.type, QrPayloadType.receiveStock);
      expect(r.receiveResi, 'DO-1');
      expect(r.receiveTujuan, 'CIMAHI');
    });

    test('customer + karyawan payloads', () {
      final c = QrRouter.classify('OBRCUS|v1|Budi|62811|a@b.c');
      expect(c.type, QrPayloadType.customer);
      expect(c.customerNama, 'Budi');

      final k = QrRouter.classify('OBRKARY|v1|NIK1|Ani|PUSAT');
      expect(k.type, QrPayloadType.karyawan);
      expect(k.karyawanId, 'NIK1');
    });
  });

  group('UniversalQrNav.wouldNavigate', () {
    test('staff invoice navigates; member product navigates', () {
      final inv = QrRouter.classify('OBRTXN|v1|INV-1|OFFLINE');
      expect(
        UniversalQrNav.wouldNavigate(
          inv,
          callerRole: UniversalQrCallerRole.admin,
        ),
        isTrue,
      );

      final prod = QrRouter.classify('OBRPROD|v1|SKU-X');
      expect(
        UniversalQrNav.wouldNavigate(
          prod,
          callerRole: UniversalQrCallerRole.member,
        ),
        isTrue,
      );
      expect(
        UniversalQrNav.wouldNavigate(
          prod,
          callerRole: UniversalQrCallerRole.admin,
        ),
        isFalse,
      );
    });

    test('member attendance / receive do not navigate', () {
      final att = QrRouter.classify('OBRATT|v1|PUSAT|abcdefghijklmnop');
      expect(
        UniversalQrNav.wouldNavigate(
          att,
          callerRole: UniversalQrCallerRole.member,
        ),
        isFalse,
      );
      final recv = QrRouter.classify('OBRDO|v1|DO-1|PUSAT');
      expect(
        UniversalQrNav.wouldNavigate(
          recv,
          callerRole: UniversalQrCallerRole.member,
          cabangKaryawan: 'PUSAT',
        ),
        isFalse,
      );
    });
  });
}
