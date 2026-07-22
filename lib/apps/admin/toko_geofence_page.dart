// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/geofence_geometry.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

enum _FenceDrawMode { circle, corners4 }

/// Editor geofence absensi di **Google Maps** (koordinat GPS nyata).
/// Mode: lingkaran (tap pusat + radius) atau **4 tap sudut**.
class TokoGeofencePage extends StatefulWidget {
  const TokoGeofencePage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<TokoGeofencePage> createState() => _TokoGeofencePageState();
}

class _TokoGeofencePageState extends State<TokoGeofencePage> {
  final _db = Supabase.instance.client;
  GoogleMapController? _mapCtrl;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _tokoList = [];
  String? _selectedTokoId;

  _FenceDrawMode _mode = _FenceDrawMode.circle;
  double? _lat;
  double? _lng;
  int _radiusMeters = 100;
  final List<LatLng> _corners = [];

  static const _defaultCenter = LatLng(-6.9175, 107.6191);

  bool get _isPusat {
    final t = (widget.profile['toko_id'] ?? '').toString().toUpperCase();
    final r = (widget.profile['role'] ?? '').toString().toLowerCase();
    return t == 'PUSAT' ||
        t == 'CABANG-PUSAT' ||
        r == 'owner' ||
        r == 'admin_pusat' ||
        r == 'super_admin';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db.from('toko_id').select(
            'id, toko_id, latitude, longitude, radius_meters, '
            'geofence_mode, geofence_polygon',
          ).order('id');
      var list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!_isPusat) {
        final my = (widget.profile['toko_id'] ?? '').toString().toUpperCase();
        list = list
            .where((t) => (t['id'] ?? '').toString().toUpperCase() == my)
            .toList();
      }

      if (!mounted) return;
      final firstId = list.isNotEmpty ? list.first['id']?.toString() : null;
      setState(() {
        _tokoList = list;
        _selectedTokoId = firstId;
        _loading = false;
      });
      if (firstId != null) _applyToko(firstId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyToko(String id) {
    Map<String, dynamic>? row;
    for (final t in _tokoList) {
      if (t['id']?.toString() == id) {
        row = t;
        break;
      }
    }
    final mode = (row?['geofence_mode'] ?? 'circle').toString().toLowerCase();
    final lat = (row?['latitude'] as num?)?.toDouble();
    final lng = (row?['longitude'] as num?)?.toDouble();
    final radius = (row?['radius_meters'] as num?)?.toInt() ?? 100;
    final poly = GeofenceGeometry.parsePolygon(row?['geofence_polygon']);

    setState(() {
      _selectedTokoId = id;
      _corners
        ..clear()
        ..addAll(poly.map((p) => LatLng(p.lat, p.lng)));
      if (mode == 'polygon' && _corners.length == 4) {
        _mode = _FenceDrawMode.corners4;
        final c = GeofenceGeometry.centroid(poly);
        _lat = c?.lat ?? lat;
        _lng = c?.lng ?? lng;
      } else {
        _mode = _FenceDrawMode.circle;
        _lat = lat;
        _lng = lng;
      }
      _radiusMeters = radius.clamp(10, 1000);
    });

    final cam = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : (_corners.isNotEmpty ? _corners.first : _defaultCenter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapCtrl?.animateCamera(CameraUpdate.newLatLngZoom(cam, 17));
    });
  }

  void _onMapTap(LatLng point) {
    if (_mode == _FenceDrawMode.circle) {
      setState(() {
        _lat = point.latitude;
        _lng = point.longitude;
      });
      return;
    }
    // 4 sudut
    setState(() {
      if (_corners.length >= 4) {
        _corners
          ..clear()
          ..add(point);
      } else {
        _corners.add(point);
      }
      if (_corners.length == 4) {
        final c = GeofenceGeometry.centroid(
          _corners.map((e) => GeoPoint(e.latitude, e.longitude)).toList(),
        );
        _lat = c?.lat;
        _lng = c?.lng;
      }
    });
  }

  void _undoCorner() {
    if (_corners.isEmpty) return;
    setState(() => _corners.removeLast());
  }

  void _resetCorners() {
    setState(() => _corners.clear());
  }

  Set<Marker> get _markers {
    if (_mode == _FenceDrawMode.circle) {
      if (_lat == null || _lng == null) return {};
      return {
        Marker(
          markerId: const MarkerId('center'),
          position: LatLng(_lat!, _lng!),
          infoWindow: const InfoWindow(title: 'Pusat radius'),
        ),
      };
    }
    return {
      for (var i = 0; i < _corners.length; i++)
        Marker(
          markerId: MarkerId('c$i'),
          position: _corners[i],
          infoWindow: InfoWindow(title: 'Sudut ${i + 1}/4'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure + (i * 15),
          ),
        ),
    };
  }

  Set<Circle> get _circles {
    if (_mode != _FenceDrawMode.circle || _lat == null || _lng == null) {
      return {};
    }
    return {
      Circle(
        circleId: const CircleId('fence'),
        center: LatLng(_lat!, _lng!),
        radius: _radiusMeters.toDouble(),
        fillColor: const Color(0xFF3B82F6).withOpacity(0.22),
        strokeColor: const Color(0xFF60A5FA),
        strokeWidth: 2,
      ),
    };
  }

  Set<Polygon> get _polygons {
    if (_mode != _FenceDrawMode.corners4 || _corners.length < 3) return {};
    return {
      Polygon(
        polygonId: const PolygonId('fence'),
        points: List<LatLng>.from(_corners),
        fillColor: const Color(0xFF3B82F6).withOpacity(0.22),
        strokeColor: const Color(0xFF60A5FA),
        strokeWidth: 2,
      ),
    };
  }

  Future<void> _save() async {
    final id = _selectedTokoId;
    if (id == null) return;

    if (_mode == _FenceDrawMode.circle) {
      if (_lat == null || _lng == null) {
        _toast('Ketuk peta Google untuk menaruh titik pusat.', Colors.orange);
        return;
      }
    } else if (_corners.length != 4) {
      _toast('Ketuk tepat 4 sudut di peta Google dulu.', Colors.orange);
      return;
    }

    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{
        'geofence_mode':
            _mode == _FenceDrawMode.circle ? 'circle' : 'polygon',
      };
      if (_mode == _FenceDrawMode.circle) {
        patch['latitude'] = _lat;
        patch['longitude'] = _lng;
        patch['radius_meters'] = _radiusMeters;
        patch['geofence_polygon'] = null;
      } else {
        final pts = _corners
            .map((e) => GeoPoint(e.latitude, e.longitude))
            .toList();
        patch['geofence_polygon'] = GeofenceGeometry.polygonToJson(pts);
        final c = GeofenceGeometry.centroid(pts);
        if (c != null) {
          patch['latitude'] = c.lat;
          patch['longitude'] = c.lng;
        }
      }

      await _db.from('toko_id').update(patch).eq('id', id);

      for (var i = 0; i < _tokoList.length; i++) {
        if (_tokoList[i]['id']?.toString() == id) {
          _tokoList[i] = {..._tokoList[i], ...patch};
          break;
        }
      }

      if (!mounted) return;
      _toast(
        _mode == _FenceDrawMode.circle
            ? 'Geofence $id (lingkaran $_radiusMeters m) disimpan.'
            : 'Geofence $id (4 sudut) disimpan.',
        Colors.green,
      );
      setState(() {});
    } catch (e) {
      _toast('$e', Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : (_corners.isNotEmpty ? _corners.first : _defaultCenter);

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Geofence Toko',
        subtitle: 'Google Maps · lat/lng GPS nyata',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isPusat && _tokoList.length > 1)
                            DropdownButtonFormField<String>(
                              value: _selectedTokoId,
                              dropdownColor: OptikAdminTokens.bgMid,
                              style: const TextStyle(color: Colors.white),
                              decoration: _fieldDeco('Toko'),
                              items: _tokoList
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t['id']?.toString(),
                                      child: Text(t['id']?.toString() ?? '-'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) _applyToko(v);
                              },
                            )
                          else
                            Text(
                              'Toko: ${_selectedTokoId ?? '-'}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 10),
                          SegmentedButton<_FenceDrawMode>(
                            segments: const [
                              ButtonSegment(
                                value: _FenceDrawMode.circle,
                                label: Text('Lingkaran'),
                                icon: Icon(Icons.radio_button_checked, size: 16),
                              ),
                              ButtonSegment(
                                value: _FenceDrawMode.corners4,
                                label: Text('4 sudut'),
                                icon: Icon(Icons.crop_free, size: 16),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) {
                              setState(() => _mode = s.first);
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _mode == _FenceDrawMode.circle
                                ? 'Ketuk peta Google untuk titik pusat, atur radius (meter).'
                                : 'Ketuk 4 sudut berurutan di peta Google '
                                    '(${_corners.length}/4). Area tertutup otomatis.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                          if (kIsWeb)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Butuh GOOGLE_MAPS_API_KEY di Vercel / web/index.html.',
                                style: TextStyle(
                                  color: Colors.orange.withOpacity(0.75),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (_mode == _FenceDrawMode.circle) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Text('Radius',
                                    style: TextStyle(color: Colors.white70)),
                                Expanded(
                                  child: Slider(
                                    value: _radiusMeters.toDouble(),
                                    min: 10,
                                    max: 500,
                                    divisions: 49,
                                    label: '$_radiusMeters m',
                                    activeColor: OptikAdminTokens.accentSoft,
                                    onChanged: (v) => setState(
                                        () => _radiusMeters = v.round()),
                                  ),
                                ),
                                Text(
                                  '$_radiusMeters m',
                                  style: const TextStyle(
                                    color: OptikAdminTokens.warning,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed:
                                      _corners.isEmpty ? null : _undoCorner,
                                  icon: const Icon(Icons.undo, size: 18),
                                  label: const Text('Hapus titik terakhir'),
                                ),
                                TextButton.icon(
                                  onPressed:
                                      _corners.isEmpty ? null : _resetCorners,
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  label: const Text('Ulang gambar'),
                                ),
                              ],
                            ),
                            if (_corners.isNotEmpty)
                              ...List.generate(_corners.length, (i) {
                                final p = _corners[i];
                                return Text(
                                  'Sudut ${i + 1}: '
                                  '${p.latitude.toStringAsFixed(6)}, '
                                  '${p.longitude.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                );
                              }),
                          ],
                          if (_mode == _FenceDrawMode.circle &&
                              _lat != null &&
                              _lng != null)
                            Text(
                              'Pusat: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: center,
                              zoom: 17,
                            ),
                            onMapCreated: (c) => _mapCtrl = c,
                            onTap: _onMapTap,
                            markers: _markers,
                            circles: _circles,
                            polygons: _polygons,
                            mapType: MapType.hybrid,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                            compassEnabled: true,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: OptikAdminTokens.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save_rounded),
                          label: const Text(
                            'Simpan geofence',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );
}
