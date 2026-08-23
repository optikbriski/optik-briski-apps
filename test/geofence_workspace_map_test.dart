import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:optik_b_riski/shared/maps/geofence_workspace_map.dart';

void main() {
  test('geoBoundsFromPoints pads a single-point span', () {
    final b = geoBoundsFromPoints(const [LatLng(-6.9, 107.6), LatLng(-6.9, 107.6)]);
    expect(b.south, lessThan(b.north));
    expect(b.west, lessThan(b.east));
  });

  test('geoBoundsFromPoints covers the corners', () {
    final b = geoBoundsFromPoints(const [
      LatLng(-6.92, 107.60),
      LatLng(-6.90, 107.63),
    ]);
    expect(b.south, closeTo(-6.92, 0.00001));
    expect(b.north, closeTo(-6.90, 0.00001));
    expect(b.west, closeTo(107.60, 0.00001));
    expect(b.east, closeTo(107.63, 0.00001));
  });
}
