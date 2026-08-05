import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/invoice/invoice_hub_service.dart';
import '../../../shared/member/member_online_order_labels.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/member/member_status_watch.dart';
import '../../../shared/theme.dart';
import '../member_widgets.dart';
import 'member_invoice_hub_page.dart';
import 'member_online_order_page.dart';

/// Pesanan Member: nota (`sales`) + pesanan online belum/ada (`online_orders`).
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

class _OrderRow {
  _OrderRow.sale(Map<String, dynamic> data)
      : sale = data,
        online = null,
        sortAt = DateTime.tryParse('${data['created_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

  _OrderRow.online(Map<String, dynamic> data)
      : online = data,
        sale = null,
        sortAt = DateTime.tryParse('${data['created_at']}') ??
            DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, dynamic>? sale;
  final Map<String, dynamic>? online;
  final DateTime sortAt;

  bool get isOnline => online != null;
}

class _MemberOrdersListPageState extends State<MemberOrdersListPage> {
  final _repo = MemberRepository();
  bool _loading = true;
  String? _error;
  List<_OrderRow> _rows = const [];
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
      final results = await Future.wait([
        _repo.listSales(phone),
        _repo.listOnlineOrders(phone),
      ]);
      final sales = results[0];
      final online = results[1];

      final saleOnlineIds = <String>{};
      for (final s in sales) {
        final oid = (s['online_order_id'] ?? '').toString();
        if (oid.isNotEmpty) saleOnlineIds.add(oid);
      }

      final rows = <_OrderRow>[];
      for (final s in sales) {
        final diambil = s['diambil_at'] != null ||
            (s['tracking_status']?.toString().toUpperCase() == 'DIAMBIL');
        if (widget.onlyActive && diambil) continue;
        rows.add(_OrderRow.sale(s));
      }

      for (final o in online) {
        final id = (o['id'] ?? '').toString();
        final status = (o['status'] ?? '').toString();
        final saleId = (o['sale_id'] ?? '').toString();
        // Sudah punya nota / sale_id → tampil sebagai sales (hindari dobel).
        if (id.isNotEmpty && saleOnlineIds.contains(id)) continue;
        if (saleId.isNotEmpty) continue;
        if (status == 'fulfilled' && widget.onlyActive) continue;
        if (widget.onlyActive &&
            (status == 'cancelled' || status == 'expired')) {
          continue;
        }
        // Pending / tanpa sale: tampilkan kartu online.
        rows.add(_OrderRow.online(o));
      }

      rows.sort((a, b) => b.sortAt.compareTo(a.sortAt));

      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _openRow(_OrderRow row) async {
    if (row.isOnline) {
      final id = (row.online!['id'] ?? '').toString();
      if (id.isEmpty) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberOnlineOrderPage(onlineOrderId: id),
        ),
      );
    } else {
      final inv = row.sale!['no_invoice']?.toString() ?? '';
      if (inv.isEmpty) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MemberInvoiceHubPage(noInvoice: inv),
        ),
      );
    }
    if (mounted) await _load();
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
                  : _rows.isEmpty
                      ? MemberEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Belum ada pesanan',
                          message:
                              'Belanja Online & nota dengan nomor HP yang sama muncul di sini.',
                          actionLabel: 'Muat ulang',
                          onAction: _load,
                        )
                      : RefreshIndicator(
                          color: OptikMemberTokens.blue,
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final row = _rows[i];
                              if (row.isOnline) {
                                return _onlineCard(row.online!);
                              }
                              return _saleCard(row.sale!);
                            },
                          ),
                        ),
    );
  }

  Widget _saleCard(Map<String, dynamic> s) {
    final inv = s['no_invoice']?.toString() ?? '-';
    final label = InvoiceHubService.statusLabel({
      'tracking_status': s['tracking_status'],
      'diambil_at': s['diambil_at'],
    });
    final pay =
        (int.tryParse('${s['sisa_tagihan'] ?? 0}') ?? 0) > 0 ? 'DP' : 'LUNAS';
    final isOnline =
        (s['channel'] ?? '').toString().toLowerCase() == 'member_online' ||
            (s['online_order_id'] ?? '').toString().isNotEmpty;
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        onTap: () => _openRow(_OrderRow.sale(s)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
            border: Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv,
                      style: const TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (isOnline) ...[
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: OptikMemberTokens.blueSoft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Online',
                        style: TextStyle(
                          color: OptikMemberTokens.blueDeep,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    pay,
                    style: const TextStyle(
                      color: OptikMemberTokens.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
  }

  Widget _onlineCard(Map<String, dynamic> o) {
    final status = (o['status'] ?? '').toString();
    final label = MemberOnlineOrderLabels.status(status);
    final color = MemberOnlineOrderLabels.statusColor(status);
    final mid = (o['midtrans_order_id'] ?? '').toString();
    final id = (o['id'] ?? '').toString();
    final title = mid.isNotEmpty
        ? mid
        : (id.length >= 8 ? 'Online · ${id.substring(0, 8)}' : 'Pesanan online');
    return Material(
      color: OptikMemberTokens.white,
      borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
        onTap: () => _openRow(_OrderRow.online(o)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OptikMemberTokens.radiusMd),
            border: Border.all(color: OptikMemberTokens.lineSoft),
            boxShadow: OptikMemberTokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikMemberTokens.blueDeep,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: color.withOpacity(0.35)),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${MemberOnlineOrderLabels.fulfillment(o['fulfillment']?.toString())}'
                ' · ${o['toko_id'] ?? '-'}',
                style: const TextStyle(
                  color: OptikMemberTokens.inkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _money(o['total']),
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
  }
}
