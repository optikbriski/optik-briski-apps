import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/invoice/invoice_hub_service.dart';

void main() {
  group('InvoiceHubService.statusLabel', () {
    test('DP + SIAP_DIAMBIL prioritizes masih DP (Beranda parity)', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'SIAP_DIAMBIL',
        'sisa_tagihan': 150000,
        'status_pembayaran': 'DP',
      });
      expect(label, 'Siap diambil · masih DP');
    });

    test('DP + PENDING_PO shows DP waiting label', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'PENDING_PO',
        'sisa_tagihan': 1,
        'status_pembayaran': 'DP',
      });
      expect(label, 'DP · menunggu barang ready');
    });

    test('lunas SIAP_DIAMBIL is plain siap diambil', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'SIAP_DIAMBIL',
        'sisa_tagihan': 0,
        'status_pembayaran': 'LUNAS',
      });
      expect(label, 'Siap diambil');
    });

    test('raw BATAL_VOUCHER is humanized', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'BATAL_VOUCHER',
        'sisa_tagihan': 0,
      });
      expect(label, 'Dibatalkan');
    });

    test('unknown SCREAMING_SNAKE is title-cased not raw key', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'FOO_BAR_BAZ',
      });
      expect(label, 'Foo Bar Baz');
      expect(label.contains('_'), isFalse);
    });

    test('isDpOpen true when status DP even if sisa 0', () {
      expect(
        InvoiceHubService.isDpOpen({
          'status_pembayaran': 'DP',
          'sisa_tagihan': 0,
        }),
        isTrue,
      );
      expect(
        InvoiceHubService.isDpOpen({
          'status_pembayaran': 'LUNAS',
          'sisa_tagihan': 150000.0,
        }),
        isTrue,
      );
    });

    test('DP + CLEAR matches Beranda siap-ambil-masih-DP', () {
      final label = InvoiceHubService.statusLabel({
        'tracking_status': 'CLEAR',
        'sisa_tagihan': 50000,
        'status_pembayaran': 'DP',
      });
      expect(label, 'Siap diambil · masih DP');
    });

    test('DIAMBIL without garansi flag is Sudah diambil (list RPC)', () {
      expect(
        InvoiceHubService.statusLabel({
          'tracking_status': 'DIAMBIL',
          'diambil_at': '2026-08-01T10:00:00Z',
        }),
        'Sudah diambil',
      );
    });

    test('DIAMBIL with garansi_claimable true/false', () {
      expect(
        InvoiceHubService.statusLabel({
          'tracking_status': 'DIAMBIL',
          'diambil_at': '2026-08-01T10:00:00Z',
          'garansi_claimable': true,
        }),
        'CLEAR · Garansi aktif',
      );
      expect(
        InvoiceHubService.statusLabel({
          'tracking_status': 'DIAMBIL',
          'diambil_at': '2026-08-01T10:00:00Z',
          'garansi_claimable': false,
        }),
        'CLEAR · Garansi mati',
      );
    });

    test('status_pembayaran BATAL alone is Dibatalkan', () {
      expect(
        InvoiceHubService.statusLabel({
          'tracking_status': 'DIPROSES',
          'status_pembayaran': 'BATAL',
        }),
        'Dibatalkan',
      );
    });
  });
}
