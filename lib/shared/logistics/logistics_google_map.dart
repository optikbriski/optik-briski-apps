import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../maps/google_pin_map.dart';
import '../theme.dart';
import 'logistics_tracking_service.dart';

/// Peta Google untuk giliran toko yang sedang dituju (setelah tiba di kota).
class LogisticsLiveGoogleMap extends StatelessWidget {
  const LogisticsLiveGoogleMap({
    super.key,
    required this.destination,
    this.height = 300,
  });

  final TokoGeo destination;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dest = destination;
    if (!hasGoogleMapsKey || !dest.hasCoords) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'Peta Google belum siap (kunci atau koordinat toko).',
            style: TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GooglePinMap(
        point: LatLng(dest.latitude!, dest.longitude!),
        zoom: 14,
        height: height,
        title: dest.label ?? dest.id,
        snippet: 'Tujuan giliran ini',
      ),
    );
  }
}
