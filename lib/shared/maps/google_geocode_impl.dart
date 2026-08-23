import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'google_geocode_parse.dart';
import 'osm_address_search.dart';

Future<List<OsmAddressHit>> googleGeocodeSearch(
  String query, {
  int limit = 8,
}) async {
  final key = googleMapsApiKey.trim();
  if (key.isEmpty) return const [];
  final q = query.trim();
  if (q.isEmpty) return const [];
  final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
    'address': q,
    'components': 'country:ID',
    'language': 'id',
    'region': 'id',
    'key': key,
  });
  final res = await http.get(uri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw Exception('Google Geocode HTTP ${res.statusCode}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) return const [];
  final hits = googleHitsFromRest(Map<String, dynamic>.from(decoded));
  if (hits.length <= limit) return hits;
  return hits.take(limit).toList();
}

Future<OsmAddressHit?> googleGeocodeReverse(double lat, double lng) async {
  final key = googleMapsApiKey.trim();
  if (key.isEmpty) return null;
  final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
    'latlng': '$lat,$lng',
    'language': 'id',
    'key': key,
  });
  final res = await http.get(uri).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) {
    throw Exception('Google reverse HTTP ${res.statusCode}');
  }
  final decoded = jsonDecode(res.body);
  if (decoded is! Map) return null;
  final hits = googleHitsFromRest(Map<String, dynamic>.from(decoded));
  return hits.isEmpty ? null : hits.first;
}
