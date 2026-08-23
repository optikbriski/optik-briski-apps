import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Snap lisensi etalase. Selesai = URL finish situs paket (`bayar=selesai`).
class RekasaStoreMidtransPayPage extends StatefulWidget {
  const RekasaStoreMidtransPayPage({
    super.key,
    required this.redirectUrl,
    required this.orderId,
  });

  final String redirectUrl;
  final String orderId;

  @override
  State<RekasaStoreMidtransPayPage> createState() =>
      _RekasaStoreMidtransPayPageState();
}

class _RekasaStoreMidtransPayPageState
    extends State<RekasaStoreMidtransPayPage> {
  late final WebViewController _controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            if (_isFinish(req.url)) {
              _done(true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            if (_isFinish(url)) _done(true);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.redirectUrl));
  }

  bool _isFinish(String url) {
    final u = url.toLowerCase();
    return u.contains('bayar=selesai') ||
        u.contains('transaction_status=settlement') ||
        u.contains('transaction_status=capture');
  }

  void _done(bool paid) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.pop(context, paid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bayar via Midtrans'),
        actions: [
          TextButton(
            onPressed: () => _done(true),
            child: const Text('Sudah bayar'),
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
