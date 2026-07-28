import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/invoice/invoice_hub_service.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../../../shared/whatsapp_launcher.dart';
import '../member_widgets.dart';
import 'member_invoice_hub_page.dart';

/// Fitur 9 — riwayat resep / pesan ulang via WA toko.
class MemberReorderPage extends StatefulWidget {
  const MemberReorderPage({super.key});

  @override
  State<MemberReorderPage> createState() => _MemberReorderPageState();
}

class _MemberReorderPageState extends State<MemberReorderPage> {
  final _repo = MemberRepository();
  final _hub = InvoiceHubService();
  bool _loading = true;
  final List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final sales = await _repo.listSales(phone);
    final out = <Map<String, dynamic>>[];
    for (final s in sales.take(15)) {
      final inv = s['no_invoice']?.toString();
      if (inv == null || inv.isEmpty) continue;
      final hub = await _hub.loadByInvoice(inv);
      final items = (hub?['items'] as List?) ?? const [];
      for (final raw in items) {
        final it = Map<String, dynamic>.from(raw as Map);
        out.add({
          'no_invoice': inv,
          'toko_id': s['toko_id'],
          'nama_produk': it['nama_produk'],
          'detail_resep': it['detail_resep'],
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(out);
      _loading = false;
    });
  }

  Future<void> _waReorder(Map<String, dynamic> row) async {
    final toko = (row['toko_id'] ?? 'PUSAT').toString();
    final settings = await _repo.storeSettings(toko);
    final phone = (settings?['phone'] ?? '').toString();
    final msg =
        'Halo Optik B. Riski, saya ingin pesan ulang mirip nota ${row['no_invoice']}: '
        '${row['nama_produk']}. Resep: ${row['detail_resep'] ?? '-'}';
    if (phone.trim().isEmpty) {
      await openAdminWhatsApp(message: msg);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/${normalizeWaNumber(phone)}?text=${Uri.encodeComponent(msg)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = MemberSession.instance.isLoggedIn;
    return MemberPremiumScaffold(
      title: 'Resep & pesan ulang',
      body: !loggedIn
          ? MemberEmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Login dulu',
              message: 'Riwayat resep terikat nomor HP belanja.',
              actionLabel: 'Ke login',
              onAction: () =>
                  Navigator.of(context).pushReplacementNamed('/login'),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const MemberEmptyState(
                      icon: Icons.history_edu_outlined,
                      title: 'Belum ada resep',
                      message:
                          'Item dari transaksi sebelumnya akan muncul di sini.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: OptikMemberTokens.white,
                            borderRadius: BorderRadius.circular(
                                OptikMemberTokens.radiusMd),
                            border:
                                Border.all(color: OptikMemberTokens.lineSoft),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${r['nama_produk']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: OptikMemberTokens.blueDeep)),
                              const SizedBox(height: 4),
                              Text(
                                'Nota ${r['no_invoice']} · ${r['toko_id']}',
                                style: const TextStyle(
                                    color: OptikMemberTokens.inkMuted),
                              ),
                              if ((r['detail_resep'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('${r['detail_resep']}',
                                    style: const TextStyle(
                                        color: OptikMemberTokens.inkSecondary,
                                        height: 1.35)),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(0, 42)),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MemberInvoiceHubPage(
                                            noInvoice: '${r['no_invoice']}',
                                          ),
                                        ),
                                      ),
                                      child: const Text('Nota'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                          minimumSize: const Size(0, 42)),
                                      onPressed: () => _waReorder(r),
                                      child: const Text('WA pesan ulang'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
