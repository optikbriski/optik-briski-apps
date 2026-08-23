import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../config.dart';
import 'google_maps_js.dart';
import 'osm_address_search.dart';

JSObject? _asObject(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSObject>()) return null; // ignore: sdk_version_since
  return value as JSObject;
}

JSFunction? _asFunction(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSFunction>()) return null; // ignore: sdk_version_since
  return value as JSFunction;
}

JSArray? _asArray(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSArray>()) return null; // ignore: sdk_version_since
  return value as JSArray;
}

JSNumber? _asNumber(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  if (!value.isA<JSNumber>()) return null; // ignore: sdk_version_since
  return value as JSNumber;
}

JSObject _mapsNs() {
  final google = _asObject(globalContext.getProperty('google'.toJS));
  if (google == null) {
    throw StateError('google.maps belum siap');
  }
  final maps = _asObject(google.getProperty('maps'.toJS));
  if (maps == null) {
    throw StateError('google.maps belum siap');
  }
  return maps;
}

JSObject _newGeocoder() {
  final ctor = _asFunction(_mapsNs().getProperty('Geocoder'.toJS));
  if (ctor == null) {
    throw StateError('google.maps.Geocoder tidak ada');
  }
  return ctor.callAsConstructor<JSObject>();
}

Future<List<OsmAddressHit>> googleGeocodeSearch(
  String query, {
  int limit = 8,
}) async {
  final q = query.trim();
  if (q.isEmpty || googleMapsApiKey.trim().isEmpty) return const [];
  await ensureGoogleMapsJs();
  if (!googleMapsJsReady) return const [];
  final geocoder = _newGeocoder();
  final comps = JSObject()..setProperty('country'.toJS, 'ID'.toJS);
  final req = JSObject()
    ..setProperty('address'.toJS, q.toJS)
    ..setProperty('componentRestrictions'.toJS, comps)
    ..setProperty('language'.toJS, 'id'.toJS)
    ..setProperty('region'.toJS, 'id'.toJS);
  final gate = Completer<List<OsmAddressHit>>();
  void onDone(JSAny? results, JSAny? status) {
    if (gate.isCompleted) return;
    if ('${status.dartify()}' != 'OK') {
      gate.complete(const []);
      return;
    }
    gate.complete(_hitsFromJs(results, limit));
  }

  geocoder.callMethod('geocode'.toJS, req, onDone.toJS);
  return gate.future.timeout(const Duration(seconds: 12));
}

Future<OsmAddressHit?> googleGeocodeReverse(double lat, double lng) async {
  if (googleMapsApiKey.trim().isEmpty) return null;
  await ensureGoogleMapsJs();
  if (!googleMapsJsReady) return null;
  final ctor = _asFunction(_mapsNs().getProperty('LatLng'.toJS));
  if (ctor == null) return null;
  final latLng = ctor.callAsConstructor<JSObject>(lat.toJS, lng.toJS);
  final geocoder = _newGeocoder();
  final req = JSObject()
    ..setProperty('location'.toJS, latLng)
    ..setProperty('language'.toJS, 'id'.toJS);
  final gate = Completer<OsmAddressHit?>();
  void onDone(JSAny? results, JSAny? status) {
    if (gate.isCompleted) return;
    if ('${status.dartify()}' != 'OK') {
      gate.complete(null);
      return;
    }
    final hits = _hitsFromJs(results, 1);
    gate.complete(hits.isEmpty ? null : hits.first);
  }

  geocoder.callMethod('geocode'.toJS, req, onDone.toJS);
  return gate.future.timeout(const Duration(seconds: 12));
}

List<OsmAddressHit> _hitsFromJs(JSAny? results, int limit) {
  final arr = _asArray(results);
  if (arr == null) return const [];
  final rows = arr.toDart;
  final out = <OsmAddressHit>[];
  for (var i = 0; i < rows.length && out.length < limit; i++) {
    final row = _asObject(rows[i]);
    if (row == null) continue;
    final formattedRaw = row.getProperty('formatted_address'.toJS);
    final formatted = formattedRaw == null || formattedRaw.isUndefinedOrNull
        ? ''
        : '${formattedRaw.dartify()}'.trim();
    final geometry = _asObject(row.getProperty('geometry'.toJS));
    if (geometry == null) continue;
    final loc = _asObject(geometry.getProperty('location'.toJS));
    if (loc == null) continue;
    final la = _asDouble(loc.callMethod<JSAny?>('lat'.toJS));
    final ln = _asDouble(loc.callMethod<JSAny?>('lng'.toJS));
    if (la == null || ln == null) continue;
    out.add(
      OsmAddressHit(
        displayName: formatted.isEmpty ? '$la, $ln' : formatted,
        lat: la,
        lng: ln,
      ),
    );
  }
  return out;
}

double? _asDouble(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) return null;
  final num = _asNumber(value);
  if (num != null) return num.toDartDouble;
  return double.tryParse('${value.dartify()}');
}
