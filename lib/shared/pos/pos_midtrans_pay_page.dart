import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../bootstrap.dart';

/// WebView Snap kasir. Poll `get_pos_payment`, bukan order Member.
class PosMidtransPayPage extends StatefulWidget {
  const PosMidtransPayPage({
    super.key,
    required this.redirectUrl,
    required this.midtransOrderId,
  });

  final String redirectUrl;
  final String midtransOrderId;

  @override
  State<PosMidtransPayPage> createState() => _PosMidtransPayPageState();
}

class _PosMidtransPayPageState extends State<PosMidtransPayPage> {
  late final WebViewController _controller;
  bool _checking = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollStatus());
    });
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _pollStatus()),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pollStatus() async {
    if (_checking) return;
    _checking = true;
    try {
      final raw = await supabase.rpc(
        'get_pos_payment',
        params: {'p_midtrans_order_id': widget.midtransOrderId},
      );
      if (!mounted || raw is! Map) return;
      final status = (raw['status'] ?? '').toString();
      if (status == 'paid') {
        Navigator.pop(context, true);
      } else if (status == 'expired' || status == 'cancelled') {
        Navigator.pop(context, false);
      }
    } catch (_) {
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
            onPressed: () => _pollStatus(),
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
      body: WebViewWidget(controller: _controller),
    );
  }
}
