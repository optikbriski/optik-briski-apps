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
  });

  final bool inside;
  final String message;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final int? radiusMeters;
}

class GeofenceService {
  GeofenceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<GeofenceCheckResult> ensureAtStore(String tokoId) async {
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
    );
  }

  /// Evaluasi posisi terhadap geofence toko (circle atau polygon 4 sudut).
  GeofenceCheckResult evaluatePosition({
    required Map<String, dynamic> toko,
    required double latitude,
    required double longitude,
  }) {
    final mode = (toko['geofence_mode'] ?? 'circle').toString().toLowerCase();
    final polygon = GeofenceGeometry.parsePolygon(toko['geofence_polygon']);

    if (mode == 'polygon' && polygon.length >= 3) {
      final inside = GeofenceGeometry.contains(polygon, latitude, longitude);
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
          message:
              'Anda di luar area toko (batas 4 sudut). '
              'Absen / tetap di dalam area yang digambar admin.',
          latitude: latitude,
          longitude: longitude,
          distanceMeters: dist,
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

    if (distance > radius) {
      return GeofenceCheckResult(
        inside: false,
        message:
            'Anda di luar area toko (${distance.toStringAsFixed(0)} m). '
            'Absen hanya boleh dalam radius $radius m.',
        latitude: latitude,
        longitude: longitude,
        distanceMeters: distance,
        radiusMeters: radius,
      );
    }

    return GeofenceCheckResult(
      inside: true,
      message: 'Lokasi valid (${distance.toStringAsFixed(0)} m dari toko).',
      latitude: latitude,
      longitude: longitude,
      distanceMeters: distance,
      radiusMeters: radius,
    );
  }

  Future<Map<String, dynamic>?> loadToko(String tokoId) =>
      _resolveTokoRow(tokoId);

  /// Training: prefer local sandbox cache (offline). Live: Supabase only.
  Future<Map<String, dynamic>?> _resolveTokoRow(String tokoId) async {
    const cols =
        'id, latitude, longitude, radius_meters, toko_id, geofence_mode, geofence_polygon';

    if (TrainingMode.instance.isActive) {
      TrainingMode.instance.assertSameToko(tokoId);
      final cached = await TrainingSandboxStore.instance.selectOne(
        'toko_id',
        where: {'id': tokoId},
      );
      if (cached != null) return cached;
      try {
        final remote = await _client
            .from('toko_id')
            .select(cols)
            .eq('id', tokoId)
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

    return _client.from('toko_id').select(cols).eq('id', tokoId).maybeSingle();
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
