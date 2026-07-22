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
    this.primaryLabel,
    this.secondaryLabel,
  });

  /// Label lengkap (satu baris) untuk feedback / fallback.
  final String displayName;

  /// Baris utama saran (jalan / nama tempat).
  final String? primaryLabel;

  /// Detail sekunder (kelurahan, kota, provinsi, kode pos).
  final String? secondaryLabel;

  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);

  String get title =>
      (primaryLabel != null && primaryLabel!.trim().isNotEmpty)
          ? primaryLabel!.trim()
          : displayName;

  String? get subtitle {
    final s = secondaryLabel?.trim();
    if (s == null || s.isEmpty) return null;
    // Hindari mengulang title di subtitle.
    if (s == title) return null;
    return s;
  }
}

/// Hasil parse koordinat dari teks / URL Google Maps.
class OsmParsedCoords {
  const OsmParsedCoords(this.lat, this.lng);

  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);
}

/// Parse lat/lng dari teks bebas: `lat, lng`, spasi, atau cuplikan URL Maps.
class OsmCoordinatePaste {
  OsmCoordinatePaste._();

  /// Mengembalikan null jika tidak ada pasangan koordinat valid.
  static OsmParsedCoords? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Cuplikan URL Google Maps yang sering disalin.
    final fromUrl = _fromGoogleMapsUrl(text);
    if (fromUrl != null) return fromUrl;

    // -6.915146, 107.613528 | -6.915146 107.613528 | -6.915146;107.613528
    final plain = RegExp(
      r'(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)',
    ).firstMatch(text);
    if (plain != null) {
      return _validated(
        double.tryParse(plain.group(1)!),
        double.tryParse(plain.group(2)!),
      );
    }
    return null;
  }

  static OsmParsedCoords? _fromGoogleMapsUrl(String text) {
    final patterns = <RegExp>[
      // .../@-6.91,107.61,18z
      RegExp(r'@(-?\d+\.?\d*),\s*(-?\d+\.?\d*)'),
      // ?q=-6.91,107.61  atau  &ll=-6.91,107.61
      RegExp(r'[?&](?:q|ll|query)=(-?\d+\.?\d*),\s*(-?\d+\.?\d*)'),
      // !3d-6.91!4d107.61
      RegExp(r'!3d(-?\d+\.?\d*)!4d(-?\d+\.?\d*)'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m == null) continue;
      final parsed = _validated(
        double.tryParse(m.group(1)!),
        double.tryParse(m.group(2)!),
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  static OsmParsedCoords? _validated(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90) return null;
    if (lng < -180 || lng > 180) return null;
    // Tolak 0,0 yang hampir selalu salah paste.
    if (lat == 0 && lng == 0) return null;
    return OsmParsedCoords(lat, lng);
  }
}

/// Pencarian alamat gratis berbasis OpenStreetMap.
///
/// Preferensi: Nominatim (`addressdetails`, `jsonv2`, `accept-language=id`).
/// Pada Flutter web, jika Nominatim gagal (CORS / rate-limit), otomatis
/// fallback ke Photon (CORS-friendly, bias lokasi).
class OsmAddressSearch {
  OsmAddressSearch._();

  static const userAgent = 'OptikBRiskiGeofence/1.0 (optik.briski.admin)';
  static const _bandungBias = LatLng(-6.9175, 107.6191);

  /// Cari alamat; [bias] mengarahkan Photon ke sekitar Bandung bila dipakai.
  ///
  /// Opsional [client]: tutup client dari pemanggil untuk membatalkan request.
  static Future<List<OsmAddressHit>> search(
    String query, {
    LatLng? bias,
    int limit = 8,
    http.Client? client,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final near = bias ?? _bandungBias;
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;

    try {
      try {
        return await _searchNominatim(httpClient, q, limit: limit);
      } catch (_) {
        // Web admin (Vercel) / CORS edge cases → Photon.
        return await _searchPhoton(httpClient, q, bias: near, limit: limit);
      }
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  /// Reverse geocode: koordinat → label alamat.
  /// Nominatim dulu, Photon bila gagal (CORS / rate-limit).
  static Future<OsmAddressHit?> reverse(
    LatLng point, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      try {
        return await _reverseNominatim(httpClient, point);
      } catch (_) {
        return await _reversePhoton(httpClient, point);
      }
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static Future<List<OsmAddressHit>> _searchNominatim(
    http.Client client,
    String query, {
    required int limit,
  }) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '$limit',
      'countrycodes': 'id',
      'addressdetails': '1',
      'accept-language': 'id',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': 'id',
      // Browser menolak set User-Agent kustom; di native/desktop tetap terkirim.
      if (!kIsWeb) 'User-Agent': userAgent,
    };

    final res = await client.get(uri, headers: headers).timeout(
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
      if (lat == null || lng == null) continue;

      final labels = _nominatimLabels(Map<String, dynamic>.from(raw));
      if (labels.displayName.isEmpty) continue;
      out.add(
        OsmAddressHit(
          displayName: labels.displayName,
          primaryLabel: labels.primary,
          secondaryLabel: labels.secondary,
          lat: lat,
          lng: lng,
        ),
      );
    }
    return out;
  }

  static Future<List<OsmAddressHit>> _searchPhoton(
    http.Client client,
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

    final res = await client.get(uri, headers: headers).timeout(
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

      final labels = _photonLabels(Map<String, dynamic>.from(props));
      if (labels.displayName.isEmpty) continue;
      out.add(
        OsmAddressHit(
          displayName: labels.displayName,
          primaryLabel: labels.primary,
          secondaryLabel: labels.secondary,
          lat: lat,
          lng: lng,
        ),
      );
    }
    return out;
  }

  static Future<OsmAddressHit?> _reverseNominatim(
    http.Client client,
    LatLng point,
  ) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'format': 'jsonv2',
      'addressdetails': '1',
      'accept-language': 'id',
      'zoom': '18',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': 'id',
      if (!kIsWeb) 'User-Agent': userAgent,
    };

    final res = await client.get(uri, headers: headers).timeout(
          const Duration(seconds: 12),
        );
    if (res.statusCode != 200) {
      throw Exception('Nominatim reverse HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final raw = Map<String, dynamic>.from(decoded);
    final lat = double.tryParse('${raw['lat']}') ?? point.latitude;
    final lng = double.tryParse('${raw['lon']}') ?? point.longitude;
    final labels = _nominatimLabels(raw);
    if (labels.displayName.isEmpty) return null;
    return OsmAddressHit(
      displayName: labels.displayName,
      primaryLabel: labels.primary,
      secondaryLabel: labels.secondary,
      lat: lat,
      lng: lng,
    );
  }

  static Future<OsmAddressHit?> _reversePhoton(
    http.Client client,
    LatLng point,
  ) async {
    final uri = Uri.https('photon.komoot.io', '/reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'lang': 'id',
    });

    final headers = <String, String>{
      'Accept': 'application/json',
      if (!kIsWeb) 'User-Agent': userAgent,
    };

    final res = await client.get(uri, headers: headers).timeout(
          const Duration(seconds: 12),
        );
    if (res.statusCode != 200) {
      throw Exception('Photon reverse HTTP ${res.statusCode}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final features = decoded['features'];
    if (features is! List || features.isEmpty) return null;
    final raw = features.first;
    if (raw is! Map) return null;
    final geometry = raw['geometry'];
    final props = raw['properties'];
    if (props is! Map) return null;

    var lat = point.latitude;
    var lng = point.longitude;
    if (geometry is Map) {
      final coords = geometry['coordinates'];
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num?)?.toDouble() ?? lng;
        lat = (coords[1] as num?)?.toDouble() ?? lat;
      }
    }

    final labels = _photonLabels(Map<String, dynamic>.from(props));
    if (labels.displayName.isEmpty) return null;
    return OsmAddressHit(
      displayName: labels.displayName,
      primaryLabel: labels.primary,
      secondaryLabel: labels.secondary,
      lat: lat,
      lng: lng,
    );
  }

  static _AddressLabels _nominatimLabels(Map<String, dynamic> raw) {
    final fallback = (raw['display_name'] ?? '').toString().trim();
    final address = raw['address'];
    if (address is! Map) {
      return _AddressLabels(displayName: fallback, primary: fallback);
    }
    final addr = Map<String, dynamic>.from(address);

    final name = _firstNonEmpty([
      raw['name'],
      addr['amenity'],
      addr['shop'],
      addr['building'],
      addr['tourism'],
      addr['office'],
    ]);

    final road = _firstNonEmpty([
      addr['road'],
      addr['pedestrian'],
      addr['path'],
      addr['footway'],
      addr['residential'],
    ]);
    final house = _str(addr['house_number']);

    final suburb = _firstNonEmpty([
      addr['suburb'],
      addr['village'],
      addr['neighbourhood'],
      addr['neighborhood'],
      addr['hamlet'],
      addr['quarter'],
    ]);
    final city = _firstNonEmpty([
      addr['city'],
      addr['town'],
      addr['municipality'],
      addr['county'], // sering = kabupaten/kota di ID
      addr['city_district'],
    ]);
    final state = _firstNonEmpty([addr['state'], addr['region']]);
    final postcode = _str(addr['postcode']);

    String? primary;
    if (road != null) {
      final street = house != null ? '$road No. $house' : road;
      primary = (name != null && !_sameIgnoreCase(name, road))
          ? '$name, $street'
          : street;
    } else if (name != null) {
      primary = name;
    } else if (suburb != null) {
      primary = suburb;
    }

    final secondaryParts = <String>[
      if (suburb != null &&
          (primary == null || !primary.toLowerCase().contains(suburb.toLowerCase())))
        suburb,
      if (city != null) city,
      if (state != null) state,
      if (postcode != null) postcode,
    ];
    final secondary = secondaryParts.isEmpty ? null : secondaryParts.join(', ');

    final display = [
      if (primary != null && primary.isNotEmpty) primary,
      if (secondary != null && secondary.isNotEmpty) secondary,
    ].join(', ');

    if (display.trim().isEmpty) {
      return _AddressLabels(displayName: fallback, primary: fallback);
    }
    return _AddressLabels(
      displayName: display,
      primary: primary ?? display,
      secondary: secondary,
    );
  }

  static _AddressLabels _photonLabels(Map<String, dynamic> props) {
    final name = _str(props['name']);
    final street = _str(props['street']);
    final house = _str(props['housenumber']);
    final district = _firstNonEmpty([
      props['district'],
      props['locality'],
      props['suburb'],
    ]);
    final city = _str(props['city']);
    final state = _str(props['state']);
    final postcode = _str(props['postcode']);
    final country = _str(props['country']);

    String? primary;
    if (street != null) {
      final road = house != null ? '$street No. $house' : street;
      primary = (name != null && !_sameIgnoreCase(name, street))
          ? '$name, $road'
          : road;
    } else if (name != null) {
      primary = name;
    }

    final secondaryParts = <String>[
      if (district != null &&
          (primary == null ||
              !primary.toLowerCase().contains(district.toLowerCase())))
        district,
      if (city != null) city,
      if (state != null) state,
      if (postcode != null) postcode,
      if (country != null && country.toLowerCase() != 'indonesia') country,
    ];
    final secondary = secondaryParts.isEmpty ? null : secondaryParts.join(', ');

    final display = [
      if (primary != null && primary.isNotEmpty) primary,
      if (secondary != null && secondary.isNotEmpty) secondary,
    ].join(', ');

    if (display.trim().isEmpty) {
      // Fallback kasar bila properti minim.
      final parts = <String>[
        for (final key in [
          'name',
          'street',
          'housenumber',
          'district',
          'city',
          'state',
          'postcode',
          'country',
        ])
          if (_str(props[key]) != null) _str(props[key])!,
      ];
      final joined = parts.toSet().join(', ');
      return _AddressLabels(displayName: joined, primary: joined);
    }

    return _AddressLabels(
      displayName: display,
      primary: primary ?? display,
      secondary: secondary,
    );
  }

  static String? _str(Object? v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final s = _str(v);
      if (s != null) return s;
    }
    return null;
  }

  static bool _sameIgnoreCase(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}

class _AddressLabels {
  const _AddressLabels({
    required this.displayName,
    this.primary,
    this.secondary,
  });

  final String displayName;
  final String? primary;
  final String? secondary;
}
