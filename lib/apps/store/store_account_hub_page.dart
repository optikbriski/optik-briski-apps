import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import 'store_account.dart';
import 'store_account_login_page.dart';
import 'store_brand_dashboard_page.dart';
import 'store_contract_token_page.dart';
import 'store_help_page.dart';

/// Pilihan di bawah etalase: akun owner, kontrak, operator, bantuan.
class StoreAccountHubPage extends StatelessWidget {
  const StoreAccountHubPage({super.key, this.kind = StoreAccountKind.none});

  final StoreAccountKind kind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        children: [
          RekasaPage(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RekasaMark(height: 30),
                const SizedBox(height: 18),
                const RekasaEyebrow('Portal usaha'),
                const SizedBox(height: 8),
                Text(
                  'Pilih cara masuk',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
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
                _tile(
                  context,
                  icon: Icons.support_agent_rounded,
                  title: 'Bantuan',
                  body: 'Cara beli, APK yang di-install, dan hubungi Rekasa.',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StoreHelpPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RekasaSurface(
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
            const Icon(Icons.arrow_forward_rounded, color: RekasaTokens.ink),
          ],
        ),
      ),
    );
  }
}

class StoreServiceStrip extends StatefulWidget {
  const StoreServiceStrip({super.key, this.kind = StoreAccountKind.none});

  final StoreAccountKind kind;

  @override
  State<StoreServiceStrip> createState() => _StoreServiceStripState();
}

class _StoreServiceStripState extends State<StoreServiceStrip> {
  late StoreAccountKind _kind = widget.kind;

  @override
  void initState() {
    super.initState();
    _refreshKind();
  }

  @override
  void didUpdateWidget(covariant StoreServiceStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _kind = widget.kind;
  }

  Future<void> _refreshKind() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await supabase.from('profiles').select().eq('id', uid).maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _kind = StoreAuth.kind(Map<String, dynamic>.from(row)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final items = [
      (
        Icons.person_rounded,
        'Akun',
        kind == StoreAccountKind.owner ? 'Dasbor merek' : 'Masuk owner',
        () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StoreAccountHubPage(kind: kind),
            ),
          );
          await _refreshKind();
        },
      ),
      (
        Icons.draw_rounded,
        'Kontrak',
        'Tanda tangan',
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StoreContractTokenPage()),
          );
        },
      ),
      (
        Icons.help_outline_rounded,
        'Bantuan',
        'Cara pakai',
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StoreHelpPage()),
          );
        },
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const RekasaEyebrow('Layanan'),
        const SizedBox(height: 16),
        Text(
          'Sudah beli? Kelola merek di sini.',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            color: RekasaTokens.ink,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 720;
            if (!wide) {
              return Column(
                children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _card(i.$1, i.$2, i.$3, i.$4),
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _card(items[i].$1, items[i].$2, items[i].$3, items[i].$4)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card(IconData icon, String title, String body, VoidCallback onTap) {
    return RekasaSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RekasaIconTile(icon: icon, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: RekasaTokens.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.plusJakartaSans(
              color: RekasaTokens.muted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
