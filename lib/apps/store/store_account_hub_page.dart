import 'package:flutter/material.dart';

import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import 'store_account.dart';
import 'store_account_login_page.dart';
import 'store_brand_dashboard_page.dart';
import 'store_contract_token_page.dart';

/// Portal owner: masuk / dasbor / kontrak. Bantuan ada di tab bawah.
class StoreAccountHubPage extends StatelessWidget {
  const StoreAccountHubPage({
    super.key,
    this.kind = StoreAccountKind.none,
    this.embedded = false,
  });

  final StoreAccountKind kind;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      children: [
        RekasaPage(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!embedded) ...[
                const RekasaMark(height: 30),
                const SizedBox(height: 18),
              ],
              const RekasaEyebrow('Portal usaha'),
              const SizedBox(height: 16),
              Text(
                'Akun owner',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Yang sudah beli masuk ke dasbor merek sendiri: tagihan, '
                'kontrak, paket. Kasir tetap di APK Admin/Karyawan.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 22),
              _tile(
                context,
                icon: Icons.storefront_rounded,
                title: kind == StoreAccountKind.owner
                    ? 'Dasbor merek saya'
                    : 'Owner usaha',
                body: kind == StoreAccountKind.owner
                    ? 'Buka pembayaran, kontrak, dan paket usaha Anda.'
                    : 'Sudah beli: masuk atau daftar, klaim kode usaha + HP.',
                onTap: () {
                  if (kind == StoreAccountKind.owner) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StoreBrandDashboardPage(),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StoreAccountLoginPage(),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _tile(
                context,
                icon: Icons.draw_rounded,
                title: 'Tanda tangan kontrak',
                body: 'Punya tautan / kode kontrak dari Rekasa.',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StoreContractTokenPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
    if (embedded) return body;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(title: const Text('Akun')),
      body: body,
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return RekasaSurface(
      onTap: onTap,
      child: Row(
        children: [
          RekasaIconTile(icon: icon, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: RekasaTokens.inkSoft),
        ],
      ),
    );
  }
}
