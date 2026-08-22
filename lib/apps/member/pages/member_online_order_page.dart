import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/member/member_online_order_labels.dart';
import '../../../shared/member/member_repository.dart';
import '../../../shared/member/member_session.dart';
import '../../../shared/theme.dart';
import '../../../shared/whatsapp_launcher.dart';
import '../member_widgets.dart';
import 'member_invoice_hub_page.dart';
import 'member_midtrans_pay_page.dart';
import 'member_orders_list_page.dart';
import '../../../shared/brand/brand_service.dart';

/// Detail pesanan online (`online_orders`) — pending bayar / tanpa nota / resume Snap.
class MemberOnlineOrderPage extends StatefulWidget {
  const MemberOnlineOrderPage({super.key, required this.onlineOrderId});

  final String onlineOrderId;

  @override
  State<MemberOnlineOrderPage> createState() => _MemberOnlineOrderPageState();
}

class _MemberOnlineOrderPageState extends State<MemberOnlineOrderPage> {
  final _repo = MemberRepository();
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  bool _loading = true;
  bool _paying = false;
  String? _error;
  Map<String, dynamic>? _order;
  Timer? _tick;
  Duration _remaining = Duration.zero;
  bool _expireReloadQueued = false;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncCountdown();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncCountdown() {
    final status = (_order?['status'] ?? '').toString();
    if (status != 'pending_payment') {
      _expireReloadQueued = false;
      if (_remaining != Duration.zero && mounted) {
        setState(() => _remaining = Duration.zero);
      }
      return;
    }
    final exp = MemberPaymentCountdownBanner.expiresAtFromOrder(_order);
    if (exp == null) return;
    final next = exp.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _remaining = next);
    if (next <= Duration.zero && !_expireReloadQueued && !_loading) {
      _expireReloadQueued = true;
      _load();
    }
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
    final res = await _repo.getOnlineOrder(
      phone: phone,
      onlineOrderId: widget.onlineOrderId,
    );
    if (!mounted) return;
    if (res['ok'] != true) {
      setState(() {
        _loading = false;
        _error = (res['error'] ?? 'Order tidak ditemukan').toString();
      });
      return;
    }
    final order = res['order'];
    setState(() {
      _order = order is Map ? Map<String, dynamic>.from(order) : null;
      _loading = false;
      if (_order == null) _error = 'Order kosong';
    });
    _syncCountdown();
  }

  bool get _isDevSnap {
    final token = (_order?['midtrans_snap_token'] ?? '').toString();
    return token.isEmpty || token.startsWith('DEV_');
  }

  String get _redirectUrl =>
      (_order?['midtrans_redirect_url'] ?? '').toString().trim();

  Future<void> _cancelPending() async {
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan pesanan?'),
        content: const Text(
          'Stok yang di-hold akan dikembalikan. Pesanan tidak bisa dilanjutkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying = true);
    final res = await _repo.cancelPendingOnlineOrder(
      phone: phone,
      onlineOrderId: widget.onlineOrderId,
    );
    if (!mounted) return;
    setState(() => _paying = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res['error'] ?? 'Gagal batalkan'}'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pesanan dibatalkan · stok dikembalikan'),
        backgroundColor: OptikMemberTokens.success,
      ),
    );
    await _load();
  }

  Future<void> _continuePay() async {
    final phone = MemberSession.instance.phoneForQuery;
    final status = (_order?['status'] ?? '').toString();
    if (status != 'pending_payment') return;
    if (_remaining <= Duration.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waktu bayar 15 menit habis. Stok dikembalikan — buat pesanan baru.',
          ),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      await _load();
      return;
    }

    // Resume Snap jika ada redirect nyata.
    if (!_isDevSnap && _redirectUrl.isNotEmpty) {
      setState(() => _paying = true);
      final paid = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => MemberMidtransPayPage(
            redirectUrl: _redirectUrl,
            phone: phone,
            onlineOrderId: widget.onlineOrderId,
            expiresAt:
                MemberPaymentCountdownBanner.expiresAtFromOrder(_order),
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _paying = false);
      if (paid == true) {
        await _afterPaid();
      } else {
        await _load();
      }
      return;
    }

    // Mode uji / tanpa Midtrans.
    final mid = (_order?['midtrans_order_id'] ?? '').toString();
    if (mid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID pembayaran belum tersedia')),
      );
      return;
    }
    setState(() => _paying = true);
    final res = await _repo.mockPayOnlineOrder(mid);
    if (!mounted) return;
    setState(() => _paying = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${res['error'] ?? 'Gagal bayar'}'),
          backgroundColor: OptikMemberTokens.danger,
        ),
      );
      return;
    }
    await _afterPaid(invoice: (res['no_invoice'] ?? '').toString());
  }

  Future<String> _resolveInvoiceNo() async {
    final fromOrder = (_order?['no_invoice'] ?? '').toString().trim();
    if (fromOrder.isNotEmpty) return fromOrder;
    final phone = MemberSession.instance.phoneForQuery;
    if (phone.isEmpty) return '';
    final saleId = (_order?['sale_id'] ?? '').toString().trim();
    final oid = widget.onlineOrderId.trim();
    try {
      final sales = await _repo.listSales(phone);
      for (final s in sales) {
        final matchOid =
            oid.isNotEmpty && (s['online_order_id'] ?? '').toString() == oid;
        final matchSale =
            saleId.isNotEmpty && (s['id'] ?? '').toString() == saleId;
        if (matchOid || matchSale) {
          return (s['no_invoice'] ?? '').toString().trim();
        }
      }
    } catch (_) {}
    return '';
  }

  Future<void> _openNota(String inv) async {
    if (inv.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberInvoiceHubPage(noInvoice: inv),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _waToko() async {
    final toko = (_order?['toko_id'] ?? 'PUSAT').toString();
    final settings = await _repo.storeSettings(toko);
    final phone = (settings?['phone'] ?? '').toString();
    final mid = (_order?['midtrans_order_id'] ?? '').toString();
    final ref = mid.isNotEmpty
        ? mid
        : (widget.onlineOrderId.length >= 8
            ? widget.onlineOrderId.substring(0, 8)
            : widget.onlineOrderId);
    final msg =
        'Halo ${BrandService.name}, saya cek status pesanan online $ref (cabang $toko).';
    if (phone.isEmpty) {
      await openAdminWhatsApp(message: msg);
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/${normalizeWaNumber(phone)}?text=${Uri.encodeComponent(msg)}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _afterPaid({String? invoice}) async {
    var inv = (invoice ?? '').trim();
    if (inv.isEmpty) {
      await _load();
      inv = await _resolveInvoiceNo();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(inv.isEmpty ? 'Pembayaran berhasil' : 'Lunas · nota $inv'),
        backgroundColor: OptikMemberTokens.success,
      ),
    );
    if (inv.isNotEmpty) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MemberInvoiceHubPage(noInvoice: inv),
        ),
      );
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MemberOrdersListPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final status = (o?['status'] ?? '').toString();
    final pending = status == 'pending_payment';
    final payExpired = pending && _remaining <= Duration.zero;
    final items = o?['items'];
    final itemList = items is List ? items : const [];
    final payLabel = !pending || payExpired
        ? null
        : (_paying
            ? 'Memproses…'
            : (!_isDevSnap && _redirectUrl.isNotEmpty)
                ? 'Lanjut bayar Midtrans'
                : 'Bayar sekarang (uji / tanpa Snap)');

    return MemberPremiumScaffold(
      title: 'Pesanan online',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error == 'login'
              ? MemberEmptyState(
                  icon: Icons.lock_outline_rounded,
                  title: 'Login dulu',
                  message: 'Masuk untuk melihat pesanan online.',
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
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                      children: [
                        if (pending) ...[
                          MemberPaymentCountdownBanner(remaining: _remaining),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: OptikMemberTokens.white,
                            borderRadius: BorderRadius.circular(
                                OptikMemberTokens.radiusMd),
                            border:
                                Border.all(color: OptikMemberTokens.lineSoft),
                            boxShadow: OptikMemberTokens.cardShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      MemberOnlineOrderLabels.status(status),
                                      style: TextStyle(
                                        color: MemberOnlineOrderLabels
                                            .statusColor(status),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _money.format(
                                        int.tryParse('${o?['total'] ?? 0}') ??
                                            0),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: OptikMemberTokens.blueDeep,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${o?['toko_id'] ?? '-'} · '
                                '${MemberOnlineOrderLabels.fulfillment(o?['fulfillment']?.toString())}',
                                style: const TextStyle(
                                  color: OptikMemberTokens.inkSecondary,
                                ),
                              ),
                              if ((o?['courier_tracking'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Resi: ${o?['courier_tracking']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              if ((o?['address_text'] ?? '')
                                  .toString()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  o!['address_text'].toString(),
                                  style: const TextStyle(
                                    color: OptikMemberTokens.inkMuted,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Item',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: OptikMemberTokens.blueDeep,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final raw in itemList)
                          if (raw is Map)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: OptikMemberTokens.white,
                                  borderRadius: BorderRadius.circular(
                                      OptikMemberTokens.radiusSm),
                                  border: Border.all(
                                      color: OptikMemberTokens.lineSoft),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (raw['nama'] ?? raw['sku'] ?? 'Item')
                                            .toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'x${raw['qty'] ?? 1}',
                                      style: const TextStyle(
                                        color: OptikMemberTokens.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        if (payLabel != null) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _paying ? null : _continuePay,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: OptikMemberTokens.blueDeep,
                            ),
                            child: Text(payLabel),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (!_isDevSnap && _redirectUrl.isNotEmpty)
                                ? 'Lanjutkan pembayaran Snap yang belum selesai.'
                                : 'Mode uji: lunasi tanpa Midtrans. Set MIDTRANS_SERVER_KEY di Edge untuk bayar asli.',
                            style: const TextStyle(
                              color: OptikMemberTokens.inkMuted,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (pending && !payExpired) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _paying ? null : _cancelPending,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              foregroundColor: OptikMemberTokens.danger,
                            ),
                            child: const Text('Batalkan pesanan'),
                          ),
                        ],
                        if (!pending &&
                            ((_order?['sale_id'] ?? '').toString().isNotEmpty ||
                                status == 'fulfilled' ||
                                status == 'paid' ||
                                status == 'packing' ||
                                status == 'ready' ||
                                status == 'shipped')) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _paying
                                ? null
                                : () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    final inv = await _resolveInvoiceNo();
                                    if (!mounted) return;
                                    if (inv.isEmpty) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Nota belum tersedia. Coba muat ulang sebentar lagi.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    await _openNota(inv);
                                  },
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Lihat nota'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _paying ? null : _waToko,
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('Hubungi toko (WA)'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            backgroundColor: OptikMemberTokens.blueDeep,
                          ),
                        ),
                      ],
                    ),
    );
  }
}
