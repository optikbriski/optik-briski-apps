import 'package:flutter_test/flutter_test.dart';
import 'package:optik_b_riski/shared/config.dart';
import 'package:optik_b_riski/shared/maps/google_maps_js.dart';

void main() {
  test('VM / tes: loader Maps JS no-op, tidak meledak', () async {
    expect(googleMapsJsReady, isFalse);
    await ensureGoogleMapsJs();
    expect(googleMapsJsReady, isFalse);
  });

  test('kunci Google dibaca dari dart-define yang sama', () {
    expect(hasGoogleMapsKey, googleMapsApiKey.trim().isNotEmpty);
  });
}
