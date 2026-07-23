import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../training/training_mode.dart';
import '../training/training_sandbox_store.dart';
import 'geofence_geometry.dart';

class GeofenceCheckResult {
  const GeofenceCheckResult({
    required this.inside,
    required this.message,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.radiusMeters,
    this.accuracyMeters,
    this.gpsSkipped = false,
  });

  final bool inside;
  final String message;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final int? radiusMeters;
  final double? accuracyMeters;

  /// True bila cek GPS dilewati (mis. Absensi Toko web / Mac tanpa GPS chip).
  final bool gpsSkipped;
}

class GeofenceService {
  GeofenceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Cap buffer native (meter) — GPS HP biasanya lebih akurat.
  static const double nativeMaxAccuracyBufferMeters = 35;

  /// Ambang GPS akurat di web (meter). Di bawah ini boleh enforce fence ketat.
  /// Di atas ini (Wi‑Fi/IP) dianggap tidak andal — jangan pakai buffer longgar.
  static const double webHighAccuracyMeters = 30;

  /// [webKiosk]: Absensi Toko di browser (Mac/PC kasir) — lewati GPS Wi‑Fi
  /// yang tidak andal; hanya enforce jika ada GPS akurat (&lt;30 m).
  Future<GeofenceCheckResult> ensureAtStore(
    String tokoId, {
    bool webKiosk = false,
  }) async {
    final toko = await _resolveTokoRow(tokoId);

    if (toko == null) {
      return GeofenceCheckResult(
        inside: false,
        message: TrainingMode.instance.isActive
            ? 'Data toko belum tersedia offline. '
                'Masuk Mode Latihan saat online sekali agar koordinat di-cache lokal.'
            : 'Data toko tidak ditemukan.',
      );
    }

    if (webKiosk && kIsWeb) {
      return _ensureAtStoreWebKiosk(toko);
    }

    final permission = await _ensurePermission();
    if (permission != null) {
      return GeofenceCheckResult(inside: false, message: permission);
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    return evaluatePosition(
      toko: toko,
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracyMeters: pos.accuracy.isFinite ? pos.accuracy : null,
    );
  }

  /// Web kiosk: Mac/PC umumnya tanpa chip GPS. Percaya admin + toko dipilih
  /// (+ wajah di UI). Jika kebetulan ada GPS akurat &lt;30 m, enforce ketat.
  Future<GeofenceCheckResult> _ensureAtStoreWebKiosk(
    Map<String, dynamic> toko,
  ) async {
    try {
      final permission = await _ensurePermission();
      if (permission == null) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 12),
          ),
        );
        final acc = pos.accuracy.isFinite ? pos.accuracy : null;
        if (acc != null && acc > 0 && acc < webHighAccuracyMeters) {
          return evaluatePosition(
            toko: toko,
            latitude: pos.latitude,
            longitude: pos.longitude,
            accuracyMeters: acc,
          );
        }
      }
    } catch (_) {
      // Izin ditolak / timeout / Wi‑Fi kasar — lanjut skip GPS.
    }

    return const GeofenceCheckResult(
      inside: true,
      gpsSkipped: true,
      message:
          'Lokasi GPS dilewati (Mac/PC tidak punya GPS bawaan). '
          'Absensi Toko web memakai toko yang dipilih + verifikasi wajah.',
    );
  }

  /// Evaluasi posisi terhadap geofence toko (circle atau polygon 4 sudut).
  GeofenceCheckResult evaluatePosition({
    required Map<String, dynamic> toko,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    final mode = (toko['geofence_mode'] ?? 'circle').toString().toLowerCase();
    final polygon = GeofenceGeometry.parsePolygon(toko['geofence_polygon']);
    final buffer = accuracyBufferMeters(accuracyMeters);

    if (mode == 'polygon' && polygon.length >= 3) {
      final inside = GeofenceGeometry.containsWithBuffer(
        polygon,
        latitude,
        longitude,
        bufferMeters: buffer,
      );
      final edgeDist =
          GeofenceGeometry.distanceToPolygon(polygon, latitude, longitude);
      final c = GeofenceGeometry.centroid(polygon);
      double? dist;
      if (c != null) {
        dist = Geolocator.distanceBetween(
          c.lat,
          c.lng,
          latitude,
          longitude,
        );
      }
      if (!inside) {
        return GeofenceCheckResult(
          inside: false,
          message: _outsidePolygonMessage(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracyMeters,
            edgeDistanceMeters: edgeDist,
          ),
          latitude: latitude,
          longitude: longitude,
          distanceMeters: dist ?? edgeDist,
          accuracyMeters: accuracyMeters,
        );
      }
      return GeofenceCheckResult(
        inside: true,
        message: dist != null
            ? 'Lokasi valid (di dalam area toko, ~${dist.toStringAsFixed(0)} m dari pusat).'
            : 'Lokasi valid (di dalam area toko).',
        latitude: latitude,
        longitude: longitude,
        distanceMeters: dist,
        accuracyMeters: accuracyMeters,
      );
    }

    final lat = (toko['latitude'] as num?)?.toDouble();
    final lng = (toko['longitude'] as num?)?.toDouble();
    final radius = (toko['radius_meters'] as num?)?.toInt() ?? 100;

    if (lat == null || lng == null) {
      return const GeofenceCheckResult(
        inside: false,
        message:
            'Koordinat toko belum diatur. Hubungi Admin Pusat untuk set GPS toko.',
      );
    }

    final distance = Geolocator.distanceBetween(
      lat,
      lng,
      latitude,
      longitude,
    );

    if (distance > radius + buffer) {
      return GeofenceCheckResult(
        inside: false,
        message: _outsideCircleMessage(
          latitude: latitude,
          longitude: longitude,
          accuracyMeters: accuracyMeters,
          distanceMeters: distance,
          radiusMeters: radius,
        ),
        latitude: latitude,
        longitude: longitude,
        distanceMeters: distance,
        radiusMeters: radius,
        accuracyMeters: accuracyMeters,
      );
    }

    return GeofenceCheckResult(
      inside: true,
      message: 'Lokasi valid (${distance.toStringAsFixed(0)} m dari toko).',
      latitude: latitude,
      longitude: longitude,
      distanceMeters: distance,
      radiusMeters: radius,
      accuracyMeters: accuracyMeters,
    );
  }

  Future<Map<String, dynamic>?> loadToko(String tokoId) =>
      _resolveTokoRow(tokoId);

  /// Training: prefer local sandbox cache (offline). Live: Supabase only.
  /// Alias PUSAT ↔ CABANG-PUSAT: pakai baris yang punya geofence terisi.
  Future<Map<String, dynamic>?> _resolveTokoRow(String tokoId) async {
    const cols =
        'id, latitude, longitude, radius_meters, toko_id, geofence_mode, geofence_polygon';

    Future<Map<String, dynamic>?> fetch(
      String id, {
      bool enforceTrainingToko = true,
    }) async {
      if (TrainingMode.instance.isActive) {
        if (enforceTrainingToko) {
          TrainingMode.instance.assertSameToko(id);
        }
        final cached = await TrainingSandboxStore.instance.selectOne(
          'toko_id',
          where: {'id': id},
        );
        if (cached != null) return cached;
        try {
          final remote = await _client
              .from('toko_id')
              .select(cols)
              .eq('id', id)
              .maybeSingle();
          if (remote != null) {
            await TrainingSandboxStore.instance.insert(
              'toko_id',
              Map<String, dynamic>.from(remote),
            );
            return Map<String, dynamic>.from(remote);
          }
        } catch (_) {
          return null;
        }
        return null;
      }
      return _client.from('toko_id').select(cols).eq('id', id).maybeSingle();
    }

    final primary = await fetch(tokoId);
    if (_hasUsableGeofence(primary)) return primary;

    final alias = _pusatAlias(tokoId);
    if (alias != null) {
      // Alias PUSAT/CABANG-PUSAT: jangan gagal training scope.
      final alt = await fetch(alias, enforceTrainingToko: false);
      if (_hasUsableGeofence(alt)) return alt;
    }
    return primary;
  }

  static String? _pusatAlias(String tokoId) {
    final id = tokoId.trim().toUpperCase();
    if (id == 'PUSAT') return 'CABANG-PUSAT';
    if (id == 'CABANG-PUSAT') return 'PUSAT';
    return null;
  }

  static bool _hasUsableGeofence(Map<String, dynamic>? toko) {
    if (toko == null) return false;
    final mode = (toko['geofence_mode'] ?? 'circle').toString().toLowerCase();
    if (mode == 'polygon') {
      return GeofenceGeometry.parsePolygon(toko['geofence_polygon']).length >=
          3;
    }
    final lat = (toko['latitude'] as num?)?.toDouble();
    final lng = (toko['longitude'] as num?)?.toDouble();
    return lat != null && lng != null;
  }

  /// Buffer agar lingkaran ketidakpastian GPS boleh bersinggungan dengan fence.
  /// Ketat untuk GPS nyata (HP/tablet) — bukan workaround Wi‑Fi Mac.
  @visibleForTesting
  static double accuracyBufferMeters(double? accuracyMeters) {
    if (accuracyMeters == null ||
        !accuracyMeters.isFinite ||
        accuracyMeters <= 0) {
      return 8;
    }
    final raw = accuracyMeters * 0.4;
    if (raw <= 0) return 0;
    return raw > nativeMaxAccuracyBufferMeters
        ? nativeMaxAccuracyBufferMeters
        : raw;
  }

  String _fmtCoord(double v) => v.toStringAsFixed(6);

  String _gpsDebugLine({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) {
    final acc = accuracyMeters != null && accuracyMeters.isFinite
        ? ' (±${accuracyMeters.toStringAsFixed(0)} m)'
        : '';
    return 'GPS perangkat: ${_fmtCoord(latitude)}, ${_fmtCoord(longitude)}$acc.';
  }

  String _outsidePolygonMessage({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    required double edgeDistanceMeters,
  }) {
    final edge = edgeDistanceMeters.isFinite
        ? ' ~${edgeDistanceMeters.toStringAsFixed(0)} m di luar batas.'
        : '';
    return 'Anda di luar area toko (batas 4 sudut).$edge '
        '${_gpsDebugLine(latitude: latitude, longitude: longitude, accuracyMeters: accuracyMeters)} '
        'Pastikan perangkat benar-benar di dalam area yang digambar admin.';
  }

  String _outsideCircleMessage({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    required double distanceMeters,
    required int radiusMeters,
  }) {
    return 'Anda di luar area toko (${distanceMeters.toStringAsFixed(0)} m; '
        'batas $radiusMeters m). '
        '${_gpsDebugLine(latitude: latitude, longitude: longitude, accuracyMeters: accuracyMeters)}';
  }

  Future<String?> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'GPS perangkat mati. Nyalakan lokasi dulu.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return 'Izin lokasi ditolak. Absen membutuhkan GPS.';
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Izin lokasi diblokir permanen. Buka pengaturan HP.';
    }
    return null;
  }
}
