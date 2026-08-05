import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/member/member_repository.dart';
import '../member_widgets.dart';

/// WebView pembayaran Midtrans Snap — dipakai checkout & resume pending.
class MemberMidtransPayPage extends StatefulWidget {
  const MemberMidtransPayPage({
    super.key,
    required this.redirectUrl,
    required this.phone,
    required this.onlineOrderId,
    this.expiresAt,
  });

  final String redirectUrl;
  final String phone;
  final String onlineOrderId;
  final DateTime? expiresAt;

  @override
  State<MemberMidtransPayPage> createState() => _MemberMidtransPayPageState();
}

class _MemberMidtransPayPageState extends State<MemberMidtransPayPage> {
  late final WebViewController _controller;
  final _repo = MemberRepository();
  bool _checking = false;
  bool _expiredHandled = false;
  DateTime? _expiresAt;
  Timer? _tick;
  Timer? _statusPoll;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _expiresAt = widget.expiresAt?.toLocal();
    _refreshRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshRemaining();
      if (_remaining <= Duration.zero) {
        _onExpired();
      }
    });
    // Poll status berkala — jangan andalkan onPageFinished saja.
    _statusPoll = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollStatus());
    });
    _loadExpiresAt();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _pollStatus(),
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _statusPoll?.cancel();
    super.dispose();
  }

  void _refreshRemaining() {
    final exp = _expiresAt;
    final next = exp == null
        ? Duration.zero
        : exp.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _remaining = next);
  }

  Future<void> _loadExpiresAt() async {
    try {
      final res = await _repo.getOnlineOrder(
        phone: widget.phone,
        onlineOrderId: widget.onlineOrderId,
      );
      if (!mounted) return;
      final order = res['order'];
      if (order is Map) {
        final map = Map<String, dynamic>.from(order);
        final exp = MemberPaymentCountdownBanner.expiresAtFromOrder(map);
        if (exp != null) {
          setState(() => _expiresAt = exp);
          _refreshRemaining();
        }
        final status = (map['status'] ?? '').toString();
        if (status == 'expired' || status == 'cancelled') {
          _onExpired();
        }
      }
    } catch (_) {
      // Countdown opsional — WebView tetap jalan.
    }
  }

  Future<void> _onExpired() async {
    if (_expiredHandled || !mounted) return;
    _expiredHandled = true;
    _tick?.cancel();
    // Pastikan server expire + lepas ONLINE_HOLD (jangan hanya UI).
    try {
      await _repo.getOnlineOrder(
        phone: widget.phone,
        onlineOrderId: widget.onlineOrderId,
      );
    } catch (_) {
      try {
        await Supabase.instance.client.rpc('expire_all_stale_stock_holds');
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Waktu bayar habis'),
        content: const Text(
          'Batas 15 menit terlewati. Pesanan dibatalkan dan stok dikembalikan. '
          'Silakan buat pesanan baru.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _pollStatus() async {
    if (_checking) return;
    _checking = true;
    try {
      final res = await _repo.getOnlineOrder(
        phone: widget.phone,
        onlineOrderId: widget.onlineOrderId,
      );
      if (!mounted) return;
      final order = res['order'];
      if (order is Map) {
        final map = Map<String, dynamic>.from(order);
        final exp = MemberPaymentCountdownBanner.expiresAtFromOrder(map);
        if (exp != null && _expiresAt == null) {
          setState(() => _expiresAt = exp);
          _refreshRemaining();
        }
        final status = (order['status'] ?? '').toString();
        if (status == 'paid' ||
            status == 'packing' ||
            status == 'ready' ||
            status == 'shipped' ||
            status == 'fulfilled') {
          Navigator.pop(context, true);
        } else if (status == 'expired' || status == 'cancelled') {
          await _onExpired();
        }
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pembayaran Midtrans'),
        actions: [
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await _pollStatus();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text('Status diperbarui')),
              );
            },
            child: const Text('Cek status'),
          ),
          IconButton(
            tooltip: 'Buka di browser',
            onPressed: () => launchUrl(
              Uri.parse(widget.redirectUrl),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_expiresAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: MemberPaymentCountdownBanner(
                remaining: _remaining,
                compact: true,
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
