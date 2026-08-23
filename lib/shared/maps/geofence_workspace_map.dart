import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'google_maps_js.dart';

/// Kotak lintang/bujur untuk fit kamera (Google atau OSM).
class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;
}

GeoBounds geoBoundsFromPoints(List<LatLng> points) {
  var south = points.first.latitude;
  var north = points.first.latitude;
  var west = points.first.longitude;
  var east = points.first.longitude;
  for (final p in points.skip(1)) {
    if (p.latitude < south) south = p.latitude;
    if (p.latitude > north) north = p.latitude;
    if (p.longitude < west) west = p.longitude;
    if (p.longitude > east) east = p.longitude;
  }
  // Google newLatLngBounds menolak titik yang sama persis.
  if (south == north) {
    south -= 0.00005;
    north += 0.00005;
  }
  if (west == east) {
    west -= 0.00005;
    east += 0.00005;
  }
  return GeoBounds(south: south, west: west, north: north, east: east);
}

gmaps.LatLng toGoogleLatLng(LatLng p) =>
    gmaps.LatLng(p.latitude, p.longitude);

LatLng fromGoogleLatLng(gmaps.LatLng p) => LatLng(p.latitude, p.longitude);

/// Satu gagang untuk geser kamera OSM (flutter_map) atau Google Maps.
class GeofenceMapHandle {
  GeofenceMapHandle(this.osm);

  final MapController osm;
  gmaps.GoogleMapController? google;
  LatLng? googleCenter;
  double? googleZoom;

  bool get usingGoogle => google != null;

  LatLng get center {
    final g = googleCenter;
    if (g != null) return g;
    try {
      return osm.camera.center;
    } catch (_) {
      return const LatLng(-6.9175, 107.6191);
    }
  }

  double get zoom {
    final z = googleZoom;
    if (z != null) return z;
    try {
      return osm.camera.zoom;
    } catch (_) {
      return 18;
    }
  }

  Future<void> move(LatLng point, double zoom) async {
    googleCenter = point;
    googleZoom = zoom;
    final g = google;
    if (g != null) {
      await g.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          toGoogleLatLng(point),
          zoom.clamp(3.0, 21.0),
        ),
      );
      return;
    }
    try {
      osm.move(point, zoom);
    } catch (_) {}
  }

  Future<void> fit(
    List<LatLng> points, {
    double padding = 80,
    double maxZoom = 21,
  }) async {
    if (points.isEmpty) return;
    if (points.length == 1) {
      await move(points.first, maxZoom);
      return;
    }
    final b = geoBoundsFromPoints(points);
    final g = google;
    if (g != null) {
      await g.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(b.south, b.west),
            northeast: gmaps.LatLng(b.north, b.east),
          ),
          padding,
        ),
      );
      return;
    }
    try {
      osm.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(b.south, b.west),
            LatLng(b.north, b.east),
          ),
          padding: EdgeInsets.all(padding),
          maxZoom: maxZoom,
        ),
      );
    } catch (_) {}
  }

  void dispose() {
    osm.dispose();
  }
}

/// Kanvas Google Maps untuk editor geofence (web + Android + iOS).
class GoogleGeofenceMap extends StatefulWidget {
  const GoogleGeofenceMap({
    super.key,
    required this.handle,
    required this.satellite,
    required this.initialCenter,
    required this.initialZoom,
    required this.interactionLocked,
    required this.onTap,
    required this.onCameraIdle,
    required this.onGoogleReady,
    required this.onFailed,
    this.circleCenter,
    this.circleRadiusMeters,
    this.polygon = const [],
    this.previewTarget,
    this.selectedCorner,
    required this.onCenterDragStart,
    required this.onCenterDrag,
    required this.onCenterDragEnd,
    required this.onCornerDragStart,
    required this.onCornerDrag,
    required this.onCornerDragEnd,
    required this.onCornerTap,
  });

  final GeofenceMapHandle handle;
  final bool satellite;
  final LatLng initialCenter;
  final double initialZoom;
  final bool interactionLocked;
  final ValueChanged<LatLng> onTap;
  final VoidCallback onCameraIdle;
  final VoidCallback onGoogleReady;
  final VoidCallback onFailed;
  final LatLng? circleCenter;
  final double? circleRadiusMeters;
  final List<LatLng> polygon;
  final LatLng? previewTarget;
  final int? selectedCorner;
  final VoidCallback onCenterDragStart;
  final ValueChanged<LatLng> onCenterDrag;
  final VoidCallback onCenterDragEnd;
  final ValueChanged<int> onCornerDragStart;
  final void Function(int index, LatLng point) onCornerDrag;
  final VoidCallback onCornerDragEnd;
  final ValueChanged<int> onCornerTap;

  @override
  State<GoogleGeofenceMap> createState() => _GoogleGeofenceMapState();
}

class _GoogleGeofenceMapState extends State<GoogleGeofenceMap> {
  late final Future<void> _ready = _boot();

  Future<void> _boot() async {
    try {
      await ensureGoogleMapsJs();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ensureGoogleMapsJs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onFailed();
          });
          return const Center(
            child: CircularProgressIndicator(color: OptikAdminTokens.ice),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: OptikAdminTokens.ice),
          );
        }
        return gmaps.GoogleMap(
          initialCameraPosition: gmaps.CameraPosition(
            target: toGoogleLatLng(widget.initialCenter),
            zoom: widget.initialZoom.clamp(3.0, 21.0),
          ),
          mapType:
              widget.satellite ? gmaps.MapType.hybrid : gmaps.MapType.normal,
          minMaxZoomPreference: const gmaps.MinMaxZoomPreference(3, 21),
          rotateGesturesEnabled: false,
          scrollGesturesEnabled: !widget.interactionLocked,
          zoomGesturesEnabled: !widget.interactionLocked,
          tiltGesturesEnabled: false,
          myLocationButtonEnabled: false,
          myLocationEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: true,
          compassEnabled: true,
          mapTypeControlEnabled: false,
          streetViewControlEnabled: false,
          fullscreenControlEnabled: false,
          webGestureHandling: gmaps.WebGestureHandling.greedy,
          webCameraControlEnabled: true,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
          },
          circles: _circles(),
          polygons: _polygons(),
          polylines: _polylines(),
          markers: _markers(),
          onMapCreated: (c) {
            widget.handle.google = c;
            widget.handle.googleCenter = widget.initialCenter;
            widget.handle.googleZoom = widget.initialZoom;
            widget.onGoogleReady();
          },
          onTap: (p) => widget.onTap(fromGoogleLatLng(p)),
          onCameraMove: (pos) {
            widget.handle.googleCenter = fromGoogleLatLng(pos.target);
            widget.handle.googleZoom = pos.zoom;
          },
          onCameraIdle: widget.onCameraIdle,
        );
      },
    );
  }

  Set<gmaps.Circle> _circles() {
    final c = widget.circleCenter;
    final r = widget.circleRadiusMeters;
    if (c == null || r == null) return {};
    return {
      gmaps.Circle(
        circleId: const gmaps.CircleId('fence'),
        center: toGoogleLatLng(c),
        radius: r,
        fillColor: OptikAdminTokens.ice.withOpacity(0.22),
        strokeColor: OptikAdminTokens.ice,
        strokeWidth: 3,
        consumeTapEvents: false,
      ),
    };
  }

  Set<gmaps.Polygon> _polygons() {
    if (widget.polygon.length < 3) return {};
    return {
      gmaps.Polygon(
        polygonId: const gmaps.PolygonId('fence'),
        points: widget.polygon.map(toGoogleLatLng).toList(),
        fillColor: OptikAdminTokens.ice.withOpacity(0.22),
        strokeColor: OptikAdminTokens.ice,
        strokeWidth: 3,
      ),
    };
  }

  Set<gmaps.Polyline> _polylines() {
    if (widget.polygon.length < 2) return {};
    final pts = <gmaps.LatLng>[
      ...widget.polygon.map(toGoogleLatLng),
      if (widget.polygon.length >= 3) toGoogleLatLng(widget.polygon.first),
    ];
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('fence-line'),
        points: pts,
        color: OptikAdminTokens.ice,
        width: 3,
      ),
    };
  }

  Set<gmaps.Marker> _markers() {
    final out = <gmaps.Marker>{};
    final preview = widget.previewTarget;
    if (preview != null) {
      out.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('preview'),
          position: toGoogleLatLng(preview),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueCyan,
          ),
          infoWindow: const gmaps.InfoWindow(
            title: 'Target sementara',
            snippet: 'Ketuk peta untuk set geofence',
          ),
          zIndexInt: 2,
        ),
      );
    }
    final center = widget.circleCenter;
    if (center != null) {
      out.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('center'),
          position: toGoogleLatLng(center),
          draggable: true,
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueAzure,
          ),
          infoWindow: const gmaps.InfoWindow(
            title: 'Pusat geofence',
            snippet: 'Geser untuk pindah',
          ),
          onDragStart: (_) => widget.onCenterDragStart(),
          onDrag: (p) => widget.onCenterDrag(fromGoogleLatLng(p)),
          onDragEnd: (p) {
            widget.onCenterDrag(fromGoogleLatLng(p));
            widget.onCenterDragEnd();
          },
          zIndexInt: 4,
        ),
      );
    }
    for (var i = 0; i < widget.polygon.length; i++) {
      final selected = widget.selectedCorner == i;
      out.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('corner-$i'),
          position: toGoogleLatLng(widget.polygon[i]),
          draggable: true,
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            selected
                ? gmaps.BitmapDescriptor.hueOrange
                : gmaps.BitmapDescriptor.hueRed,
          ),
          infoWindow: gmaps.InfoWindow(title: 'Sudut ${i + 1}'),
          onTap: () => widget.onCornerTap(i),
          onDragStart: (_) => widget.onCornerDragStart(i),
          onDrag: (p) => widget.onCornerDrag(i, fromGoogleLatLng(p)),
          onDragEnd: (p) {
            widget.onCornerDrag(i, fromGoogleLatLng(p));
            widget.onCornerDragEnd();
          },
          zIndexInt: selected ? 5 : 3,
        ),
      );
    }
    return out;
  }
}
