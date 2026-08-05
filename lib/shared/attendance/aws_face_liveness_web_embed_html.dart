// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'aws_face_liveness_service.dart';

/// Embed Amplify Face Liveness UI di iframe (Flutter web / Admin).
class AwsFaceLivenessWebEmbed {
  AwsFaceLivenessWebEmbed({
    required this.viewType,
    required this.uiUrl,
    required this.session,
    required this.onEvent,
  });

  final String viewType;
  final String uiUrl;
  final AwsLivenessSession session;
  final void Function(Map<String, dynamic> event) onEvent;

  html.IFrameElement? _iframe;
  StreamSubscription<html.MessageEvent>? _sub;
  bool _uiReady = false;
  bool _started = false;

  void register() {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final iframe = html.IFrameElement()
        ..src = uiUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'camera; microphone; autoplay';
      iframe.setAttribute('allowfullscreen', 'true');
      _iframe = iframe;
      return iframe;
    });

    _sub = html.window.onMessage.listen((html.MessageEvent event) {
      final data = event.data;
      if (data is! String) return;
      Map<String, dynamic>? raw;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) raw = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return;
      }
      if (raw == null) return;
      if (raw['source']?.toString() != 'optik-aws-liveness') return;
      // Hanya start setelah script UI siap (hindari race onLoad vs importmap).
      if (raw['type']?.toString() == 'ready') {
        _uiReady = true;
        _tryStart();
      }
      onEvent(raw);
    });
  }

  void _tryStart() {
    if (_started || !_uiReady || _iframe == null) return;
    final win = _iframe!.contentWindow;
    if (win == null) return;
    _started = true;
    final cfg = {
      'sessionId': session.sessionId,
      'region': session.region,
      'credentials': session.credentials.toJson(),
    };
    win.postMessage(
      jsonEncode({'type': 'optik-start-liveness', 'cfg': cfg}),
      '*',
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _iframe = null;
  }
}
