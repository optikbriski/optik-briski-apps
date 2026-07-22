import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Satu hasil geocode (OSM Nominatim / Photon).
class OsmAddressHit {
  const OsmAddressHit({
    required this.displayName,
    required this.lat,
    required this.lng,
  });

  final String displayName;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);
}

/// Pencarian alamat gratis berbasis OpenStreetMap.
///
/// Preferensi: Nominatim (dengan User-Agent). Pada Flutter web, jika Nominatim
/// gagal (CORS / rate-limit), otomatis fallback ke Photon (CORS-friendly).
class OsmAddressSearch {
  OsmAddressSearch._();

  static const userAgent = 'OptikBRiskiGeofence/1.0 (optik.briski.admin)';
  static const _bandungBias = LatLng(-6.9175, 107.6191);

  /// Cari alamat; [bias] mengarahkan Photon ke sekitar Bandung bila dipakai.
  static Future<List<OsmAddressHit>> search(
    String query, {
    LatLng? bias,
    int limit = 5,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final near = bias ?? _bandungBias;

    try {
      return await _searchNominatim(q, limit: limit);
    } catch (_) {
      // Web admin (Vercel) / CORS edge cases → Photon.
      return await _searchPhoton(q, bias: near, limit: limit);
    }
  }

  static Future<List<OsmAddressHit>> _searchNominatim(
    String query, {
    required int limit,
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '$limit',
      'countrycodes': 'id',
      'addressdetails': '0',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      // Browser menolak set User-Agent kustom; di native/desktop tetap terkirim.
      if (!kIsWeb) 'User-Agent': userAgent,
    };

    final res = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 12),
        );
    if (res.statusCode != 200) {
      throw Exception('Nominatim HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];

    final out = <OsmAddressHit>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final lat = double.tryParse('${raw['lat']}');
      final lng = double.tryParse('${raw['lon']}');
      final name = (raw['display_name'] ?? '').toString().trim();
      if (lat == null || lng == null || name.isEmpty) continue;
      out.add(OsmAddressHit(displayName: name, lat: lat, lng: lng));
    }
    return out;
  }

  static Future<List<OsmAddressHit>> _searchPhoton(
    String query, {
    required LatLng bias,
    required int limit,
  }) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '$limit',
      'lat': '${bias.latitude}',
      'lon': '${bias.longitude}',
      'lang': 'id',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': userAgent,
    };

    final res = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 12),
        );
    if (res.statusCode != 200) {
      throw Exception('Photon HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final out = <OsmAddressHit>[];
    for (final raw in features) {
      if (raw is! Map) continue;
      final geometry = raw['geometry'];
      final props = raw['properties'];
      if (geometry is! Map || props is! Map) continue;
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final lng = (coords[0] as num?)?.toDouble();
      final lat = (coords[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      // Filter kasar ke Indonesia bila countrycode tersedia.
      final cc = (props['countrycode'] ?? '').toString().toUpperCase();
      if (cc.isNotEmpty && cc != 'ID') continue;

      final name = _photonLabel(props);
      if (name.isEmpty) continue;
      out.add(OsmAddressHit(displayName: name, lat: lat, lng: lng));
    }
    return out;
  }

  static String _photonLabel(Map props) {
    final parts = <String>[
      for (final key in [
        'name',
        'street',
        'housenumber',
        'district',
        'city',
        'state',
        'country',
      ])
        if ((props[key] ?? '').toString().trim().isNotEmpty)
          (props[key] as Object).toString().trim(),
    ];
    // Hindari "street housenumber" terpisah jelek: rapikan sederhana.
    return parts.toSet().join(', ');
  }
}
