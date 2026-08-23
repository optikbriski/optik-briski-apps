import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/tenant/rekasa_store_midtrans.dart';

void main() {
  test('katalog Midtrans: snap punya redirect, mock tanpa potong stok', () {
    final snap = RekasaStoreMidtransResult.fromMap({
      'ok': true,
      'mock_payment': false,
      'order_id': 'RKS-1',
      'redirect_url': 'https://app.sandbox.midtrans.com/snap/v2/vtweb/abc',
      'snap_token': 'tok',
    });
    expect(snap.ok, isTrue);
    expect(snap.mock, isFalse);
    expect(snap.redirectUrl, contains('midtrans.com'));

    final mock = RekasaStoreMidtransResult.fromMap({
      'ok': true,
      'mock_payment': true,
      'order_id': 'RKS-2',
    });
    expect(mock.ok, isTrue);
    expect(mock.mock, isTrue);
    expect(mock.redirectUrl, isNull);
  });

  test('katalog Midtrans: error edge tidak dianggap lunas', () {
    final bad = RekasaStoreMidtransResult.fromMap({
      'ok': false,
      'error': 'Gagal membuat transaksi Midtrans lisensi',
    });
    expect(bad.ok, isFalse);
    expect(bad.paid, isFalse);
    expect(bad.error, contains('Midtrans'));
  });
}
