import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'logistics_tracking_service.dart';

/// Peta gratis OpenStreetMap: marker toko + polyline rute paket terpilih.
class LogisticsOsmMap extends StatefulWidget {
  const LogisticsOsmMap({
    super.key,
    required this.toko,
    this.selectedMove,
    this.height = 320,
  });

  final List<TokoGeo> toko;
  final Map<String, dynamic>? selectedMove;
  final double height;

  @override
  State<LogisticsOsmMap> createState() => _LogisticsOsmMapState();
}

class _LogisticsOsmMapState extends State<LogisticsOsmMap> {
  final _mapCtrl = MapController();

  TokoGeo? _findToko(String? id) {
    if (id == null || id.isEmpty) return null;
    final key = id.toUpperCase();
    for (final t in widget.toko) {
      if (t.id.toUpperCase() == key) return t;
    }
    return null;
  }

  LatLng? _centerFallback() {
    final withCoords = widget.toko.where((t) => t.hasCoords).toList();
    if (withCoords.isEmpty) {
      // Bandung-ish default (area Optik)
      return const LatLng(-6.9175, 107.6191);
    }
    double lat = 0, lng = 0;
    for (final t in withCoords) {
      lat += t.latitude!;
      lng += t.longitude!;
    }
    return LatLng(lat / withCoords.length, lng / withCoords.length);
  }

  @override
  void didUpdateWidget(covariant LogisticsOsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final move = widget.selectedMove;
    if (move == null) return;
    if (oldWidget.selectedMove?['id'] == move['id']) return;
    final dari = _findToko(move['dari_lokasi']?.toString());
    final ke = _findToko(move['ke_lokasi']?.toString());
    if (dari?.hasCoords == true && ke?.hasCoords == true) {
      final bounds = LatLngBounds(
        LatLng(dari!.latitude!, dari.longitude!),
        LatLng(ke!.latitude!, ke.longitude!),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapCtrl.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
          );
        } catch (_) {}
      });
    } else if (ke?.hasCoords == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapCtrl.move(LatLng(ke!.latitude!, ke.longitude!), 12);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _centerFallback()!;
    final dari = _findToko(widget.selectedMove?['dari_lokasi']?.toString());
    final ke = _findToko(widget.selectedMove?['ke_lokasi']?.toString());
    final routePoints = <LatLng>[];
    if (dari?.hasCoords == true && ke?.hasCoords == true) {
      routePoints.add(LatLng(dari!.latitude!, dari.longitude!));
      routePoints.add(LatLng(ke!.latitude!, ke.longitude!));
    }

    final markers = <Marker>[];
    for (final t in widget.toko.where((e) => e.hasCoords)) {
      final isDari = dari?.id.toUpperCase() == t.id.toUpperCase();
      final isKe = ke?.id.toUpperCase() == t.id.toUpperCase();
      final color = isDari
          ? OptikAdminTokens.warning
          : (isKe ? OptikAdminTokens.success : OptikAdminTokens.accentSoft);
      markers.add(
        Marker(
          point: LatLng(t.latitude!, t.longitude!),
          width: 44,
          height: 44,
          child: Tooltip(
            message: t.id,
            child: Icon(
              isDari
                  ? Icons.flight_takeoff_rounded
                  : (isKe
                      ? Icons.flag_rounded
                      : Icons.store_mall_directory_rounded),
              color: color,
              size: isDari || isKe ? 34 : 26,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 6),
              ],
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(OptikAdminTokens.radiusMd),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 10.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.optikbriski.admin',
                  maxZoom: 19,
                ),
                if (routePoints.length == 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: OptikAdminTokens.accent,
                        strokeWidth: 4,
                        borderColor: Colors.white54,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  routePoints.length == 2
                      ? '${dari!.id} → ${ke!.id} (garis lurus)'
                      : 'OpenStreetMap · tanpa live GPS',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
