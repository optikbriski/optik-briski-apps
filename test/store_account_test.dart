import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/apps/store/store_account.dart';

void main() {
  test('platform profile is not an owner portal session', () {
    expect(
      StoreAuth.kind({'is_platform': true, 'tenant_id': 'x', 'role': 'admin'}),
      StoreAccountKind.platform,
    );
  });

  test('owner with tenant opens brand dashboard', () {
    expect(
      StoreAuth.kind({'role': 'owner', 'tenant_id': 't-1'}),
      StoreAccountKind.owner,
    );
    expect(
      StoreAuth.kind({'role': 'super_admin', 'tenant_id': 't-1'}),
      StoreAccountKind.owner,
    );
  });

  test('kasir is rejected from store owner portal', () {
    expect(
      StoreAuth.kind({'role': 'karyawan', 'tenant_id': 't-1'}),
      StoreAccountKind.staff,
    );
  });

  test('account snapshot reads brand invoices and contracts', () {
    final snap = StoreAccountSnapshot.fromRpc({
      'ok': true,
      'display_name': 'Warung Sari',
      'slug': 'warung-sari',
      'status': 'trial',
      'plan_key': 'paket_b',
      'industry_key': 'fnb',
      'modules': [
        {'module_key': 'pos', 'enabled': true},
        {'module_key': 'finance', 'enabled': false},
      ],
      'invoices': [
        {'invoice_no': 'RK-INV-1', 'amount_idr': 450000, 'status': 'sent'},
      ],
      'contracts': [
        {'contract_no': 'RK-KTR-1', 'status': 'sent'},
      ],
      'unsigned_contract_token': 'abc',
    });
    expect(snap.ok, isTrue);
    expect(snap.brandLabel, 'Warung Sari');
    expect(snap.planLabel, contains('Bisnis'));
    expect(snap.industryLabel.toLowerCase(), contains('kafe'));
    expect(snap.enabledModuleLabels, isNot(contains('Keuangan')));
    expect(snap.invoices, hasLength(1));
    expect(snap.unsignedContractToken, 'abc');
  });

  test('missing account RPC payload is not ok', () {
    final snap = StoreAccountSnapshot.fromRpc(null);
    expect(snap.ok, isFalse);
  });
}
