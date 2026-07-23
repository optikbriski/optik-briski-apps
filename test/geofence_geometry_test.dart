import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/attendance/geofence_geometry.dart';
import 'package:optik_b_riski/shared/attendance/geofence_service.dart';

void main() {
  // Kotak kecil di sekitar Depok Bakung (~-6.3933, 106.8124).
  final poly = [
    const GeoPoint(-6.39340, 106.81220),
    const GeoPoint(-6.39340, 106.81260),
    const GeoPoint(-6.39310, 106.81260),
    const GeoPoint(-6.39310, 106.81220),
  ];

  test('contains: titik di dalam kotak', () {
    expect(GeofenceGeometry.contains(poly, -6.39329, 106.81240), isTrue);
  });

  test('contains: titik di luar kotak', () {
    expect(GeofenceGeometry.contains(poly, -6.39000, 106.81240), isFalse);
    expect(GeofenceGeometry.contains(poly, -6.39329, 106.82000), isFalse);
  });

  test('parsePolygon: lat/lng object + string JSON', () {
    final fromList = GeofenceGeometry.parsePolygon([
      {'lat': -6.1, 'lng': 106.8},
      {'lat': '-6.2', 'lng': '106.9'},
      {'lat': -6.3, 'lng': 106.7},
    ]);
    expect(fromList.length, 3);
    expect(fromList[1].lat, closeTo(-6.2, 1e-9));

    final fromJson = GeofenceGeometry.parsePolygon(
      '[{"lat":-6.1,"lng":106.8},{"lat":-6.2,"lng":106.9},{"lat":-6.3,"lng":106.7}]',
    );
    expect(fromJson.length, 3);
  });

  test('containsWithBuffer: dekat tepi lolos dengan buffer GPS kecil', () {
    // Sedikit di luar sisi selatan.
    const lat = -6.39341;
    const lng = 106.81240;
    expect(GeofenceGeometry.contains(poly, lat, lng), isFalse);
    expect(
      GeofenceGeometry.containsWithBuffer(poly, lat, lng, bufferMeters: 25),
      isTrue,
    );
  });

  test('distanceToPolygon: di dalam = 0', () {
    expect(
      GeofenceGeometry.distanceToPolygon(poly, -6.39329, 106.81240),
      0,
    );
  });

  test('containsWithBuffer: drift ~80 m tetap gagal dengan buffer ketat', () {
    // ~80 m ke selatan — jangan diloloskan seperti workaround Wi‑Fi.
    const lat = -6.39412;
    const lng = 106.81240;
    expect(GeofenceGeometry.contains(poly, lat, lng), isFalse);
    final dist = GeofenceGeometry.distanceToPolygon(poly, lat, lng);
    expect(dist, greaterThan(50));
    expect(dist, lessThan(120));
    expect(
      GeofenceGeometry.containsWithBuffer(poly, lat, lng, bufferMeters: 35),
      isFalse,
    );
  });

  test('accuracyBufferMeters: native ketat (cap 35)', () {
    expect(GeofenceService.accuracyBufferMeters(null), 8);
    expect(GeofenceService.accuracyBufferMeters(50), 20);
    expect(GeofenceService.accuracyBufferMeters(200), 35);
  });

  test('webHighAccuracyMeters: ambang GPS akurat web', () {
    expect(GeofenceService.webHighAccuracyMeters, 30);
  });

  test('GeoPoint: tidak tukar lat/lng', () {
    final p = GeoPoint.tryParse({'lat': -6.3933, 'lng': 106.8124});
    expect(p, isNotNull);
    expect(p!.lat, closeTo(-6.3933, 1e-9));
    expect(p.lng, closeTo(106.8124, 1e-9));
    // lat di luar rentang → ditolak (mencegah swap tersembunyi).
    expect(GeoPoint.tryParse({'lat': 106.8124, 'lng': -6.3933}), isNull);
  });
}
