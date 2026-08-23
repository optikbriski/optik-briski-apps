import 'osm_address_search.dart';
import 'google_geocode_parse.dart';
import 'google_geocode_impl.dart'
    if (dart.library.html) 'google_geocode_web.dart'
    if (dart.library.js_interop) 'google_geocode_web.dart';

/// Geocode / reverse lewat Google Maps bila kuncinya ada.
class GoogleGeocode {
  GoogleGeocode._();

  static Future<List<OsmAddressHit>> search(
    String query, {
    int limit = 8,
  }) {
    return googleGeocodeSearch(query, limit: limit);
  }

  static Future<OsmAddressHit?> reverse(double lat, double lng) {
    return googleGeocodeReverse(lat, lng);
  }

  static List<OsmAddressHit> hitsFromRest(Map<String, dynamic> body) =>
      googleHitsFromRest(body);
}
