import 'package:flutter/material.dart';

import '../bootstrap.dart';
import '../tenant/tenant_billing.dart';
import '../theme.dart';
import 'tenant_contract_sign_page.dart';

/// Layar kunci UMKM: tagihan jatuh tempo / kontrak belum ditandatangani.
/// Data tidak dihapus. Rekasa menandai lunas → status aktif lagi.
class TenantSuspendedPage extends StatelessWidget {
  const TenantSuspendedPage({
    super.key,
    required this.access,
    this.onSignOut,
    this.onOpenContract,
  });

  final TenantAccessSnapshot access;
  final VoidCallback? onSignOut;
  final VoidCallback? onOpenContract;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OptikAdminTokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
          children: [
            Icon(
              Icons.lock_clock_rounded,
              size: 52,
              color: OptikAdminTokens.danger.withOpacity(0.9),
            ),
            const SizedBox(height: 16),
            Text(
              access.lockTitle,
              style: const TextStyle(
                color: OptikAdminTokens.navy,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            if ((access.displayName ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                access.displayName!,
                style: const TextStyle(
                  color: OptikAdminTokens.slate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              access.lockBody,
              style: TextStyle(
                color: OptikAdminTokens.navy.withOpacity(0.78),
                height: 1.4,
                fontSize: 15,
              ),
            ),
            if (access.invoices.isNotEmpty) ...[
              const SizedBox(height: 22),
              const Text(
                'Tagihan terbuka',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: OptikAdminTokens.navy,
                ),
              ),
              const SizedBox(height: 8),
              for (final i in access.invoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: OptikAdminTokens.danger.withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i['invoice_no'] ?? '-'} · ${i['period'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${TenantBilling.formatRp(i['amount_idr'])} · ${i['status']}',
                          style: const TextStyle(color: OptikAdminTokens.slate),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            if ((access.unsignedContractToken ?? '').isNotEmpty)
              FilledButton.icon(
                onPressed: onOpenContract ??
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TenantContractSignPage(
                            token: access.unsignedContractToken!,
                          ),
                        ),
                      );
                    },
                icon: const Icon(Icons.draw_rounded),
                label: const Text('Buka kontrak online'),
              ),
            const SizedBox(height: 10),
            if (onSignOut != null)
              OutlinedButton(
                onPressed: onSignOut,
                child: const Text('Keluar'),
              ),
            const SizedBox(height: 18),
            Text(
              'Transfer / konfirmasi ke Rekasa Karya Indonesia. '
              'Setelah lunas, sistem menyala lagi — nota dan stok tetap ada.',
              style: TextStyle(
                color: OptikAdminTokens.slate.withOpacity(0.9),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> signOutQuiet() async {
  try {
    await supabase.auth.signOut();
  } catch (_) {}
}
