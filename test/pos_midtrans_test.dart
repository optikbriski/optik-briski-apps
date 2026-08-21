import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/pos/pos_midtrans.dart';

void main() {
  test('POS uses Midtrans for QRIS/Transfer/Debit, not cash', () {
    expect(PosMidtrans.usesGateway('Tunai'), isFalse);
    expect(PosMidtrans.usesGateway('QRIS'), isTrue);
    expect(PosMidtrans.usesGateway('Transfer'), isTrue);
    expect(PosMidtrans.usesGateway('Debit'), isTrue);
    expect(PosMidtrans.usesGateway('midtrans'), isTrue);
  });

  test('Midtrans payment types map back to POS labels', () {
    expect(PosMidtrans.labelForType('qris'), 'QRIS');
    expect(PosMidtrans.labelForType('bank_transfer'), 'Transfer');
    expect(PosMidtrans.labelForType('credit_card'), 'Debit');
  });
}
