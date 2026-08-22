// ignore_for_file: use_build_context_synchronously, deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math show Point, max, min, cos, pi;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/attendance/attendance_admin_scope.dart';
import '../../shared/attendance/geofence_geometry.dart';
import '../../shared/maps/osm_address_search.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/admin/admin_premium.dart';

enum _FenceDrawMode { circle, corners4 }

/// Editor geofence absensi (koordinat WGS84 = GPS HP).
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
  final _coordsCtrl = TextEditingController();
  final _coordsFocus = FocusNode();
  final _radiusCtrl = TextEditingController(text: '100');
  final _radiusFocus = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _searching = false;
  bool _reversing = false;
  /// Default satelit = mosaic Esri terbaru (bukan arsip Wayback).
  bool _satellite = true;
  String? _error;
  String? _searchFeedback;
  String? _coordsFeedback;
  String? _reverseLabel;
  String? _radiusError;
  String? _imageryMeta;
  bool _imageryMetaLoading = false;
  Timer? _imageryMetaDebounce;
  int _imageryMetaGen = 0;
  List<Map<String, dynamic>> _tokoList = [];
  String? _selectedTokoId;
  List<OsmAddressHit> _searchHits = [];

  /// Pin sementara dari pencarian / tempel koordinat (bukan geofence).
  LatLng? _previewTarget;
  LatLng? _reversePoint;

  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  http.Client? _searchClient;
  http.Client? _reverseClient;
  int _searchGen = 0;
  int _reverseGen = 0;

  _FenceDrawMode _mode = _FenceDrawMode.circle;
  double? _lat;
  double? _lng;
  int _radiusMeters = 100;
  final List<LatLng> _corners = [];
  int? _selectedCorner;
  bool _draggingMarker = false;

  static const _defaultCenter = LatLng(-6.9175, 107.6191);
  static const _searchZoom = 19.5;
  static const _minRadius = 10;
  static const _maxRadius = 500;
  static const _mapMaxZoom = 21.0;
  static const _autocompleteMinChars = 3;
  static const _autocompleteDebounce = Duration(milliseconds: 350);
  static const _reverseDebounceMs = Duration(milliseconds: 450);
  // Carto Voyager: detail dekat lebih baik & stabil di web dibanding OSM.org.
  static const _streetTiles =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  static const _streetNativeZoom = 20;
  static const _esriSatelliteTiles =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const _satelliteNativeZoom = 19;

  bool get _isPusat =>
      AttendanceAdminScope.canViewAllStores(widget.profile);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _imageryMetaDebounce?.cancel();
    _cancelInFlightSearch();
    _cancelInFlightReverse();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _coordsCtrl.dispose();
    _coordsFocus.dispose();
    _radiusCtrl.dispose();
    _radiusFocus.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  void _scheduleImageryMeta() {
    _imageryMetaDebounce?.cancel();
    _imageryMetaDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _refreshImageryMeta();
    });
  }

  String? _formatImageryDate(String? raw) {
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty || t.toLowerCase() == 'null') return null;
    // YYYYMMDD
    if (RegExp(r'^\d{8}$').hasMatch(t)) {
      return '${t.substring(6, 8)}/${t.substring(4, 6)}/${t.substring(0, 4)}';
    }
    // M/D/YYYY or MM/DD/YYYY
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(t);
    if (m != null) {
      final day = m.group(2)!.padLeft(2, '0');
      final month = m.group(1)!.padLeft(2, '0');
      return '$day/$month/${m.group(3)}';
    }
    return t;
  }

  /// Ambil tanggal akuisisi foto satelit Esri di titik peta (mosaic terbaru).
  Future<void> _refreshImageryMeta() async {
    if (!_satellite) {
      if (!mounted) return;
      setState(() {
        _imageryMeta = 'Mode peta jalan · data OSM/Carto (bukan foto satelit)';
        _imageryMetaLoading = false;
      });
      return;
    }

    LatLng center;
    double zoom;
    try {
      center = _mapCtrl.camera.center;
      zoom = _mapCtrl.camera.zoom;
    } catch (_) {
      center = (_lat != null && _lng != null)
          ? LatLng(_lat!, _lng!)
          : _defaultCenter;
      zoom = 18;
    }

    final gen = ++_imageryMetaGen;
    if (mounted) setState(() => _imageryMetaLoading = true);

    try {
      final z = zoom.round().clamp(12, 19);
      final pad = 0.01 / math.max(1, z - 10);
      final uri = Uri.parse(
        'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/identify',
      ).replace(queryParameters: {
        'f': 'json',
        'geometry': '${center.longitude},${center.latitude}',
        'geometryType': 'esriGeometryPoint',
        'sr': '4326',
        'tolerance': '2',
        'mapExtent':
            '${center.longitude - pad},${center.latitude - pad},${center.longitude + pad},${center.latitude + pad}',
        'imageDisplay': '800,600,96',
        'returnGeometry': 'false',
        'layers': 'all',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted || gen != _imageryMetaGen) return;
      if (res.statusCode != 200) {
        setState(() {
          _imageryMeta = 'Satelit Esri · mosaic terbaru (tanggal lokasi gagal dibaca)';
          _imageryMetaLoading = false;
        });
        return;
      }

      final body = jsonDecode(res.body);
      final results = (body is Map && body['results'] is List)
          ? body['results'] as List
          : const [];

      Map<String, dynamic>? best;
      var bestScore = -1;
      for (final raw in results) {
        if (raw is! Map) continue;
        final attrs = raw['attributes'];
        if (attrs is! Map) continue;
        final a = Map<String, dynamic>.from(attrs);
        final dateRaw = (a['DATE (YYYYMMDD)'] ??
                a['SRC_DATE'] ??
                a['DATE'] ??
                a['SRC_DATE2'])
            ?.toString();
        final formatted = _formatImageryDate(dateRaw);
        if (formatted == null) continue;

        final minL = int.tryParse('${a['MinMapLevel'] ?? a['FROM_CACHE_LEVEL'] ?? 0}') ?? 0;
        final maxL = int.tryParse('${a['MaxMapLevel'] ?? a['TO_CACHE_LEVEL'] ?? 19}') ?? 19;
        final inRange = z >= minL && z <= maxL;
        final resM = double.tryParse('${a['RESOLUTION (M)'] ?? a['SRC_RES'] ?? 99}') ?? 99;
        final score = (inRange ? 1000 : 0) + (100 - resM.round().clamp(0, 100));
        if (score > bestScore) {
          bestScore = score;
          best = {
            'date': formatted,
            'source': (a['SOURCE'] ?? a['NICE_DESC'] ?? a['SOURCE_INFO'] ?? 'Esri')
                .toString(),
            'product': (a['SOURCE_INFO'] ?? a['NICE_NAME'] ?? '').toString(),
            'res': resM,
          };
        }
      }

      if (!mounted || gen != _imageryMetaGen) return;
      if (best == null) {
        setState(() {
          _imageryMeta =
              'Satelit Esri World Imagery · mosaic publik terbaru di lokasi ini';
          _imageryMetaLoading = false;
        });
        return;
      }

      final hit = best;
      final resM = hit['res'] as double;
      final resLabel = resM < 10 ? ' · $resM m' : '';
      final product = (hit['product'] as String).trim();
      final productPart = product.isEmpty ? '' : ' · $product';
      final label =
          'Foto satelit: ${hit['date']}$productPart · ${hit['source']}$resLabel';
      setState(() {
        _imageryMeta = label;
        _imageryMetaLoading = false;
      });
    } catch (_) {
      if (!mounted || gen != _imageryMetaGen) return;
      setState(() {
        _imageryMeta = 'Satelit Esri · mosaic terbaru (metadata offline)';
        _imageryMetaLoading = false;
      });
    }
  }

  LatLng get _mapBias {
    try {
      return _mapCtrl.camera.center;
    } catch (_) {
      if (_lat != null && _lng != null) return LatLng(_lat!, _lng!);
      return _defaultCenter;
    }
  }

  void _cancelInFlightSearch() {
    _searchClient?.close();
    _searchClient = null;
  }

  void _cancelInFlightReverse() {
    _reverseClient?.close();
    _reverseClient = null;
  }

  void _invalidateSearch() {
    _cancelInFlightSearch();
    _searchGen++;
  }

  void _invalidateReverse() {
    _reverseDebounce?.cancel();
    _cancelInFlightReverse();
    _reverseGen++;
  }

  void _onSearchTextChanged(String value) {
    // Rebuild agar tombol clear muncul/hilang.
    setState(() {});
    _searchDebounce?.cancel();

    final q = value.trim();
    if (q.length < _autocompleteMinChars) {
      _invalidateSearch();
      setState(() {
        _searching = false;
        _searchHits = [];
        if (q.isEmpty) _searchFeedback = null;
      });
      return;
    }

    _searchDebounce = Timer(_autocompleteDebounce, () {
      if (!mounted) return;
      unawaited(_fetchAddressSuggestions(q, commitFirst: false));
    });
  }

  /// [commitFirst]=true: Enter / ikon cari — pindah ke hasil pertama.
  Future<void> _fetchAddressSuggestions(
    String query, {
    required bool commitFirst,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchHits = [];
        _searchFeedback = 'Ketik alamat dulu, lalu cari.';
      });
      return;
    }

    _cancelInFlightSearch();
    final client = http.Client();
    final gen = ++_searchGen;
    _searchClient = client;

    setState(() {
      _searching = true;
      _searchFeedback = null;
      if (commitFirst) _searchHits = [];
    });
    if (commitFirst) _searchFocus.unfocus();

    try {
      final hits = await OsmAddressSearch.search(
        q,
        bias: _mapBias,
        limit: 8,
        client: client,
      );
      if (!mounted || gen != _searchGen) return;

      if (hits.isEmpty) {
        setState(() {
          _searching = false;
          _searchHits = [];
          _searchFeedback = 'Alamat tidak ditemukan. Coba kata kunci lain.';
        });
        return;
      }

      setState(() {
        _searching = false;
        _searchHits = hits;
        _searchFeedback = null;
      });

      if (commitFirst) {
        // Hasil pertama langsung dipakai untuk geser peta (tanpa ubah geofence).
        _goToSearchHit(hits.first, keepResults: hits.length > 1);
      }
    } catch (e) {
      if (!mounted || gen != _searchGen) return;
      // Client ditutup saat keystroke baru / dispose — bukan error UI.
      if (e is http.ClientException) return;
      setState(() {
        _searching = false;
        _searchFeedback = 'Gagal mencari alamat. Coba lagi.';
      });
    } finally {
      if (identical(_searchClient, client)) {
        client.close();
        _searchClient = null;
      }
    }
  }

  Future<void> _searchAddress() async {
    _searchDebounce?.cancel();
    await _fetchAddressSuggestions(
      _searchCtrl.text,
      commitFirst: true,
    );
  }

  void _goToSearchHit(OsmAddressHit hit, {bool keepResults = false}) {
    _searchDebounce?.cancel();
    _invalidateSearch();
    try {
      _mapCtrl.move(hit.point, _searchZoom);
    } catch (_) {}
    _searchCtrl.value = TextEditingValue(
      text: hit.displayName,
      selection: TextSelection.collapsed(offset: hit.displayName.length),
    );
    setState(() {
      _searching = false;
      _previewTarget = hit.point;
      if (!keepResults) _searchHits = [];
      _searchFeedback =
          'Peta dipindah ke lokasi. Ketuk peta untuk set geofence.';
      _coordsFeedback = null;
    });
    _scheduleReverse(hit.point, immediate: true);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _invalidateSearch();
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _searchHits = [];
      _searchFeedback = null;
    });
  }

  void _goToPastedCoords() {
    final parsed = OsmCoordinatePaste.parse(_coordsCtrl.text);
    if (parsed == null) {
      setState(() {
        _coordsFeedback =
            'Format tidak dikenali. Contoh: -6.915146, 107.613528';
      });
      return;
    }
    _coordsFocus.unfocus();
    final point = parsed.point;
    try {
      _mapCtrl.move(point, _searchZoom);
    } catch (_) {}
    _coordsCtrl.value = TextEditingValue(
      text:
          '${parsed.lat.toStringAsFixed(6)}, ${parsed.lng.toStringAsFixed(6)}',
      selection: TextSelection.collapsed(
        offset:
            '${parsed.lat.toStringAsFixed(6)}, ${parsed.lng.toStringAsFixed(6)}'
                .length,
      ),
    );
    setState(() {
      _previewTarget = point;
      _searchHits = [];
      _coordsFeedback = 'Koordinat dipasang. Ketuk peta untuk set geofence.';
      _searchFeedback = null;
    });
    _scheduleReverse(point, immediate: true);
  }

  /// Titik yang ditampilkan di label reverse (preview → pusat / sudut).
  LatLng? get _activeReversePoint {
    if (_previewTarget != null) return _previewTarget;
    if (_mode == _FenceDrawMode.circle && _lat != null && _lng != null) {
      return LatLng(_lat!, _lng!);
    }
    if (_mode == _FenceDrawMode.corners4) {
      if (_selectedCorner != null &&
          _selectedCorner! >= 0 &&
          _selectedCorner! < _corners.length) {
        return _corners[_selectedCorner!];
      }
      if (_lat != null && _lng != null) return LatLng(_lat!, _lng!);
      if (_corners.isNotEmpty) return _corners.first;
    }
    return null;
  }

  void _scheduleReverse(LatLng point, {bool immediate = false}) {
    _reverseDebounce?.cancel();
    _reversePoint = point;
    if (immediate) {
      unawaited(_fetchReverseLabel(point));
      return;
    }
    _reverseDebounce = Timer(_reverseDebounceMs, () {
      if (!mounted) return;
      unawaited(_fetchReverseLabel(point));
    });
  }

  void _refreshReverseForActivePoint({bool immediate = false}) {
    final p = _activeReversePoint;
    if (p == null) {
      _invalidateReverse();
      setState(() {
        _reverseLabel = null;
        _reversePoint = null;
        _reversing = false;
      });
      return;
    }
    _scheduleReverse(p, immediate: immediate);
  }

  Future<void> _fetchReverseLabel(LatLng point) async {
    _cancelInFlightReverse();
    final client = http.Client();
    final gen = ++_reverseGen;
    _reverseClient = client;

    setState(() {
      _reversing = true;
      _reversePoint = point;
    });

    try {
      final hit = await OsmAddressSearch.reverse(point, client: client);
      if (!mounted || gen != _reverseGen) return;
      setState(() {
        _reversing = false;
        _reverseLabel = hit?.displayName;
      });
    } catch (e) {
      if (!mounted || gen != _reverseGen) return;
      if (e is http.ClientException) return;
      setState(() {
        _reversing = false;
        _reverseLabel = null;
      });
    } finally {
      if (identical(_reverseClient, client)) {
        client.close();
        _reverseClient = null;
      }
    }
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
      _previewTarget = null;
      _reverseLabel = null;
      _searchHits = [];
      _searchFeedback = null;
      _coordsFeedback = null;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _moveCameraToFence();
      _scheduleImageryMeta();
      _refreshReverseForActivePoint(immediate: true);
    });
  }

  double _zoomForRadius(int meters) {
    if (meters <= 20) return 20;
    if (meters <= 40) return 19.5;
    if (meters <= 80) return 19;
    if (meters <= 150) return 18;
    if (meters <= 300) return 16;
    return 14;
  }

  /// Zoom dari ukuran polygon (meter) agar area kecil bisa “sedeket” mungkin.
  double _zoomForPolygon(List<LatLng> corners) {
    if (corners.length < 2) return 19.5;
    var minLat = corners.first.latitude;
    var maxLat = corners.first.latitude;
    var minLng = corners.first.longitude;
    var maxLng = corners.first.longitude;
    for (final c in corners.skip(1)) {
      minLat = math.min(minLat, c.latitude);
      maxLat = math.max(maxLat, c.latitude);
      minLng = math.min(minLng, c.longitude);
      maxLng = math.max(maxLng, c.longitude);
    }
    final midLat = (minLat + maxLat) / 2;
    final latM = (maxLat - minLat) * 111320.0;
    final lngM =
        (maxLng - minLng) * 111320.0 * math.cos(midLat * math.pi / 180).abs();
    final span = math.max(latM, lngM);
    if (span <= 6) return 21;
    if (span <= 12) return 20.5;
    if (span <= 25) return 20;
    if (span <= 50) return 19.5;
    if (span <= 100) return 19;
    if (span <= 200) return 18;
    if (span <= 400) return 17;
    return 16;
  }

  void _moveCameraToFence() {
    try {
      if (_mode == _FenceDrawMode.corners4 && _corners.length >= 2) {
        _mapCtrl.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(_corners),
            padding: const EdgeInsets.all(80),
            maxZoom: _mapMaxZoom,
          ),
        );
        return;
      }
      final cam = (_lat != null && _lng != null)
          ? LatLng(_lat!, _lng!)
          : _defaultCenter;
      _mapCtrl.move(cam, _zoomForRadius(_radiusMeters));
    } catch (_) {
      final cam = (_lat != null && _lng != null)
          ? LatLng(_lat!, _lng!)
          : (_corners.isNotEmpty ? _corners.first : _defaultCenter);
      final z = _mode == _FenceDrawMode.corners4 && _corners.length >= 2
          ? _zoomForPolygon(_corners)
          : _zoomForRadius(_radiusMeters);
      try {
        _mapCtrl.move(cam, z);
      } catch (_) {}
    }
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
        _previewTarget = null;
      });
      _scheduleReverse(point, immediate: true);
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
      _selectedCorner = _corners.length; // sudut baru yang baru ditambah
      _previewTarget = null;
      _corners.add(point);
      if (_corners.length >= 3) _syncCentroidFromCorners();
    });
    _scheduleReverse(point, immediate: true);
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
    _refreshReverseForActivePoint(immediate: true);
  }

  void _resetCorners() {
    setState(() {
      _corners.clear();
      _selectedCorner = null;
      _previewTarget = null;
    });
    _refreshReverseForActivePoint(immediate: true);
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
    _refreshReverseForActivePoint(immediate: true);
  }

  void _beginMarkerDrag() {
    if (_draggingMarker) return;
    setState(() => _draggingMarker = true);
  }

  void _endMarkerDrag() {
    if (!_draggingMarker) return;
    setState(() {
      _draggingMarker = false;
      _previewTarget = null;
      if (_mode == _FenceDrawMode.corners4 && _corners.length >= 3) {
        _syncCentroidFromCorners();
      }
    });
    // Debounce: jangan reverse tiap pixel, hanya setelah drag selesai.
    _refreshReverseForActivePoint();
  }

  LatLng? _offsetLatLng(LatLng origin, Offset delta) {
    try {
      final camera = _mapCtrl.camera;
      final screen = camera.latLngToScreenPoint(origin);
      return camera.pointToLatLng(
        math.Point(screen.x + delta.dx, screen.y + delta.dy),
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
      SnackBar(
        backgroundColor: color,
        content: Text(
          msg,
          style: const TextStyle(
            color: OptikAdminTokens.snow,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _tokoLabel(Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    final nama = (row['toko_id'] ?? '').toString();
    if (nama.isNotEmpty && nama.toUpperCase() != id.toUpperCase()) {
      return '$id · $nama';
    }
    return id.isEmpty ? '-' : id;
  }

  /// Circle: lat/lng + radius > 0. Polygon: mode polygon + ≥3 titik.
  bool _tokoHasGeofence(Map<String, dynamic> row) {
    final mode = (row['geofence_mode'] ?? 'circle').toString().toLowerCase();
    if (mode == 'polygon') {
      final poly = GeofenceGeometry.parsePolygon(row['geofence_polygon']);
      return poly.length >= 3;
    }
    final lat = (row['latitude'] as num?)?.toDouble();
    final lng = (row['longitude'] as num?)?.toDouble();
    final radius = (row['radius_meters'] as num?)?.toInt() ?? 0;
    return lat != null && lng != null && radius > 0;
  }

  Map<String, dynamic>? get _selectedTokoRow {
    final id = _selectedTokoId;
    if (id == null) return null;
    for (final t in _tokoList) {
      if (t['id']?.toString() == id) return t;
    }
    return null;
  }

  String get _selectedTokoLabel {
    final id = _selectedTokoId;
    if (id == null) return 'Pilih toko…';
    final row = _selectedTokoRow;
    if (row != null) return _tokoLabel(row);
    return id;
  }

  /// Compact picker (bukan DropdownButtonFormField yang meledak di web).
  Future<void> _pickToko() async {
    if (!_isPusat || _tokoList.length <= 1) return;

    final options = _tokoList.map((t) {
      final id = t['id']?.toString() ?? '';
      return AdminPickerOption<String>(
        value: id,
        label: _tokoLabel(t),
        icon: Icons.storefront_outlined,
        trailing: _GeofenceRegBadge(registered: _tokoHasGeofence(t)),
      );
    }).toList();

    final result = await showAdminPicker<String>(
      context: context,
      title: 'Pilih toko',
      options: options,
      selected: _selectedTokoId,
      searchHint: 'Cari kode / nama toko…',
      headerIcon: Icons.storefront_rounded,
      filterOption: (o, q) =>
          o.label.toLowerCase().contains(q) ||
          o.value.toLowerCase().contains(q),
    );

    if (result == null || result.value == null) return;
    final picked = result.value!;
    if (picked != _selectedTokoId) {
      _applyToko(picked);
    }
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_previewTarget != null) {
      markers.add(
        Marker(
          point: _previewTarget!,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: const _PreviewTargetMarker(),
        ),
      );
    }

    if (_mode == _FenceDrawMode.circle && _lat != null && _lng != null) {
      markers.add(
        Marker(
          point: LatLng(_lat!, _lng!),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: _DraggableMapMarker(
            onDragStart: _beginMarkerDrag,
            onDragUpdate: _dragCircleCenter,
            onDragEnd: _endMarkerDrag,
            child: const _CenterAnchorMarker(),
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
          width: selected ? 48 : 40,
          height: selected ? 48 : 40,
          alignment: Alignment.center,
          child: _DraggableMapMarker(
            onTap: () {
              setState(() {
                _selectedCorner = selected ? null : i;
                _previewTarget = null;
              });
              _refreshReverseForActivePoint(immediate: true);
            },
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
        subtitle: 'Peta detail · koordinat GPS (WGS84)',
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: OptikAdminTokens.navy),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: OptikAdminTokens.ice))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: OptikAdminTokens.danger),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        PremiumPrimaryButton(
                          label: 'Coba lagi',
                          onPressed: _load,
                          expand: false,
                        ),
                      ],
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    // Peta tinggi tetap (~72vh, min 560) — halaman di-scroll,
                    // bukan dipaksa muat satu viewport dengan Expanded.
                    final mapH = math.max(
                      560.0,
                      MediaQuery.sizeOf(context).height * 0.72,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const PremiumSectionHeader(
                            label: 'Toko',
                            padding: EdgeInsets.only(bottom: 10, left: 2),
                          ),
                          PremiumPanel(
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            borderRadius: OptikAdminTokens.radiusLg,
                            borderColor:
                                OptikAdminTokens.ice.withOpacity(0.55),
                            child: _buildTokoSelector(),
                          ),
                          const SizedBox(height: 18),
                          const PremiumSectionHeader(
                            label: 'Mode geofence',
                            padding: EdgeInsets.only(bottom: 10, left: 2),
                          ),
                          PremiumPanel(
                            padding:
                                const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            borderRadius: OptikAdminTokens.radiusLg,
                            child: _buildModePanel(),
                          ),
                          const SizedBox(height: 18),
                          const PremiumSectionHeader(
                            label: 'Cari lokasi',
                            padding: EdgeInsets.only(bottom: 10, left: 2),
                          ),
                          _buildLocationToolsPanel(),
                          const SizedBox(height: 18),
                          const PremiumSectionHeader(
                            label: 'Peta workspace',
                            padding: EdgeInsets.only(bottom: 10, left: 2),
                          ),
                          SizedBox(
                            height: mapH,
                            child: PremiumPanel(
                              padding: EdgeInsets.zero,
                              borderRadius: OptikAdminTokens.radiusLg,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  OptikAdminTokens.radiusLg,
                                ),
                                // Serap scroll wheel di atas peta agar halaman
                                // tidak ikut bergeser saat pan/zoom di map.
                                child: Listener(
                                  onPointerSignal: (event) {
                                    if (event is PointerScrollEvent) {
                                      GestureBinding.instance
                                          .pointerSignalResolver
                                          .register(event, (_) {});
                                    }
                                  },
                                  child: Stack(
                                    children: [
                                      FlutterMap(
                                        mapController: _mapCtrl,
                                        options: MapOptions(
                                          initialCenter: center,
                                          initialZoom:
                                              _zoomForRadius(_radiusMeters),
                                          minZoom: 3,
                                          maxZoom: _mapMaxZoom,
                                          onTap: _onMapTap,
                                          onMapEvent: (event) {
                                            if (event is MapEventMoveEnd ||
                                                event is MapEventFlingAnimationEnd) {
                                              _scheduleImageryMeta();
                                            }
                                          },
                                          interactionOptions:
                                              InteractionOptions(
                                            flags: mapFlags,
                                          ),
                                        ),
                                        children: [
                                          TileLayer(
                                            urlTemplate: _satellite
                                                ? _esriSatelliteTiles
                                                : _streetTiles,
                                            userAgentPackageName:
                                                'com.optikbriski.admin',
                                            // Zoom kamera boleh > native: tile
                                            // terakhir di-scale (tidak abu-abu).
                                            maxZoom: _mapMaxZoom,
                                            maxNativeZoom: _satellite
                                                ? _satelliteNativeZoom
                                                : _streetNativeZoom,
                                          ),
                                          if (_mode ==
                                                  _FenceDrawMode.circle &&
                                              _lat != null &&
                                              _lng != null)
                                            CircleLayer(
                                              circles: [
                                                CircleMarker(
                                                  point: LatLng(_lat!, _lng!),
                                                  radius: _radiusMeters
                                                      .toDouble(),
                                                  useRadiusInMeter: true,
                                                  color: OptikAdminTokens
                                                      .ice
                                                      .withOpacity(0.22),
                                                  borderColor:
                                                      OptikAdminTokens.ice,
                                                  borderStrokeWidth: 2.5,
                                                ),
                                              ],
                                            ),
                                          if (_mode ==
                                                  _FenceDrawMode.corners4 &&
                                              _corners.length >= 2)
                                            PolylineLayer(
                                              polylines: [
                                                Polyline(
                                                  points: [
                                                    ..._corners,
                                                    if (_corners.length >= 3)
                                                      _corners.first,
                                                  ],
                                                  color: OptikAdminTokens.ice,
                                                  strokeWidth: 2.5,
                                                ),
                                              ],
                                            ),
                                          if (_mode ==
                                                  _FenceDrawMode.corners4 &&
                                              _corners.length >= 3)
                                            PolygonLayer(
                                              polygons: [
                                                Polygon(
                                                  points: List<LatLng>.from(
                                                    _corners,
                                                  ),
                                                  color: OptikAdminTokens
                                                      .ice
                                                      .withOpacity(0.22),
                                                  borderColor:
                                                      OptikAdminTokens.ice,
                                                  borderStrokeWidth: 2.5,
                                                ),
                                              ],
                                            ),
                                          MarkerLayer(
                                            markers: _buildMarkers(),
                                          ),
                                        ],
                                      ),
                                      Positioned(
                                        right: 12,
                                        bottom: _mode ==
                                                    _FenceDrawMode
                                                        .corners4 &&
                                                _selectedCorner != null
                                            ? 64
                                            : 12,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: OptikAdminTokens.bgMid
                                                  .withOpacity(0.94),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: OptikAdminTokens
                                                    .lineStrong,
                                              ),
                                            ),
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              onTap: () {
                                                setState(() =>
                                                    _satellite = !_satellite);
                                                _scheduleImageryMeta();
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _satellite
                                                          ? Icons.map_rounded
                                                          : Icons
                                                              .satellite_alt_rounded,
                                                      size: 16,
                                                      color: OptikAdminTokens
                                                          .navy,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _satellite
                                                          ? 'Peta'
                                                          : 'Satelit',
                                                      style: const TextStyle(
                                                        color:
                                                            OptikAdminTokens.slate,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_imageryMeta != null ||
                                          _imageryMetaLoading)
                                        Positioned(
                                          left: 12,
                                          top: 12,
                                          right: 12,
                                          child: IgnorePointer(
                                            child: Align(
                                              alignment: Alignment.topLeft,
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                        maxWidth: 420),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color: OptikAdminTokens
                                                        .bgMid
                                                        .withOpacity(0.94),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                    border: Border.all(
                                                      color: OptikAdminTokens
                                                          .lineStrong,
                                                    ),
                                                  ),
                                                  child: Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (_imageryMetaLoading)
                                                          const SizedBox(
                                                            width: 12,
                                                            height: 12,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 1.6,
                                                              color:
                                                                  OptikAdminTokens
                                                                      .ice,
                                                            ),
                                                          )
                                                        else
                                                          const Icon(
                                                            Icons
                                                                .calendar_month_rounded,
                                                            size: 14,
                                                            color:
                                                                OptikAdminTokens
                                                                    .navy,
                                                          ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Flexible(
                                                          child: Text(
                                                            _imageryMetaLoading
                                                                ? 'Cek tanggal foto satelit…'
                                                                : (_imageryMeta ??
                                                                    ''),
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  OptikAdminTokens.slate,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.3,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_mode ==
                                              _FenceDrawMode.corners4 &&
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
                          const SizedBox(height: 16),
                          PremiumPrimaryButton(
                            label: 'Simpan geofence',
                            icon: Icons.save_rounded,
                            loading: _saving,
                            onPressed: _saving ? null : _save,
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildTokoSelector() {
    final canPick = _isPusat && _tokoList.length > 1;
    final selected = _selectedTokoRow;
    final registered = selected != null && _tokoHasGeofence(selected);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPick ? _pickToko : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: OptikAdminTokens.navy.withOpacity(0.04),
            border: Border.all(color: OptikAdminTokens.lineStrong),
          ),
          child: Row(
            children: [
              const PremiumIconBadge(
                icon: Icons.storefront_rounded,
                color: OptikAdminTokens.navy,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canPick ? 'TOKO AKTIF' : 'TOKO',
                      style: TextStyle(
                        color: OptikAdminTokens.slate,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _selectedTokoLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: OptikAdminTokens.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _GeofenceRegBadge(registered: registered),
                        if (canPick)
                          Text(
                            '${_tokoList.length} cabang · ketuk untuk ganti',
                            style: TextStyle(
                              color:
                                  OptikAdminTokens.slate.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canPick)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: OptikAdminTokens.slate.withOpacity(0.95),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AdminPickerField(
          label: 'Mode gambar',
          valueText: _mode == _FenceDrawMode.circle ? 'Lingkaran' : '4 sudut',
          icon: _mode == _FenceDrawMode.circle
              ? Icons.radio_button_checked
              : Icons.crop_free,
          onTap: () async {
            final sel = await showAdminPicker<_FenceDrawMode>(
              context: context,
              title: 'Mode gambar geofence',
              searchable: false,
              selected: _mode,
              headerIcon: Icons.map_outlined,
              options: const [
                AdminPickerOption(
                  value: _FenceDrawMode.circle,
                  label: 'Lingkaran',
                  subtitle: 'Ketuk peta / geser pin pusat · atur radius',
                  icon: Icons.radio_button_checked,
                ),
                AdminPickerOption(
                  value: _FenceDrawMode.corners4,
                  label: '4 sudut',
                  subtitle: 'Ketuk hingga 4 sudut · geser penanda',
                  icon: Icons.crop_free,
                ),
              ],
            );
            if (sel == null || sel.isClear) return;
            setState(() {
              _mode = sel.value!;
              _selectedCorner = null;
            });
            _refreshReverseForActivePoint(immediate: true);
          },
        ),
        const SizedBox(height: 10),
        Text(
          _mode == _FenceDrawMode.circle
              ? 'Ketuk peta / geser pin pusat · atur radius di bawah.'
              : 'Ketuk hingga 4 sudut (${_corners.length}/4) · '
                  'geser penanda · ketuk penanda untuk hapus.',
          style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.9),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Default: satelit Esri mosaic terbaru. Badge di peta menampilkan '
          'tanggal foto di lokasi tersebut. Google-level “hari ini” butuh API berbayar.',
          style: TextStyle(
            color: OptikAdminTokens.slate.withOpacity(0.9),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (_mode == _FenceDrawMode.circle) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Radius',
                style: TextStyle(
                  color: OptikAdminTokens.slate,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$_minRadius–$_maxRadius m',
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.5,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                    ),
                  ),
                  child: Slider(
                    value: _radiusMeters.toDouble(),
                    min: _minRadius.toDouble(),
                    max: _maxRadius.toDouble(),
                    label: '$_radiusMeters m',
                    activeColor: OptikAdminTokens.navy,
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
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
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
                    color: OptikAdminTokens.navy,
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
                      color: OptikAdminTokens.navy.withOpacity(0.8),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: OptikAdminTokens.bgMid,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                      borderSide: const BorderSide(
                        color: OptikAdminTokens.lineStrong,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(OptikAdminTokens.radiusSm),
                      borderSide: const BorderSide(
                        color: OptikAdminTokens.navy,
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
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _radiusError!,
                style: const TextStyle(
                  color: OptikAdminTokens.danger,
                  fontSize: 11.5,
                ),
              ),
            )
          else if (_lat != null && _lng != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Pusat: ${_lat!.toStringAsFixed(6)}, '
                '${_lng!.toStringAsFixed(6)}',
                style: TextStyle(
                  color: OptikAdminTokens.slate.withOpacity(0.75),
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ] else ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _corners.isEmpty ? null : _undoCorner,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Hapus terakhir'),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.slate,
                ),
              ),
              if (_selectedCorner != null)
                TextButton.icon(
                  onPressed: () => _deleteCorner(_selectedCorner!),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Hapus ${_selectedCorner! + 1}'),
                  style: TextButton.styleFrom(
                    foregroundColor: OptikAdminTokens.danger,
                  ),
                ),
              TextButton.icon(
                onPressed: _corners.isEmpty ? null : _resetCorners,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Ulang'),
                style: TextButton.styleFrom(
                  foregroundColor: OptikAdminTokens.slate,
                ),
              ),
            ],
          ),
          if (_corners.isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _corners.length < 4,
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                childrenPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                dense: true,
                iconColor: OptikAdminTokens.slate,
                collapsedIconColor: OptikAdminTokens.slate,
                title: Text(
                  'Koordinat sudut (${_corners.length}/4)',
                  style: const TextStyle(
                    color: OptikAdminTokens.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                children: List.generate(_corners.length, (i) {
                  final p = _corners[i];
                  final selected = _selectedCorner == i;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCorner = selected ? null : i;
                        _previewTarget = null;
                      });
                      _refreshReverseForActivePoint(immediate: true);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}  '
                            '${p.latitude.toStringAsFixed(6)}, '
                            '${p.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: selected
                                  ? OptikAdminTokens.navy
                                  : OptikAdminTokens.slate,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (selected)
                            IconButton(
                              tooltip: 'Hapus sudut ${i + 1}',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => _deleteCorner(i),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: OptikAdminTokens.danger,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
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
          boxShadow: [
            BoxShadow(
              color: OptikAdminTokens.navy.withOpacity(0.2),
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
                backgroundColor: OptikAdminTokens.navy,
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: OptikAdminTokens.snow,
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
                    color: OptikAdminTokens.slate,
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

  /// Cari alamat / tempel koordinat / reverse — di atas peta (bukan overlay).
  Widget _buildLocationToolsPanel() {
    final showSuggestions = _searchHits.isNotEmpty;
    final reversePoint = _reversePoint ?? _activeReversePoint;
    final coordsLine = reversePoint == null
        ? null
        : '${reversePoint.latitude.toStringAsFixed(6)}, '
            '${reversePoint.longitude.toStringAsFixed(6)}';

    return PremiumPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      borderRadius: OptikAdminTokens.radiusLg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: OptikAdminTokens.navy.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OptikAdminTokens.lineStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 14,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchAddress(),
                  onChanged: _onSearchTextChanged,
                  decoration: InputDecoration(
                    hintText: 'Cari alamat (mis. Jl. Braga No. 1, Bandung)…',
                    hintStyle: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.65),
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
                                color: OptikAdminTokens.ice,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.search_rounded,
                            color: OptikAdminTokens.navy,
                          ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Hapus',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: OptikAdminTokens.slate,
                          ),
                        IconButton(
                          tooltip: 'Cari',
                          onPressed: _searching ? null : _searchAddress,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          color: OptikAdminTokens.navy,
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                const Divider(height: 1, color: OptikAdminTokens.line),
                TextField(
                  controller: _coordsCtrl,
                  focusNode: _coordsFocus,
                  style: const TextStyle(
                    color: OptikAdminTokens.navy,
                    fontSize: 13.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _goToPastedCoords(),
                  onChanged: (_) {
                    if (_coordsFeedback != null) {
                      setState(() => _coordsFeedback = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Tempel koordinat / link Maps…',
                    hintStyle: TextStyle(
                      color: OptikAdminTokens.slate.withOpacity(0.65),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.my_location_rounded,
                      color: OptikAdminTokens.navy,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Pakai koordinat',
                      onPressed: _goToPastedCoords,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      color: OptikAdminTokens.navy,
                    ),
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Belum ketemu di pencarian? Buka Google Maps → bagikan/salin '
            'koordinat → tempel di sini.',
            style: TextStyle(
              color: OptikAdminTokens.slate.withOpacity(0.85),
              fontSize: 11,
              height: 1.3,
            ),
          ),
          if (_searchFeedback != null || _coordsFeedback != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  _coordsFeedback ?? _searchFeedback!,
                  style: const TextStyle(
                    color: OptikAdminTokens.slate,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
          if (reversePoint != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OptikAdminTokens.line),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reversing)
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: OptikAdminTokens.navy,
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 1, right: 8),
                        child: Icon(
                          Icons.place_rounded,
                          size: 16,
                          color: OptikAdminTokens.navy,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _reversing
                                ? 'Mencari alamat di titik ini…'
                                : (_reverseLabel ??
                                    'Alamat tidak tersedia (tetap pakai koordinat).'),
                            style: const TextStyle(
                              color: OptikAdminTokens.slate,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            coordsLine!,
                            style: TextStyle(
                              color: OptikAdminTokens.slate.withOpacity(0.75),
                              fontSize: 11,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (showSuggestions) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: OptikAdminTokens.navy.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: OptikAdminTokens.lineStrong),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  primary: false,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _searchHits.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: OptikAdminTokens.line,
                  ),
                  itemBuilder: (context, i) {
                    final hit = _searchHits[i];
                    final subtitle = hit.subtitle;
                    return ListTile(
                      dense: true,
                      isThreeLine: subtitle != null,
                      leading: Icon(
                        i == 0 ? Icons.place_rounded : Icons.place_outlined,
                        color: i == 0
                            ? OptikAdminTokens.navy
                            : OptikAdminTokens.slate,
                        size: 20,
                      ),
                      title: Text(
                        hit.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OptikAdminTokens.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      subtitle: subtitle == null
                          ? null
                          : Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: OptikAdminTokens.slate.withOpacity(0.85),
                                fontSize: 11.5,
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

}

/// Chip status geofence toko di picker / selector.
class _GeofenceRegBadge extends StatelessWidget {
  const _GeofenceRegBadge({required this.registered});

  final bool registered;

  @override
  Widget build(BuildContext context) {
    final color =
        registered ? OptikAdminTokens.success : OptikAdminTokens.warning;
    final label = registered ? 'Terdaftar' : 'Belum';
    final icon = registered
        ? Icons.check_circle_outline_rounded
        : Icons.radio_button_unchecked_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(registered ? 0.16 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marker chip bernomor — fill semi-transparan + titik pusat solid di LatLng.
class _CornerMarkerChip extends StatelessWidget {
  const _CornerMarkerChip({
    required this.index,
    required this.selected,
  });

  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 40.0 : 34.0;
    final fill = selected
        ? OptikAdminTokens.navy.withOpacity(0.88)
        : OptikAdminTokens.ice.withOpacity(0.46);
    final border = selected
        ? OptikAdminTokens.navy
        : OptikAdminTokens.ice.withOpacity(0.75);

    return Tooltip(
      message: 'Sudut $index · ketuk untuk pilih · geser untuk pindah',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: size,
        height: size,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: border,
                  width: selected ? 2.2 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikAdminTokens.navy.withOpacity(0.35),
                    blurRadius: selected ? 8 : 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              alignment: Alignment.topCenter,
              padding: EdgeInsets.only(top: selected ? 4 : 3),
              child: Text(
                '$index',
                style: TextStyle(
                  color: selected ? OptikAdminTokens.snow : OptikAdminTokens.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: selected ? 12 : 11,
                  height: 1,
                  shadows: selected
                      ? null
                      : [
                          Shadow(
                            color: OptikAdminTokens.navy.withOpacity(0.2),
                            blurRadius: 3,
                          ),
                        ],
                ),
              ),
            ),
            // Titik pusat tepat di anchor LatLng (alignment Marker = center).
            Container(
              width: selected ? 8 : 7,
              height: selected ? 8 : 7,
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? OptikAdminTokens.snow
                      : OptikAdminTokens.ice,
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikAdminTokens.navy.withOpacity(0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pin sementara hasil cari alamat / tempel koordinat (belum jadi geofence).
class _PreviewTargetMarker extends StatelessWidget {
  const _PreviewTargetMarker();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Target sementara · ketuk peta untuk set geofence di sini',
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: OptikAdminTokens.ice.withOpacity(0.28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: OptikAdminTokens.ice.withOpacity(0.95),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: OptikAdminTokens.navy,
                shape: BoxShape.circle,
              ),
            ),
            // Crosshair tipis.
            Container(
              width: 22,
              height: 1.5,
              color: OptikAdminTokens.navy.withOpacity(0.7),
            ),
            Container(
              width: 1.5,
              height: 22,
              color: OptikAdminTokens.navy.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pin pusat mode lingkaran — semi-transparan + titik koordinat jelas.
class _CenterAnchorMarker extends StatelessWidget {
  const _CenterAnchorMarker();

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return Tooltip(
      message: 'Pusat geofence · geser untuk pindah',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: OptikAdminTokens.ice.withOpacity(0.48),
                shape: BoxShape.circle,
                border: Border.all(
                  color: OptikAdminTokens.ice.withOpacity(0.95),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikAdminTokens.navy.withOpacity(0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: OptikAdminTokens.navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: OptikAdminTokens.snow,
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: OptikAdminTokens.navy.withOpacity(0.2),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
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
