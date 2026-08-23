import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/maps/google_geocode_parse.dart';

void main() {
  test('googleHitsFromRest reads Geocoding JSON', () {
    final hits = googleHitsFromRest({
      'status': 'OK',
      'results': [
        {
          'formatted_address': 'Jl. Malioboro, Yogyakarta',
          'geometry': {
            'location': {'lat': -7.792, 'lng': 110.366},
          },
        },
      ],
    });
    expect(hits, hasLength(1));
    expect(hits.single.displayName, 'Jl. Malioboro, Yogyakarta');
    expect(hits.single.lat, closeTo(-7.792, 0.0001));
    expect(hits.single.lng, closeTo(110.366, 0.0001));
  });

  test('googleHitsFromRest ignores ZERO_RESULTS', () {
    expect(
      googleHitsFromRest({'status': 'ZERO_RESULTS', 'results': <Object>[]}),
      isEmpty,
    );
  });
}
