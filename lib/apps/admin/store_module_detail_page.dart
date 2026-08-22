import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/store_catalog.dart';
import '../../shared/brand/rekasa_tokens.dart';

/// Video + paragraf penjelasan satu fitur paket.
class StoreModuleDetailPage extends StatefulWidget {
  const StoreModuleDetailPage({super.key, required this.module});

  final StoreModuleDef module;

  @override
  State<StoreModuleDetailPage> createState() => _StoreModuleDetailPageState();
}

class _StoreModuleDetailPageState extends State<StoreModuleDetailPage> {
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    final embed = StoreVideo.embedUrl(widget.module.videoUrl);
    if (!kIsWeb && embed != null) {
      _web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(embed));
    }
  }

  Future<void> _openExternal() async {
    final raw = (widget.module.videoUrl ?? '').trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final hasVideo = (m.videoUrl ?? '').trim().isNotEmpty;
    return Scaffold(
      backgroundColor: RekasaTokens.canvas,
      appBar: AppBar(
        title: Text(m.label),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            m.summary,
            style: const TextStyle(
              color: RekasaTokens.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (_web != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: WebViewWidget(controller: _web!),
              ),
            )
          else if (hasVideo)
            OutlinedButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Putar video penjelasan'),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RekasaTokens.wash,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Video belum diunggah. Rekasa bisa tempel tautan YouTube di menu Pesanan etalase.',
                style: TextStyle(height: 1.35),
              ),
            ),
          const SizedBox(height: 18),
          Text(
            m.body,
            style: TextStyle(
              color: RekasaTokens.ink.withOpacity(0.88),
              height: 1.5,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
