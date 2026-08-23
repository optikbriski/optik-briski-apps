// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;
import 'dart:js_util' as jsu;

import '../config.dart';
import 'google_maps_js.dart';
import 'osm_address_search.dart';

Future<List<OsmAddressHit>> googleGeocodeSearch(
  String query, {
  int limit = 8,
}) async {
  final q = query.trim();
  if (q.isEmpty || googleMapsApiKey.trim().isEmpty) return const [];
  await ensureGoogleMapsJs();
  if (!googleMapsJsReady) return const [];
  final maps = (js.context['google'] as js.JsObject)['maps'] as js.JsObject;
  final geocoder = js.JsObject(maps['Geocoder']);
  final gate = Completer<List<OsmAddressHit>>();
  geocoder.callMethod('geocode', [
    js.JsObject.jsify({
      'address': q,
      'componentRestrictions': {'country': 'ID'},
      'language': 'id',
      'region': 'id',
    }),
    jsu.allowInterop((dynamic results, dynamic status) {
      if (gate.isCompleted) return;
      if ('$status' != 'OK') {
        gate.complete(const []);
        return;
      }
      gate.complete(_hitsFromJs(results, limit));
    }),
  ]);
  return gate.future.timeout(const Duration(seconds: 12));
}

Future<OsmAddressHit?> googleGeocodeReverse(double lat, double lng) async {
  if (googleMapsApiKey.trim().isEmpty) return null;
  await ensureGoogleMapsJs();
  if (!googleMapsJsReady) return null;
  final maps = (js.context['google'] as js.JsObject)['maps'] as js.JsObject;
  final latLng = js.JsObject(maps['LatLng'], [lat, lng]);
  final geocoder = js.JsObject(maps['Geocoder']);
  final gate = Completer<OsmAddressHit?>();
  geocoder.callMethod('geocode', [
    js.JsObject.jsify({'location': latLng, 'language': 'id'}),
    jsu.allowInterop((dynamic results, dynamic status) {
      if (gate.isCompleted) return;
      if ('$status' != 'OK') {
        gate.complete(null);
        return;
      }
      final hits = _hitsFromJs(results, 1);
      gate.complete(hits.isEmpty ? null : hits.first);
    }),
  ]);
  return gate.future.timeout(const Duration(seconds: 12));
}

List<OsmAddressHit> _hitsFromJs(dynamic results, int limit) {
  if (results is! js.JsArray) return const [];
  final out = <OsmAddressHit>[];
  for (var i = 0; i < results.length && out.length < limit; i++) {
    final row = results[i];
    if (row is! js.JsObject) continue;
    final formatted = '${row['formatted_address'] ?? ''}'.trim();
    final geometry = row['geometry'];
    if (geometry is! js.JsObject) continue;
    final loc = geometry['location'];
    if (loc is! js.JsObject) continue;
    final lat = loc.callMethod('lat');
    final lng = loc.callMethod('lng');
    final la = (lat is num) ? lat.toDouble() : double.tryParse('$lat');
    final ln = (lng is num) ? lng.toDouble() : double.tryParse('$lng');
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
