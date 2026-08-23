import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../maps/geofence_workspace_map.dart';
import '../maps/google_maps_js.dart';
import '../theme.dart';
import 'logistics_tracking_service.dart';

/// Peta Google untuk giliran toko yang sedang dituju (setelah tiba di kota).
class LogisticsLiveGoogleMap extends StatefulWidget {
  const LogisticsLiveGoogleMap({
    super.key,
    required this.destination,
    this.height = 300,
  });

  final TokoGeo destination;
  final double height;

  @override
  State<LogisticsLiveGoogleMap> createState() => _LogisticsLiveGoogleMapState();
}

class _LogisticsLiveGoogleMapState extends State<LogisticsLiveGoogleMap> {
  late final Future<void> _ready = ensureGoogleMapsJs();

  @override
  Widget build(BuildContext context) {
    final dest = widget.destination;
    if (!hasGoogleMapsKey || !dest.hasCoords) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Text(
            'Peta Google belum siap (kunci atau koordinat toko).',
            style: TextStyle(color: OptikAdminTokens.slate, fontSize: 12),
          ),
        ),
      );
    }
    final point = LatLng(dest.latitude!, dest.longitude!);
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<void>(
          future: _ready,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done || snap.hasError) {
              return const Center(
                child: CircularProgressIndicator(color: OptikAdminTokens.ice),
              );
            }
            return gmaps.GoogleMap(
              initialCameraPosition: gmaps.CameraPosition(
                target: toGoogleLatLng(point),
                zoom: 14,
              ),
              mapType: gmaps.MapType.normal,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              zoomControlsEnabled: true,
              streetViewControlEnabled: false,
              mapTypeControlEnabled: false,
              webGestureHandling: gmaps.WebGestureHandling.greedy,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
              },
              markers: {
                gmaps.Marker(
                  markerId: const gmaps.MarkerId('dest'),
                  position: toGoogleLatLng(point),
                  infoWindow: gmaps.InfoWindow(
                    title: dest.label ?? dest.id,
                    snippet: 'Tujuan giliran ini',
                  ),
                ),
              },
            );
          },
        ),
      ),
    );
  }
}
