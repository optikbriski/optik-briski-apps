// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/geofence_geometry.dart';
import '../../shared/maps/osm_address_search.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

enum _FenceDrawMode { circle, corners4 }

/// Editor geofence absensi di **OpenStreetMap** (koordinat WGS84 = GPS HP).
/// Mode: lingkaran (tap pusat + radius) atau **4 tap sudut**.
class TokoGeofencePage extends StatefulWidget {
  const TokoGeofencePage({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<TokoGeofencePage> createState() => _TokoGeofencePageState();
}

class _TokoGeofencePageState extends State<TokoGeofencePage> {
  final _db = Supabase.instance.client;
  final _mapCtrl = MapController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _radiusCtrl = TextEditingController(text: '100');
  final _radiusFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  String? _error;
  String? _searchFeedback;
  String? _radiusError;
  List<Map<String, dynamic>> _tokoList = [];
  String? _selectedTokoId;
  List<OsmAddressHit> _searchHits = [];

  _FenceDrawMode _mode = _FenceDrawMode.circle;
  double? _lat;
  double? _lng;
  int _radiusMeters = 100;
  final List<LatLng> _corners = [];
  int? _selectedCorner;
  bool _draggingMarker = false;

  static const _defaultCenter = LatLng(-6.9175, 107.6191);
  static const _searchZoom = 17.0;
  static const _minRadius = 10;
  static const _maxRadius = 500;

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
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _radiusCtrl.dispose();
    _radiusFocus.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchAddress() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _searchHits = [];
        _searchFeedback = 'Ketik alamat dulu, lalu cari.';
      });
      return;
    }
    if (_searching) return;

    setState(() {
      _searching = true;
      _searchFeedback = null;
      _searchHits = [];
    });
    _searchFocus.unfocus();

    try {
      final hits = await OsmAddressSearch.search(
        q,
        bias: _defaultCenter,
        limit: 5,
      );
      if (!mounted) return;
      if (hits.isEmpty) {
        setState(() {
          _searching = false;
          _searchFeedback = 'Alamat tidak ditemukan. Coba kata kunci lain.';
        });
        return;
      }
      setState(() {
        _searching = false;
        _searchHits = hits;
        _searchFeedback = null;
      });
      // Hasil pertama langsung dipakai untuk geser peta (tanpa ubah geofence).
      _goToSearchHit(hits.first, keepResults: hits.length > 1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchFeedback = 'Gagal mencari alamat. Coba lagi.';
      });
    }
  }

  void _goToSearchHit(OsmAddressHit hit, {bool keepResults = false}) {
    try {
      _mapCtrl.move(hit.point, _searchZoom);
    } catch (_) {}
    setState(() {
      if (!keepResults) _searchHits = [];
      _searchFeedback =
          'Peta dipindah ke lokasi. Ketuk peta untuk set geofence.';
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() {
      _searchHits = [];
      _searchFeedback = null;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _db
          .from('toko_id')
          .select(
            'id, toko_id, latitude, longitude, radius_meters, '
            'geofence_mode, geofence_polygon',
          )
          .order('id');
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
      _selectedCorner = null;
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
      _setRadius(radius.clamp(_minRadius, _maxRadius), updateText: true);
    });

    final cam = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : (_corners.isNotEmpty ? _corners.first : _defaultCenter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapCtrl.move(cam, _zoomForRadius(_radiusMeters));
      } catch (_) {}
    });
  }

  double _zoomForRadius(int meters) {
    if (meters <= 30) return 18;
    if (meters <= 80) return 17;
    if (meters <= 150) return 16;
    if (meters <= 300) return 15;
    return 14;
  }

  void _setRadius(int meters, {bool updateText = true, bool moveCamera = false}) {
    final clamped = meters.clamp(_minRadius, _maxRadius);
    _radiusMeters = clamped;
    _radiusError = null;
    if (updateText && _radiusCtrl.text != '$clamped') {
      _radiusCtrl.value = TextEditingValue(
        text: '$clamped',
        selection: TextSelection.collapsed(offset: '$clamped'.length),
      );
    }
    if (moveCamera && _lat != null && _lng != null) {
      try {
        _mapCtrl.move(LatLng(_lat!, _lng!), _zoomForRadius(clamped));
      } catch (_) {}
    }
  }

  void _onRadiusTextChanged(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      setState(() => _radiusError = 'Isi radius ($_minRadius–$_maxRadius m)');
      return;
    }
    final v = int.tryParse(t);
    if (v == null) {
      setState(() => _radiusError = 'Angka saja, tanpa desimal');
      return;
    }
    if (v < _minRadius || v > _maxRadius) {
      setState(() {
        _radiusError = 'Radius $_minRadius–$_maxRadius meter';
      });
      return;
    }
    setState(() => _setRadius(v, updateText: false));
  }

  void _commitRadiusField() {
    final t = _radiusCtrl.text.trim();
    final v = int.tryParse(t);
    if (v == null) {
      setState(() {
        _radiusError = 'Angka saja, tanpa desimal';
        _radiusCtrl.text = '$_radiusMeters';
      });
      return;
    }
    setState(() => _setRadius(v, updateText: true, moveCamera: true));
  }

  void _syncCentroidFromCorners() {
    if (_corners.length < 3) return;
    final c = GeofenceGeometry.centroid(
      _corners.map((e) => GeoPoint(e.latitude, e.longitude)).toList(),
    );
    _lat = c?.lat;
    _lng = c?.lng;
  }

  void _onMapTap(TapPosition tap, LatLng point) {
    if (_draggingMarker) return;
    if (_mode == _FenceDrawMode.circle) {
      setState(() {
        _lat = point.latitude;
        _lng = point.longitude;
        _selectedCorner = null;
      });
      return;
    }
    if (_corners.length >= 4) {
      // Sudah 4 titik — jangan reset; geser / hapus sudut dulu.
      _toast(
        'Sudah 4 sudut. Geser penanda, atau hapus sudut lalu ketuk lagi.',
        OptikAdminTokens.warning,
      );
      return;
    }
    setState(() {
      _selectedCorner = null;
      _corners.add(point);
      if (_corners.length >= 3) _syncCentroidFromCorners();
    });
  }

  void _undoCorner() {
    if (_corners.isEmpty) return;
    setState(() {
      _corners.removeLast();
      _selectedCorner = null;
      if (_corners.length >= 3) {
        _syncCentroidFromCorners();
      }
    });
  }

  void _resetCorners() {
    setState(() {
      _corners.clear();
      _selectedCorner = null;
    });
  }

  void _deleteCorner(int index) {
    if (index < 0 || index >= _corners.length) return;
    setState(() {
      _corners.removeAt(index);
      _selectedCorner = null;
      if (_corners.length >= 3) {
        _syncCentroidFromCorners();
      }
    });
  }

  void _beginMarkerDrag() {
    if (_draggingMarker) return;
    setState(() => _draggingMarker = true);
  }

  void _endMarkerDrag() {
    if (!_draggingMarker) return;
    setState(() {
      _draggingMarker = false;
      if (_mode == _FenceDrawMode.corners4 && _corners.length >= 3) {
        _syncCentroidFromCorners();
      }
    });
  }

  LatLng? _offsetLatLng(LatLng origin, Offset delta) {
    try {
      final camera = _mapCtrl.camera;
      final screen = camera.latLngToScreenPoint(origin);
      return camera.pointToLatLng(
        Point(screen.x + delta.dx, screen.y + delta.dy),
      );
    } catch (_) {
      return null;
    }
  }

  void _dragCircleCenter(Offset delta) {
    if (_lat == null || _lng == null) return;
    final next = _offsetLatLng(LatLng(_lat!, _lng!), delta);
    if (next == null) return;
    setState(() {
      _lat = next.latitude;
      _lng = next.longitude;
    });
  }

  void _dragCorner(int index, Offset delta) {
    if (index < 0 || index >= _corners.length) return;
    final next = _offsetLatLng(_corners[index], delta);
    if (next == null) return;
    setState(() {
      _corners[index] = next;
      _selectedCorner = index;
      if (_corners.length >= 3) _syncCentroidFromCorners();
    });
  }

  Future<void> _save() async {
    final id = _selectedTokoId;
    if (id == null) return;

    if (_mode == _FenceDrawMode.circle) {
      if (_lat == null || _lng == null) {
        _toast('Ketuk peta untuk menaruh titik pusat.', OptikAdminTokens.warning);
        return;
      }
      _commitRadiusField();
      if (_radiusError != null) {
        _toast(_radiusError!, OptikAdminTokens.warning);
        return;
      }
    } else if (_corners.length != 4) {
      _toast(
        'Butuh tepat 4 sudut (${_corners.length}/4). Ketuk peta untuk menambah.',
        OptikAdminTokens.warning,
      );
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
        final pts =
            _corners.map((e) => GeoPoint(e.latitude, e.longitude)).toList();
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
        OptikAdminTokens.success,
      );
      setState(() {});
    } catch (e) {
      _toast('$e', OptikAdminTokens.danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_mode == _FenceDrawMode.circle && _lat != null && _lng != null) {
      markers.add(
        Marker(
          point: LatLng(_lat!, _lng!),
          width: 52,
          height: 52,
          alignment: Alignment.center,
          child: _DraggableMapMarker(
            onDragStart: _beginMarkerDrag,
            onDragUpdate: _dragCircleCenter,
            onDragEnd: _endMarkerDrag,
            child: const Icon(
              Icons.location_on_rounded,
              color: OptikAdminTokens.warning,
              size: 42,
              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
        ),
      );
      return markers;
    }

    for (var i = 0; i < _corners.length; i++) {
      final selected = _selectedCorner == i;
      markers.add(
        Marker(
          point: _corners[i],
          width: selected ? 56 : 44,
          height: selected ? 56 : 44,
          alignment: Alignment.center,
          child: _DraggableMapMarker(
            onTap: () => setState(() {
              _selectedCorner = selected ? null : i;
            }),
            onDragStart: () {
              _beginMarkerDrag();
              setState(() => _selectedCorner = i);
            },
            onDragUpdate: (d) => _dragCorner(i, d),
            onDragEnd: _endMarkerDrag,
            child: _CornerMarkerChip(
              index: i + 1,
              selected: selected,
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final center = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : (_corners.isNotEmpty ? _corners.first : _defaultCenter);

    final mapFlags = _draggingMarker
        ? InteractiveFlag.none
        : (InteractiveFlag.all & ~InteractiveFlag.rotate);

    return PremiumScaffold(
      appBar: PremiumAppBar(
        title: 'Geofence Toko',
        subtitle: 'OpenStreetMap · koordinat GPS (WGS84)',
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        OptikAdminTokens.spaceLg,
                        OptikAdminTokens.spaceMd,
                        OptikAdminTokens.spaceLg,
                        OptikAdminTokens.spaceSm,
                      ),
                      child: PremiumPanel(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        borderRadius: OptikAdminTokens.radiusLg,
                        child: _buildControlsPanel(),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: OptikAdminTokens.spaceLg,
                        ),
                        child: PremiumPanel(
                          padding: EdgeInsets.zero,
                          borderRadius: OptikAdminTokens.radiusLg,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(OptikAdminTokens.radiusLg),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: _mapCtrl,
                                  options: MapOptions(
                                    initialCenter: center,
                                    initialZoom: _zoomForRadius(_radiusMeters),
                                    onTap: _onMapTap,
                                    interactionOptions: InteractionOptions(
                                      flags: mapFlags,
                                    ),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.optikbriski.admin',
                                      maxZoom: 19,
                                    ),
                                    if (_mode == _FenceDrawMode.circle &&
                                        _lat != null &&
                                        _lng != null)
                                      CircleLayer(
                                        circles: [
                                          CircleMarker(
                                            point: LatLng(_lat!, _lng!),
                                            radius: _radiusMeters.toDouble(),
                                            useRadiusInMeter: true,
                                            color: OptikAdminTokens.accent
                                                .withOpacity(0.22),
                                            borderColor:
                                                OptikAdminTokens.accentSoft,
                                            borderStrokeWidth: 2.5,
                                          ),
                                        ],
                                      ),
                                    if (_mode == _FenceDrawMode.corners4 &&
                                        _corners.length >= 2)
                                      PolylineLayer(
                                        polylines: [
                                          Polyline(
                                            points: [
                                              ..._corners,
                                              if (_corners.length >= 3)
                                                _corners.first,
                                            ],
                                            color: OptikAdminTokens.accentSoft,
                                            strokeWidth: 2.5,
                                          ),
                                        ],
                                      ),
                                    if (_mode == _FenceDrawMode.corners4 &&
                                        _corners.length >= 3)
                                      PolygonLayer(
                                        polygons: [
                                          Polygon(
                                            points:
                                                List<LatLng>.from(_corners),
                                            color: OptikAdminTokens.accent
                                                .withOpacity(0.22),
                                            borderColor:
                                                OptikAdminTokens.accentSoft,
                                            borderStrokeWidth: 2.5,
                                          ),
                                        ],
                                      ),
                                    MarkerLayer(markers: _buildMarkers()),
                                  ],
                                ),
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  right: 10,
                                  child: _buildAddressSearchOverlay(),
                                ),
                                if (_mode == _FenceDrawMode.corners4 &&
                                    _selectedCorner != null)
                                  Positioned(
                                    bottom: 12,
                                    left: 12,
                                    right: 12,
                                    child: _buildSelectedCornerBar(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(OptikAdminTokens.spaceLg),
                      child: PremiumPrimaryButton(
                        label: 'Simpan geofence',
                        icon: Icons.save_rounded,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildControlsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PremiumSectionHeader(
          label: 'Toko & mode',
          padding: EdgeInsets.only(bottom: 10),
        ),
        if (_isPusat && _tokoList.length > 1)
          DropdownButtonFormField<String>(
            value: _selectedTokoId,
            dropdownColor: OptikAdminTokens.bgMid,
            style: const TextStyle(color: OptikAdminTokens.textPrimary),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
              border: Border.all(color: OptikAdminTokens.line),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  size: 18,
                  color: OptikAdminTokens.accentSoft,
                ),
                const SizedBox(width: 10),
                Text(
                  'Toko: ${_selectedTokoId ?? '-'}',
                  style: const TextStyle(
                    color: OptikAdminTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: OptikAdminTokens.spaceMd),
        SegmentedButton<_FenceDrawMode>(
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            side: WidgetStatePropertyAll(
              BorderSide(color: OptikAdminTokens.lineStrong),
            ),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return OptikAdminTokens.textPrimary;
              }
              return OptikAdminTokens.textMuted;
            }),
          ),
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
            setState(() {
              _mode = s.first;
              _selectedCorner = null;
            });
          },
        ),
        const SizedBox(height: 8),
        Text(
          _mode == _FenceDrawMode.circle
              ? 'Ketuk peta untuk titik pusat, atau geser penanda. '
                  'Atur radius (meter) dengan slider / ketik angka.'
              : 'Ketuk hingga 4 sudut (${_corners.length}/4). '
                  'Geser penanda bernomor untuk menyesuaikan; '
                  'ketuk penanda lalu hapus jika salah titik.',
          style: TextStyle(
            color: OptikAdminTokens.warning.withOpacity(0.85),
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        if (_mode == _FenceDrawMode.circle) ...[
          const SizedBox(height: OptikAdminTokens.spaceMd),
          const PremiumSectionHeader(
            label: 'Radius',
            padding: EdgeInsets.only(bottom: 8),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Slider(
                  value: _radiusMeters.toDouble(),
                  min: _minRadius.toDouble(),
                  max: _maxRadius.toDouble(),
                  label: '$_radiusMeters m',
                  activeColor: OptikAdminTokens.accentSoft,
                  onChanged: (v) {
                    setState(
                      () => _setRadius(v.round(), updateText: true),
                    );
                  },
                  onChangeEnd: (v) {
                    setState(
                      () => _setRadius(
                        v.round(),
                        updateText: true,
                        moveCamera: true,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _radiusCtrl,
                  focusNode: _radiusFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: OptikAdminTokens.warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                  onChanged: _onRadiusTextChanged,
                  onEditingComplete: _commitRadiusField,
                  onSubmitted: (_) => _commitRadiusField(),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: 'm',
                    suffixStyle: TextStyle(
                      color: OptikAdminTokens.warning.withOpacity(0.8),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                      borderSide:
                          const BorderSide(color: OptikAdminTokens.lineStrong),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                      borderSide: const BorderSide(
                        color: OptikAdminTokens.accentSoft,
                        width: 1.6,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                      borderSide:
                          const BorderSide(color: OptikAdminTokens.danger),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_radiusError != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _radiusError!,
                style: const TextStyle(
                  color: OptikAdminTokens.danger,
                  fontSize: 11.5,
                ),
              ),
            )
          else
            Text(
              'Batas $_minRadius–$_maxRadius meter · ketik angka pasti (mis. 25, 37)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.38),
                fontSize: 11,
              ),
            ),
          if (_lat != null && _lng != null) ...[
            const SizedBox(height: 8),
            Text(
              'Pusat: ${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
              style: const TextStyle(
                color: OptikAdminTokens.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ] else ...[
          const SizedBox(height: OptikAdminTokens.spaceMd),
          PremiumChipWrap(
            children: [
              PremiumActionChip(
                label: 'Hapus terakhir',
                icon: Icons.undo_rounded,
                onPressed: _corners.isEmpty ? null : _undoCorner,
              ),
              if (_selectedCorner != null)
                PremiumActionChip(
                  label: 'Hapus sudut ${_selectedCorner! + 1}',
                  icon: Icons.delete_outline_rounded,
                  onPressed: () => _deleteCorner(_selectedCorner!),
                ),
              PremiumActionChip(
                label: 'Ulang gambar',
                icon: Icons.refresh_rounded,
                onPressed: _corners.isEmpty ? null : _resetCorners,
              ),
            ],
          ),
          if (_corners.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...List.generate(_corners.length, (i) {
              final p = _corners[i];
              final selected = _selectedCorner == i;
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: InkWell(
                  onTap: () => setState(
                    () => _selectedCorner = selected ? null : i,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          'Sudut ${i + 1}: '
                          '${p.latitude.toStringAsFixed(6)}, '
                          '${p.longitude.toStringAsFixed(6)}',
                          style: TextStyle(
                            color: selected
                                ? OptikAdminTokens.warning
                                : Colors.white38,
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          IconButton(
                            tooltip: 'Hapus sudut ${i + 1}',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () => _deleteCorner(i),
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: OptikAdminTokens.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  Widget _buildSelectedCornerBar() {
    final i = _selectedCorner;
    if (i == null || i < 0 || i >= _corners.length) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: OptikAdminTokens.bgMid.withOpacity(0.94),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OptikAdminTokens.lineStrong),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: OptikAdminTokens.warning,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sudut ${i + 1} dipilih · geser untuk pindah',
                  style: const TextStyle(
                    color: OptikAdminTokens.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _deleteCorner(i),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Hapus'),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressSearchOverlay() {
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: OptikAdminTokens.bgMid.withOpacity(0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OptikAdminTokens.lineStrong),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchAddress(),
              decoration: InputDecoration(
                hintText: 'Cari alamat (mis. Braga, Bandung)…',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 13.5,
                ),
                prefixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OptikAdminTokens.warning,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.search_rounded,
                        color: OptikAdminTokens.warning,
                      ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Hapus',
                        onPressed: _searching ? null : _clearSearch,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: Colors.white54,
                      ),
                    IconButton(
                      tooltip: 'Cari',
                      onPressed: _searching ? null : _searchAddress,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      color: OptikAdminTokens.warning,
                    ),
                  ],
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (_) {
                // Rebuild agar tombol clear muncul/hilang.
                setState(() {});
              },
            ),
          ),
          if (_searchFeedback != null) ...[
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: OptikAdminTokens.panel.withOpacity(0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _searchFeedback!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
          if (_searchHits.length > 1) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: OptikAdminTokens.bgMid.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OptikAdminTokens.lineStrong),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _searchHits.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: OptikAdminTokens.line,
                  ),
                  itemBuilder: (context, i) {
                    final hit = _searchHits[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        i == 0 ? Icons.place_rounded : Icons.place_outlined,
                        color: i == 0
                            ? OptikAdminTokens.warning
                            : Colors.white54,
                        size: 20,
                      ),
                      title: Text(
                        hit.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          height: 1.3,
                        ),
                      ),
                      onTap: () => _goToSearchHit(hit),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _fieldDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OptikAdminTokens.radiusSm),
        ),
      );
}

/// Marker chip bernomor untuk sudut poligon.
class _CornerMarkerChip extends StatelessWidget {
  const _CornerMarkerChip({
    required this.index,
    required this.selected,
  });

  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sudut $index · ketuk untuk pilih · geser untuk pindah',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: selected ? 40 : 34,
        height: selected ? 40 : 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? OptikAdminTokens.warning : OptikAdminTokens.accent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(selected ? 0.95 : 0.65),
            width: selected ? 2.4 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: selected ? 10 : 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '$index',
          style: TextStyle(
            color: selected ? Colors.black87 : Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: selected ? 14 : 13,
          ),
        ),
      ),
    );
  }
}

/// Menyerap pointer saat drag agar pan peta tidak ikut bergeser (web + desktop).
class _DraggableMapMarker extends StatelessWidget {
  const _DraggableMapMarker({
    required this.child,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onTap,
  });

  final Widget child;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (d) => onDragUpdate(d.delta),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: child,
      ),
    );
  }
}
