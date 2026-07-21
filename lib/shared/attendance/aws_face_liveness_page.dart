import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import 'attendance_config.dart';
import 'aws_face_liveness_service.dart';
import 'face_from_image.dart';
import 'liveness_result.dart';

/// AWS Rekognition Face Liveness via Amplify UI (HTML) di WebView.
///
/// Alur: create_session → inject credentials ke WebView → onComplete → get_results
/// → template lokal dari reference image (opsional fallback kamera lokal tidak di sini).
class AwsFaceLivenessPage extends StatefulWidget {
  const AwsFaceLivenessPage({super.key});

  @override
  State<AwsFaceLivenessPage> createState() => _AwsFaceLivenessPageState();
}

class _AwsFaceLivenessPageState extends State<AwsFaceLivenessPage> {
  final _service = AwsFaceLivenessService();
  WebViewController? _controller;
  bool _booting = true;
  bool _finishing = false;
  String? _error;
  AwsLivenessSession? _session;
  bool _injected = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (kIsWeb) {
      setState(() {
        _booting = false;
        _error = 'aws_liveness_web_unsupported'.tr();
      });
      return;
    }

    try {
      final session = await _service.createSession();
      if (!mounted) return;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0F172A))
        ..addJavaScriptChannel(
          'LivenessBridge',
          onMessageReceived: _onBridgeMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => _injectSession(),
          ),
        );

      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        await AndroidWebViewController.enableDebugging(false);
        await platform.setMediaPlaybackRequiresUserGesture(false);
        await platform.setOnPlatformPermissionRequest((request) async {
          request.grant();
        });
      }

      // Supabase gateway biasanya wajib apikey / Authorization.
      await controller.loadRequest(
        Uri.parse(_service.uiUrl),
        headers: {
          'apikey': supabasePublishableKey,
          'Authorization': 'Bearer $supabasePublishableKey',
        },
      );

      setState(() {
        _session = session;
        _controller = controller;
        _booting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _injectSession() async {
    if (_injected || _session == null || _controller == null) return;
    _injected = true;
    final payload = {
      'sessionId': _session!.sessionId,
      'region': _session!.region,
      'credentials': _session!.credentials.toJson(),
    };
    final js =
        'window.__startLiveness && window.__startLiveness(${jsonEncode(payload)});';
    try {
      await _controller!.runJavaScript(js);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Gagal memulai UI liveness: $e');
    }
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    Map<String, dynamic>? data;
    try {
      final raw = jsonDecode(message.message);
      if (raw is Map) data = Map<String, dynamic>.from(raw);
    } catch (_) {
      return;
    }
    if (data == null) return;

    final type = data['type']?.toString();
    if (type == 'ready') {
      _injectSession();
      return;
    }
    if (type == 'cancel') {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (type == 'error') {
      setState(() {
        _error = data!['message']?.toString() ?? 'aws_liveness_failed'.tr();
      });
      return;
    }
    if (type == 'complete') {
      _finishSession();
    }
  }

  Future<void> _finishSession() async {
    if (_finishing || _session == null) return;
    setState(() {
      _finishing = true;
      _error = null;
    });

    try {
      final results = await _service.getResults(_session!.sessionId);
      if (!results.passed) {
        throw results.error ??
            'aws_liveness_low_confidence'.tr(
              namedArgs: {
                'score': results.confidence.toStringAsFixed(1),
                'min': results.minConfidence.toStringAsFixed(0),
              },
            );
      }

      List<double>? template;
      if (AttendanceConfig.useLocalFaceMatch &&
          results.referenceImageBytes != null) {
        template = await faceTemplateFromJpeg(results.referenceImageBytes!);
      }

      if (!mounted) return;
      Navigator.pop(
        context,
        LivenessCaptureResult(
          success: true,
          photoBytes: results.referenceImageBytes,
          faceTemplate: template,
          livenessProvider: 'aws',
          livenessSessionId: results.sessionId,
          livenessConfidence: results.confidence,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _finishing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('aws_liveness_title'.tr()),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else if (_booting)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  Text(
                    'aws_liveness_preparing'.tr(),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            const SizedBox.expand(),
          if (_finishing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.tealAccent),
                    const SizedBox(height: 16),
                    Text(
                      'aws_liveness_verifying'.tr(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null)
            Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _booting = true;
                          _injected = false;
                          _controller = null;
                          _session = null;
                        });
                        _boot();
                      },
                      child: Text('aws_liveness_retry'.tr()),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('aws_liveness_cancel'.tr()),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
