import 'package:flutter/foundation.dart';

/// Plugin [google_maps_flutter] hanya Android, iOS, dan Web.
/// Di macOS / Windows / Linux widget-nya menampilkan
/// "TargetPlatform.macOS is not yet supported by the maps plugin".
bool get googleMapsPluginSupported {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
