import 'package:flutter/material.dart';

import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_claim_page.dart';
import 'member_invoice_hub_page.dart';

class MemberWarrantyListPage extends StatefulWidget {
  const MemberWarrantyListPage({super.key});

  @override
  State<MemberWarrantyListPage> createState() => _MemberWarrantyListPageState();
}

class _MemberWarrantyListPageState extends State<MemberWarrantyListPage> {
  final _repo = MemberRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'login';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listGaransi(phone);
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: 'Kartu garansi',
      subtitle: 'Data asli sistem',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'login'
              ? MemberEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Login dulu',
                  message: 'Garansi terikat nomor HP yang dipakai saat belanja.',
                  actionLabel: 'Ke login',
                  onAction: () =>
                      Navigator.of(context).pushReplacementNamed('/login'),
                )
              : _error != null
                  ? MemberEmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Gagal memuat',
                      message: _error!,
                      actionLabel: 'Coba lagi',
                      onAction: _load,
                    )
                  : _rows.isEmpty
                      ? const MemberEmptyState(
                          icon: Icons.verified_user_outlined,
                          title: 'Belum ada garansi',
                          message:
                              'Kartu muncul setelah kacamata diambil / diaktifkan toko.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final g = _rows[i];
                            final inv = g['no_invoice']?.toString() ?? '';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: OptikMemberTokens.white,
                                borderRadius: BorderRadius.circular(
                                    OptikMemberTokens.radiusMd),
                                border: Border.all(
                                    color: OptikMemberTokens.lineSoft),
                                boxShadow: OptikMemberTokens.cardShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${g['jenis_garansi'] ?? '-'} · ${g['nama_produk'] ?? '-'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: OptikMemberTokens.blueDeep,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Status: ${g['status']}\n'
                                    '${g['tanggal_mulai'] ?? '-'} → ${g['tanggal_akhir'] ?? '-'}',
                                    style: const TextStyle(
                                      color: OptikMemberTokens.inkSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (inv.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text('Nota: $inv',
                                        style: const TextStyle(
                                            color: OptikMemberTokens.inkMuted)),
                                  ],
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      if (inv.isNotEmpty)
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                                minimumSize: const Size(0, 42)),
                                            onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    MemberInvoiceHubPage(
                                                        noInvoice: inv),
                                              ),
                                            ),
                                            child: const Text('Lihat nota'),
                                          ),
                                        ),
                                      if (inv.isNotEmpty)
                                        const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 42)),
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MemberClaimPage(
                                                initialKartu: g,
                                              ),
                                            ),
                                          ),
                                          child: const Text('Klaim'),
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
