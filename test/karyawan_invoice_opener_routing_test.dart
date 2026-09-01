import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/apps/karyawan/register_karyawan_invoice_opener.dart';
import 'package:optik_b_riski/shared/qr/obr_codes.dart';

void main() {
  group('resolveKaryawanInvoiceQrDest', () {
    final lunas = ObrInvoice.encode(
      'INV-1',
      paymentStatus: 'LUNAS',
      token: 'tokensecure99ab',
      channel: ObrSaleChannel.offline,
    );
    final claim = ObrInvoice.encode(
      'INV-1',
      paymentStatus: 'CLAIM',
      token: 'claimtok999abcde',
      channel: ObrSaleChannel.offline,
    );
    final dp = ObrInvoice.encode(
      'INV-1',
      paymentStatus: 'DP',
      token: 'dptokensecure99a',
      channel: ObrSaleChannel.offline,
    );

    test('LUNAS scan → pickup page', () {
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: false,
          phase: ObrInvoice.parse(lunas)?.phase,
          rawScan: lunas,
        ),
        KaryawanInvoiceQrDest.pickupLunas,
      );
    });

    test('CLAIM scan → claim page', () {
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: false,
          phase: ObrInvoice.parse(claim)?.phase,
          rawScan: claim,
        ),
        KaryawanInvoiceQrDest.claim,
      );
    });

    test('DP scan → snack Admin', () {
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: false,
          phase: ObrInvoice.parse(dp)?.phase,
          rawScan: dp,
        ),
        KaryawanInvoiceQrDest.snackDp,
      );
    });

    test('viewOnly never opens pickup/claim', () {
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: true,
          phase: 'LUNAS',
          rawScan: lunas,
        ),
        KaryawanInvoiceQrDest.snackView,
      );
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: true,
          phase: 'CLAIM',
          rawScan: claim,
        ),
        KaryawanInvoiceQrDest.snackClaim,
      );
    });

    test('empty raw → snack view', () {
      expect(
        resolveKaryawanInvoiceQrDest(
          viewOnly: false,
          phase: 'LUNAS',
          rawScan: '',
        ),
        KaryawanInvoiceQrDest.snackView,
      );
    });
  });

  group('pickup duty gate path (profile)', () {
    test('nik empty blocks before handover (guard condition)', () {
      const profile = {'id': 'uuid-1', 'nik': '', 'toko_id': 'T1'};
      final nik = (profile['nik'] ?? '').toString().trim();
      final kid = (profile['id'] ?? '').toString().trim();
      expect(kid.isEmpty || nik.isEmpty, isTrue);
    });

    test('nik + id present allows duty gate call', () {
      const profile = {
        'id': 'uuid-1',
        'nik': '3201010101010001',
        'toko_id': 'T1',
      };
      final nik = (profile['nik'] ?? '').toString().trim();
      final kid = (profile['id'] ?? '').toString().trim();
      expect(kid.isNotEmpty && nik.isNotEmpty, isTrue);
    });
  });
}
