import 'osm_address_search.dart';

List<OsmAddressHit> googleHitsFromRest(Map<String, dynamic> body) {
  final status = '${body['status'] ?? ''}';
  if (status != 'OK' && status != 'ZERO_RESULTS') return const [];
  final raw = body['results'];
  if (raw is! List) return const [];
  final out = <OsmAddressHit>[];
  for (final row in raw) {
    if (row is! Map) continue;
    final hit = googleHitFromResult(Map<String, dynamic>.from(row));
    if (hit != null) out.add(hit);
  }
  return out;
}

OsmAddressHit? googleHitFromResult(Map<String, dynamic> row) {
  final formatted = '${row['formatted_address'] ?? ''}'.trim();
  final geometry = row['geometry'];
  if (geometry is! Map) return null;
  final loc = geometry['location'];
  if (loc is! Map) return null;
  final lat = (loc['lat'] as num?)?.toDouble();
  final lng = (loc['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return null;

  final comps = row['address_components'];
  String? road;
  String? house;
  String? city;
  String? admin;
  if (comps is List) {
    for (final raw in comps) {
      if (raw is! Map) continue;
      final types = raw['types'];
      if (types is! List) continue;
      final names = types.map((e) => '$e').toSet();
      final long = '${raw['long_name'] ?? ''}'.trim();
      if (long.isEmpty) continue;
      if (names.contains('route')) road = long;
      if (names.contains('street_number')) house = long;
      if (names.contains('locality') ||
          names.contains('administrative_area_level_2')) {
        city ??= long;
      }
      if (names.contains('administrative_area_level_1')) admin = long;
    }
  }
  final primary = [
    if (road != null) house != null ? '$road No. $house' : road,
  ].join();
  final secondary = [
    if (city != null) city,
    if (admin != null) admin,
  ].join(', ');
  return OsmAddressHit(
    displayName: formatted.isEmpty
        ? (primary.isNotEmpty ? primary : '$lat, $lng')
        : formatted,
    primaryLabel: primary.isNotEmpty ? primary : null,
    secondaryLabel: secondary.isNotEmpty ? secondary : null,
    lat: lat,
    lng: lng,
  );
}
