import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/tenant/tenant_billing.dart';
import 'package:optik_b_riski/shared/tenant/tenant_service.dart';

void main() {
  test('formatRp groups thousands', () {
    expect(TenantBilling.formatRp(750000), 'Rp 750.000');
    expect(TenantBilling.formatRp(0), 'Rp 0');
  });

  test('tokenFromUri reads query and path', () {
    expect(
      TenantBilling.tokenFromUri(Uri.parse('https://x.id/?kontrak=abc123')),
      'abc123',
    );
    expect(
      TenantBilling.tokenFromUri(Uri.parse('https://x.id/kontrak/tok_99')),
      'tok_99',
    );
    expect(TenantBilling.tokenFromUri(Uri.parse('https://x.id/')), isNull);
  });

  test('publicSignUrl keeps token on kontrak query', () {
    expect(
      TenantBilling.publicSignUrl('deadbeef', origin: 'https://admin.example'),
      'https://admin.example/?kontrak=deadbeef',
    );
  });

  test('access snapshot maps suspend lock copy', () {
    final snap = TenantAccessSnapshot.fromRpc({
      'ok': false,
      'reason': 'suspend',
      'status': 'suspend',
      'error': 'Langganan ditangguhkan. Tagihan belum dibayar.',
      'display_name': 'Optik Maju',
      'invoices': [
        {'invoice_no': 'RK-INV-202608-0001', 'amount_idr': 250000},
      ],
    });
    expect(snap.ok, isFalse);
    expect(snap.isSuspended, isTrue);
    expect(snap.lockTitle, 'Langganan ditangguhkan');
    expect(snap.invoices, hasLength(1));
    expect(snap.lockBody, contains('ditangguhkan'));
  });

  test('missing RPC payload stays unlocked', () {
    final snap = TenantAccessSnapshot.fromRpc(null);
    expect(snap.ok, isTrue);
  });

  test('suspend copy is explicit about billing lock', () {
    expect(TenantService.suspendedMessage, contains('Tagihan belum dibayar'));
    expect(TenantService.suspendedMessage, contains('tidak dihapus'));
  });
}
