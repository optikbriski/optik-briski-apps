import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../theme.dart';
import 'geofence_workspace_map.dart';
import 'google_maps_js.dart';
import 'google_maps_support.dart';

/// Kanvas Google satu pin — tracking, alamat member, checkout.
/// macOS / Windows / Linux memakai OSM (plugin Google belum support desktop).
class GooglePinMap extends StatefulWidget {
  const GooglePinMap({
    super.key,
    required this.point,
    this.zoom = 16,
    this.height,
    this.title,
    this.snippet,
    this.onTap,
    this.onCameraIdle,
    this.centerPin = false,
    this.onCreated,
  });

  final LatLng point;
  final double zoom;
  final double? height;
  final String? title;
  final String? snippet;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<LatLng>? onCameraIdle;
  final bool centerPin;
  final ValueChanged<gmaps.GoogleMapController>? onCreated;

  @override
  State<GooglePinMap> createState() => _GooglePinMapState();
}

class _GooglePinMapState extends State<GooglePinMap> {
  late Future<void> _ready;
  gmaps.GoogleMapController? _c;
  MapController? _osm;
  Object? _error;

  bool get _useGoogle => googleMapsPluginSupported && hasGoogleMapsKey;

  @override
  void initState() {
    super.initState();
    if (_useGoogle) {
      _ready = _load();
    } else {
      _osm = MapController();
      _ready = Future.value();
    }
  }

  @override
  void dispose() {
    _osm?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!hasGoogleMapsKey) {
      throw StateError('GOOGLE_MAPS_API_KEY kosong');
    }
    try {
      await ensureGoogleMapsJs();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ensureGoogleMapsJs();
    }
  }

  void _boot() {
    setState(() {
      _error = null;
      _ready = _load();
    });
  }

  @override
  void didUpdateWidget(covariant GooglePinMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.point.latitude == widget.point.latitude &&
        oldWidget.point.longitude == widget.point.longitude &&
        oldWidget.zoom == widget.zoom) {
      return;
    }
    _c?.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(
        toGoogleLatLng(widget.point),
        widget.zoom.clamp(3.0, 21.0),
      ),
    );
    try {
      _osm?.move(widget.point, widget.zoom);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    final h = widget.height;
    if (h == null) return body;
    return SizedBox(height: h, child: body);
  }

  Widget _body() {
    if (!_useGoogle) {
      return _osmBody();
    }
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _boot,
          child: const Text('Peta Google gagal. Coba lagi'),
        ),
      );
    }
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: TextButton(
              onPressed: _boot,
              child: const Text('Peta Google gagal. Coba lagi'),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: OptikAdminTokens.ice),
          );
        }
        return gmaps.GoogleMap(
          initialCameraPosition: gmaps.CameraPosition(
            target: toGoogleLatLng(widget.point),
            zoom: widget.zoom.clamp(3.0, 21.0),
          ),
          mapType: gmaps.MapType.normal,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: true,
          compassEnabled: true,
          streetViewControlEnabled: false,
          mapTypeControlEnabled: false,
          fullscreenControlEnabled: false,
          webGestureHandling: gmaps.WebGestureHandling.greedy,
          webCameraControlEnabled: true,
          gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
            Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
          },
          markers: widget.centerPin
              ? {}
              : {
                  gmaps.Marker(
                    markerId: const gmaps.MarkerId('pin'),
                    position: toGoogleLatLng(widget.point),
                    draggable: widget.onTap != null,
                    infoWindow: gmaps.InfoWindow(
                      title: widget.title ?? 'Lokasi',
                      snippet: widget.snippet,
                    ),
                    onDragEnd: (p) => widget.onTap?.call(fromGoogleLatLng(p)),
                  ),
                },
          onMapCreated: (c) {
            _c = c;
            widget.onCreated?.call(c);
          },
          onTap: widget.onTap == null
              ? null
              : (p) => widget.onTap!(fromGoogleLatLng(p)),
          onCameraIdle: widget.onCameraIdle == null
              ? null
              : () async {
                  final c = _c;
                  if (c == null) return;
                  final z = await c.getVisibleRegion();
                  final mid = LatLng(
                    (z.northeast.latitude + z.southwest.latitude) / 2,
                    (z.northeast.longitude + z.southwest.longitude) / 2,
                  );
                  widget.onCameraIdle!(mid);
                },
        );
      },
    );
  }

  Widget _osmBody() {
    final ctrl = _osm ??= MapController();
    return FlutterMap(
      mapController: ctrl,
      options: MapOptions(
        initialCenter: widget.point,
        initialZoom: widget.zoom.clamp(3.0, 20.0),
        minZoom: 3,
        maxZoom: 20,
        onTap: widget.onTap == null
            ? null
            : (tap, p) => widget.onTap!(p),
        onMapEvent: (event) {
          if (widget.onCameraIdle == null) return;
          if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
            widget.onCameraIdle!(event.camera.center);
          }
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom |
              InteractiveFlag.drag |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.optikbriski.admin',
          maxZoom: 20,
          maxNativeZoom: 20,
        ),
        if (!widget.centerPin)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.point,
                width: 40,
                height: 40,
                child: Icon(
                  Icons.location_on_rounded,
                  color: OptikAdminTokens.navy,
                  size: 36,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
