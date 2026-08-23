import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../config.dart';

Completer<void>? _loadGate;

JSObject? _asObject(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSObject>()) return null; // ignore: sdk_version_since
  return value as JSObject;
}

bool get googleMapsJsReadyImpl {
  if (!globalContext.has('google')) return false;
  final google = _asObject(globalContext.getProperty('google'.toJS));
  if (google == null) return false;
  return google.has('maps');
}

Future<void> ensureGoogleMapsJsImpl() async {
  final key = googleMapsApiKey.trim();
  if (key.isEmpty) return;
  if (googleMapsJsReadyImpl) return;

  final existing = _loadGate;
  if (existing != null) {
    try {
      await existing.future;
    } catch (_) {}
    if (googleMapsJsReadyImpl) return;
  }

  final gate = Completer<void>();
  _loadGate = gate;
  try {
    await _ensureScript(key);
    await _waitUntilReady();
    if (!gate.isCompleted) gate.complete();
  } catch (e) {
    if (!gate.isCompleted) gate.completeError(e);
    if (identical(_loadGate, gate)) _loadGate = null;
    rethrow;
  }
}

Future<void> _ensureScript(String key) async {
  if (googleMapsJsReadyImpl) return;
  final document = _asObject(globalContext.getProperty('document'.toJS));
  if (document == null) {
    throw StateError('Document web tidak ada');
  }
  final existing = document.callMethod<JSAny?>(
    'querySelector'.toJS,
    'script[src*="maps.googleapis.com/maps/api/js"]'.toJS,
  );
  if (existing != null && existing.isDefinedAndNotNull) {
    return;
  }
  final src =
      'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(key)}'
      '&language=id&region=id&loading=async';
  final script = document.callMethod<JSObject>(
    'createElement'.toJS,
    'script'.toJS,
  );
  script.setProperty('src'.toJS, src.toJS);
  script.setProperty('async'.toJS, true.toJS);
  final head = _asObject(document.getProperty('head'.toJS));
  if (head == null) {
    throw StateError('document.head tidak ada');
  }
  head.callMethod('appendChild'.toJS, script);
}

Future<void> _waitUntilReady() async {
  const step = Duration(milliseconds: 50);
  const limit = Duration(seconds: 15);
  final started = DateTime.now();
  while (!googleMapsJsReadyImpl) {
    if (DateTime.now().difference(started) > limit) {
      throw StateError('Google Maps JS belum siap');
    }
    await Future<void>.delayed(step);
  }
}
