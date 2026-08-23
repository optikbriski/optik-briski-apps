// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import '../config.dart';

Completer<void>? _loadGate;

Future<void> ensureGoogleMapsJsImpl() async {
  final key = googleMapsApiKey.trim();
  if (key.isEmpty) return;
  if (googleMapsJsReadyImpl) return;
  if (_loadGate != null) {
    await _loadGate!.future;
    return;
  }
  _loadGate = Completer<void>();
  try {
    final existing = html.document.querySelector(
      'script[src*="maps.googleapis.com/maps/api/js"]',
    );
    if (existing != null && !googleMapsJsReadyImpl) {
      existing.addEventListener('load', (_) {
        if (!_loadGate!.isCompleted) _loadGate!.complete();
      });
      await _loadGate!.future.timeout(const Duration(seconds: 12));
      return;
    }
    if (googleMapsJsReadyImpl) {
      if (!_loadGate!.isCompleted) _loadGate!.complete();
      return;
    }
    final script = html.ScriptElement()
      ..src =
          'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(key)}&language=id&region=id'
      ..async = true;
    final done = Completer<void>();
    script.onLoad.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    script.onError.listen((_) {
      if (!done.isCompleted) {
        done.completeError(StateError('Gagal memuat Google Maps JS'));
      }
    });
    html.document.head!.append(script);
    await done.future.timeout(const Duration(seconds: 15));
    if (!_loadGate!.isCompleted) _loadGate!.complete();
  } catch (e) {
    if (!_loadGate!.isCompleted) _loadGate!.completeError(e);
    rethrow;
  }
}

bool get googleMapsJsReadyImpl {
  if (!js.context.hasProperty('google')) return false;
  final g = js.context['google'];
  if (g is! js.JsObject) return false;
  return g.hasProperty('maps');
}
