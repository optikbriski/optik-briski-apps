import 'dart:convert';
import 'dart:math' as math;

/// Titik lat/lng WGS84 untuk geofence (tanpa dependensi maps).
class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  static GeoPoint? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final lat = _asDouble(raw['lat'] ?? raw['latitude']);
    final lng = _asDouble(raw['lng'] ?? raw['longitude'] ?? raw['lon']);
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return GeoPoint(lat, lng);
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}

class GeofenceGeometry {
  GeofenceGeometry._();

  /// Parse jsonb array → list titik (harapkan 4 untuk mode polygon).
  /// Menerima List, atau String JSON array.
  static List<GeoPoint> parsePolygon(dynamic raw) {
    dynamic data = raw;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return const [];
      try {
        data = jsonDecode(s);
      } catch (_) {
        return const [];
      }
    }
    if (data is! List) return const [];
    final out = <GeoPoint>[];
    for (final item in data) {
      final p = GeoPoint.tryParse(item);
      if (p != null) out.add(p);
    }
    return out;
  }

  static List<Map<String, dynamic>> polygonToJson(List<GeoPoint> pts) =>
      pts.map((e) => e.toJson()).toList();

  /// Ray casting point-in-polygon (x=lng, y=lat; cocok untuk area toko kecil).
  static bool contains(List<GeoPoint> polygon, double lat, double lng) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].lng;
      final yi = polygon[i].lat;
      final xj = polygon[j].lng;
      final yj = polygon[j].lat;
      final intersect = ((yi > lat) != (yj > lat)) &&
          (lng <
              (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// True jika di dalam, atau lingkaran buffer bersinggungan dengan polygon
  /// (jarak ke tepi ≤ [bufferMeters]) — untuk ketidakpastian GPS nyata.
  static bool containsWithBuffer(
    List<GeoPoint> polygon,
    double lat,
    double lng, {
    double bufferMeters = 0,
  }) {
    if (contains(polygon, lat, lng)) return true;
    if (bufferMeters <= 0) return false;
    return distanceToPolygon(polygon, lat, lng) <= bufferMeters;
  }

  /// Jarak terdekat ke tepi polygon (0 jika di dalam). Estimasi lokal meter.
  static double distanceToPolygon(
    List<GeoPoint> polygon,
    double lat,
    double lng,
  ) {
    if (polygon.length < 3) return double.infinity;
    if (contains(polygon, lat, lng)) return 0;
    var min = double.infinity;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final d = _distanceToSegmentMeters(lat, lng, a, b);
      if (d < min) min = d;
    }
    return min;
  }

  /// Alias lama — pakai [distanceToPolygon].
  static double minDistanceMeters(
    List<GeoPoint> polygon,
    double lat,
    double lng,
  ) =>
      distanceToPolygon(polygon, lat, lng);

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

  static double _distanceToSegmentMeters(
    double lat,
    double lng,
    GeoPoint a,
    GeoPoint b,
  ) {
    // Equirectangular lokal di sekitar titik uji (cukup untuk toko ~puluhan meter).
    final midLat = lat * math.pi / 180;
    final mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(midLat).abs().clamp(1e-6, 1.0);

    final ax = (a.lng - lng) * mPerDegLng;
    final ay = (a.lat - lat) * mPerDegLat;
    final bx = (b.lng - lng) * mPerDegLng;
    final by = (b.lat - lat) * mPerDegLat;
    final abx = bx - ax;
    final aby = by - ay;
    final ab2 = abx * abx + aby * aby;
    if (ab2 < 1e-6) {
      return math.sqrt(ax * ax + ay * ay);
    }
    // Proyeksi dari titik (0,0) ke segmen A→B di ruang lokal.
    var t = (-ax * abx + -ay * aby) / ab2;
    t = t.clamp(0.0, 1.0);
    final dx = ax + t * abx;
    final dy = ay + t * aby;
    return math.sqrt(dx * dx + dy * dy);
  }
}
