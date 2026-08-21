import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/bootstrap.dart';
import '../../shared/brand/rekasa_tokens.dart';
import '../../shared/tenant/tenant_billing.dart';
import '../../shared/widgets/rekasa_mark.dart';
import '../../shared/widgets/rekasa_surface.dart';
import '../../shared/widgets/tenant_contract_sign_page.dart';
import 'store_account.dart';

/// Dasbor merek owner di etalase: tagihan Rekasa + kontrak. Bukan POS.
class StoreBrandDashboardPage extends StatefulWidget {
  const StoreBrandDashboardPage({super.key});

  @override
  State<StoreBrandDashboardPage> createState() => _StoreBrandDashboardPageState();
}

class _StoreBrandDashboardPageState extends State<StoreBrandDashboardPage> {
  StoreAccountSnapshot? _account;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final snap = await StoreAccount.load();
    if (!mounted) return;
    if (snap.platform) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _account = snap;
      _error = snap.ok ? null : (snap.error ?? 'Tidak bisa memuat akun');
      _loading = false;
    });
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(
        title: Text(a?.brandLabel ?? 'Dasbor merek'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _boot,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(onPressed: _logout, child: const Text('Keluar')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: RekasaTokens.ink))
          : ListView(
              children: [
                RekasaPage(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RekasaMark(height: 28),
                      const SizedBox(height: 16),
                      const RekasaEyebrow('Dasbor owner'),
                      const SizedBox(height: 8),
                      Text(
                        a?.brandLabel ?? 'Usaha Anda',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if ((a?.slug ?? '').trim().isNotEmpty) 'Kode ${a!.slug}',
                          if (a != null) a.planLabel,
                          if (a != null) a.industryLabel,
                          if (a?.whiteLabel == true) 'Merek sendiri',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      if (a != null) _statusChip(a),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: const TextStyle(color: RekasaTokens.danger)),
                      ],
                      const SizedBox(height: 22),
                      _sectionTitle('Kebutuhan owner'),
                      const SizedBox(height: 8),
                      const Text(
                        'Pembayaran langganan ke Rekasa, kontrak, dan paket. '
                        'Kasir / stok / absensi tetap di APK Admin atau Karyawan.',
                      ),
                      const SizedBox(height: 18),
                      _invoices(a),
                      const SizedBox(height: 16),
                      _contracts(a),
                      const SizedBox(height: 16),
                      _modules(a),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusChip(StoreAccountSnapshot a) {
    final suspend = (a.status ?? '') == 'suspend';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: suspend ? RekasaTokens.warning.withOpacity(0.16) : RekasaTokens.wash,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        a.statusLabel,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w800,
          color: suspend ? RekasaTokens.warning : RekasaTokens.ink,
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w800,
        fontSize: 18,
        color: RekasaTokens.ink,
      ),
    );
  }

  Widget _invoices(StoreAccountSnapshot? a) {
    final list = a?.invoices ?? const [];
    return RekasaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Pembayaran'),
          const SizedBox(height: 6),
          const Text(
            'Tagihan Rekasa ke usaha Anda. Transfer ke Rekasa; '
            'operator menandai lunas. Bukan nota kasir.',
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Text('Belum ada tagihan.')
          else
            for (final i in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i['invoice_no'] ?? 'Tagihan'} · ${i['period'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            TenantBilling.formatRp(i['amount_idr']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${i['status'] ?? ''}',
                      style: const TextStyle(color: RekasaTokens.muted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _contracts(StoreAccountSnapshot? a) {
    final list = a?.contracts ?? const [];
    final token = (a?.unsignedContractToken ?? '').trim();
    return RekasaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Kontrak'),
          const SizedBox(height: 6),
          const Text('Perjanjian langganan online. Klik-setuju + ketik nama.'),
          const SizedBox(height: 12),
          if (token.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TenantContractSignPage(token: token),
                    ),
                  );
                  await _boot();
                },
                child: const Text('Tandatangani yang menunggu'),
              ),
            ),
          if (list.isEmpty)
            const Text('Belum ada kontrak.')
          else
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${c['contract_no'] ?? ''} · ${c['title'] ?? 'Kontrak'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${c['status'] ?? ''}',
                      style: const TextStyle(color: RekasaTokens.muted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _modules(StoreAccountSnapshot? a) {
    final chips = a?.enabledModuleLabels ?? const <String>[];
    return RekasaSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Paket & fitur'),
          const SizedBox(height: 6),
          Text(a == null ? '—' : '${a.planLabel} · ${a.industryLabel}'),
          const SizedBox(height: 10),
          if (chips.isEmpty)
            const Text('Fitur muncul setelah SQL 000011/000012 dan paket aktif.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: RekasaTokens.wash,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: RekasaTokens.ink,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
