import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../config.dart';

Completer<void>? _loadGate;

T? _jsAs<T extends JSAny>(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<T>()) return null; // ignore: sdk_version_since
  return value as T;
}

bool get googleMapsJsReadyImpl {
  if (!globalContext.has('google')) return false;
  final google = _jsAs<JSObject>(globalContext.getProperty('google'.toJS));
  if (google == null) return false;
  return google.has('maps');
}

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
    final document = _jsAs<JSObject>(globalContext.getProperty('document'.toJS));
    if (document == null) {
      throw StateError('Document web tidak ada');
    }
    final existing = document.callMethod<JSAny?>(
      'querySelector'.toJS,
      'script[src*="maps.googleapis.com/maps/api/js"]'.toJS,
    );
    if (existing != null &&
        existing.isDefinedAndNotNull &&
        !googleMapsJsReadyImpl) {
      void onExistingLoad(JSAny _) {
        if (!_loadGate!.isCompleted) _loadGate!.complete();
      }

      final node = _jsAs<JSObject>(existing);
      if (node == null) {
        throw StateError('Script Maps JS tidak valid');
      }
      node.callMethod(
        'addEventListener'.toJS,
        'load'.toJS,
        onExistingLoad.toJS,
      );
      await _loadGate!.future.timeout(const Duration(seconds: 12));
      return;
    }
    if (googleMapsJsReadyImpl) {
      if (!_loadGate!.isCompleted) _loadGate!.complete();
      return;
    }
    final src =
        'https://maps.googleapis.com/maps/api/js?key=${Uri.encodeQueryComponent(key)}&language=id&region=id';
    final script = document.callMethod<JSObject>(
      'createElement'.toJS,
      'script'.toJS,
    );
    script.setProperty('src'.toJS, src.toJS);
    script.setProperty('async'.toJS, true.toJS);
    final done = Completer<void>();
    void onLoad(JSAny _) {
      if (!done.isCompleted) done.complete();
    }

    void onError(JSAny _) {
      if (!done.isCompleted) {
        done.completeError(StateError('Gagal memuat Google Maps JS'));
      }
    }

    script.callMethod('addEventListener'.toJS, 'load'.toJS, onLoad.toJS);
    script.callMethod('addEventListener'.toJS, 'error'.toJS, onError.toJS);
    final head = _jsAs<JSObject>(document.getProperty('head'.toJS));
    if (head == null) {
      throw StateError('document.head tidak ada');
    }
    head.callMethod('appendChild'.toJS, script);
    await done.future.timeout(const Duration(seconds: 15));
    if (!_loadGate!.isCompleted) _loadGate!.complete();
  } catch (e) {
    if (!_loadGate!.isCompleted) _loadGate!.completeError(e);
    rethrow;
  }
}
