/// Titik lat/lng WGS84 untuk geofence (tanpa dependensi maps).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  static GeoPoint? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }
}

class GeofenceGeometry {
  GeofenceGeometry._();

  /// Parse jsonb array → list titik (harapkan 4 untuk mode polygon).
  static List<GeoPoint> parsePolygon(dynamic raw) {
    if (raw is! List) return const [];
    final out = <GeoPoint>[];
    for (final item in raw) {
      final p = GeoPoint.tryParse(item);
      if (p != null) out.add(p);
    }
    return out;
  }

  static List<Map<String, dynamic>> polygonToJson(List<GeoPoint> pts) =>
      pts.map((e) => e.toJson()).toList();

  /// Ray casting point-in-polygon (cocok untuk area toko kecil).
  static bool contains(List<GeoPoint> polygon, double lat, double lng) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].lng;
      final yi = polygon[i].lat;
      final xj = polygon[j].lng;
      final yj = polygon[j].lat;
      final intersect = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Centroid kasar untuk kamera / fallback circle center.
  static GeoPoint? centroid(List<GeoPoint> polygon) {
    if (polygon.isEmpty) return null;
    var lat = 0.0;
    var lng = 0.0;
    for (final p in polygon) {
      lat += p.lat;
      lng += p.lng;
    }
    return GeoPoint(lat / polygon.length, lng / polygon.length);
  }
}
