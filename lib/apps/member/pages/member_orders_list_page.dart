import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/invoice/invoice_hub_service.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_invoice_hub_page.dart';

/// Fitur 1 & 5 — status + riwayat belanja.
class MemberOrdersListPage extends StatefulWidget {
  const MemberOrdersListPage({
    super.key,
    this.title = 'Pesanan saya',
    this.onlyActive = false,
  });

  final String title;
  final bool onlyActive;

  @override
  State<MemberOrdersListPage> createState() => _MemberOrdersListPageState();
}

class _MemberOrdersListPageState extends State<MemberOrdersListPage> {
  final _repo = MemberRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sales = const [];
  StreamSubscription<void>? _watchSub;

  @override
  void initState() {
    super.initState();
    _load();
    _watchSub = MemberStatusWatch.instance.onRefresh.listen((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _watchSub?.cancel();
    super.dispose();
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
      var list = await _repo.listSales(phone);
      if (widget.onlyActive) {
        list = list.where((s) {
          final diambil = s['diambil_at'] != null ||
              (s['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
          return !diambil;
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        _sales = list;
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

  String _money(dynamic v) {
    final n = int.tryParse('$v') ?? 0;
    return NumberFormat.currency(
            locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(n);
  }

  @override
  Widget build(BuildContext context) {
    return MemberPremiumScaffold(
      title: widget.title,
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'login'
              ? MemberEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Login dulu',
                  message:
                      'Masuk dengan nomor HP agar pesanan & nota terhubung.',
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
                  : _sales.isEmpty
                      ? MemberEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Belum ada pesanan',
                          message:
                              'Transaksi dengan nomor HP yang sama akan muncul di sini.',
                          actionLabel: 'Muat ulang',
                          onAction: _load,
                        )
                      : RefreshIndicator(
                          color: OptikMemberTokens.blue,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            itemCount: _sales.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final s = _sales[i];
                              final inv = s['no_invoice']?.toString() ?? '-';
                              final label = InvoiceHubService.statusLabel({
                                'tracking_status': s['tracking_status'],
                                'diambil_at': s['diambil_at'],
                              });
                              final pay =
                                  (int.tryParse('${s['sisa_tagihan'] ?? 0}') ??
                                              0) >
                                          0
                                      ? 'DP'
                                      : 'LUNAS';
                              return Material(
                                color: OptikMemberTokens.white,
                                borderRadius: BorderRadius.circular(
                                    OptikMemberTokens.radiusMd),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                      OptikMemberTokens.radiusMd),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          MemberInvoiceHubPage(noInvoice: inv),
                                    ),
                                  ).then((_) => _load()),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          OptikMemberTokens.radiusMd),
                                      border: Border.all(
                                          color: OptikMemberTokens.lineSoft),
                                      boxShadow: OptikMemberTokens.cardShadow,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                inv,
                                                style: const TextStyle(
                                                  color:
                                                      OptikMemberTokens.blueDeep,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Text(pay,
                                                style: const TextStyle(
                                                  color: OptikMemberTokens.blue,
                                                  fontWeight: FontWeight.w800,
                                                )),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$label · ${s['toko_id'] ?? '-'}',
                                          style: const TextStyle(
                                            color: OptikMemberTokens.inkSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _money(s['total_harga']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: OptikMemberTokens.ink,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
    );
  }
}
