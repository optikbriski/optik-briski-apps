import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/qr/obr_codes.dart';

void main() {
  test('OBRINV LUNAS and CLAIM phases parse', () {
    final lunas = ObrInvoice.encode(
      'INV-TEST-1',
      paymentStatus: 'LUNAS',
      token: 'abcdef12token99',
      channel: ObrSaleChannel.offline,
    );
    final claim = ObrInvoice.encode(
      'INV-TEST-1',
      paymentStatus: 'CLAIM',
      token: 'claimtok999abcde',
      channel: ObrSaleChannel.offline,
    );
    expect(ObrInvoice.parse(lunas)?.phase, 'LUNAS');
    expect(ObrInvoice.parse(claim)?.phase, 'CLAIM');
    expect(ObrInvoice.parse(lunas)?.noInvoice, 'INV-TEST-1');
    expect(ObrInvoice.parse(claim)?.token, 'claimtok999abcde');
  });
}
