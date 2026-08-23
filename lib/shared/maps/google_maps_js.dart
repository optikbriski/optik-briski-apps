import 'google_maps_js_stub.dart'
    if (dart.library.html) 'google_maps_js_web.dart'
    if (dart.library.js_interop) 'google_maps_js_web.dart';

/// Muat Maps JavaScript API bila kuncinya ada (no-op di IO / tanpa kunci).
Future<void> ensureGoogleMapsJs() => ensureGoogleMapsJsImpl();

bool get googleMapsJsReady => googleMapsJsReadyImpl;
