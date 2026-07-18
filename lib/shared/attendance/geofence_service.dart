import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final toko = await _client
        .from('toko_id')
        .select('id, latitude, longitude, radius_meters, toko_id')
        .eq('id', tokoId)
        .maybeSingle();

    if (toko == null) {
      return const GeofenceCheckResult(
        inside: false,
        message: 'Data toko tidak ditemukan.',
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

    final distance = Geolocator.distanceBetween(
      lat,
      lng,
      pos.latitude,
      pos.longitude,
    );

    if (distance > radius) {
      return GeofenceCheckResult(
        inside: false,
        message:
            'Anda di luar area toko (${distance.toStringAsFixed(0)} m). '
            'Absen hanya boleh dalam radius $radius m.',
        latitude: pos.latitude,
        longitude: pos.longitude,
        distanceMeters: distance,
        radiusMeters: radius,
      );
    }

    return GeofenceCheckResult(
      inside: true,
      message: 'Lokasi valid (${distance.toStringAsFixed(0)} m dari toko).',
      latitude: pos.latitude,
      longitude: pos.longitude,
      distanceMeters: distance,
      radiusMeters: radius,
    );
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
