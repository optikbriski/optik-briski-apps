import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geofence_service.dart';

/// Pantau lokasi karyawan saat shift OPEN; notifikasi lokal jika keluar area.
///
/// Catatan: paling andal saat app aktif / izin lokasi diberikan.
/// Background "always" bergantung OS & permission user.
class GeofenceExitMonitor {
  GeofenceExitMonitor._();
  static final instance = GeofenceExitMonitor._();

  final _db = Supabase.instance.client;
  final _geofence = GeofenceService();
  final _notifications = FlutterLocalNotificationsPlugin();

  Timer? _timer;
  String? _karyawanId;
  String? _tokoId;
  Map<String, dynamic>? _tokoCache;
  bool _wasInside = true;
  DateTime? _lastAlertAt;
  bool _notifReady = false;

  static const _cooldown = Duration(minutes: 10);
  static const _pollEvery = Duration(seconds: 75);

  Future<void> ensureNotificationsReady() async {
    if (_notifReady || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    _notifReady = true;
  }

  /// Mulai monitor setelah absen masuk.
  Future<void> start({
    required String karyawanId,
    required String tokoId,
  }) async {
    if (kIsWeb) return;
    await ensureNotificationsReady();
    _karyawanId = karyawanId;
    _tokoId = tokoId;
    _tokoCache = await _geofence.loadToko(tokoId);
    _wasInside = true;
    _timer?.cancel();
    _timer = Timer.periodic(_pollEvery, (_) => _tick());
    // Cek cepat sekali.
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _karyawanId = null;
    _tokoId = null;
    _tokoCache = null;
  }

  /// Panggil saat app resume / buka absensi — restart jika masih ada shift OPEN.
  Future<void> syncFromOpenShift({
    required String karyawanId,
    required String tokoId,
    required bool hasOpenShift,
  }) async {
    if (!hasOpenShift) {
      stop();
      return;
    }
    if (_timer != null &&
        _karyawanId == karyawanId &&
        _tokoId == tokoId) {
      return;
    }
    await start(karyawanId: karyawanId, tokoId: tokoId);
  }

  Future<void> _tick() async {
    final kid = _karyawanId;
    final tid = _tokoId;
    if (kid == null || tid == null) return;

    try {
      // Pastikan masih OPEN
      final open = await _db
          .from('attendance_shifts')
          .select('id')
          .eq('karyawan_id', kid)
          .eq('status', 'OPEN')
          .maybeSingle();
      if (open == null) {
        stop();
        return;
      }

      _tokoCache ??= await _geofence.loadToko(tid);
      final toko = _tokoCache;
      if (toko == null) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final result = _geofence.evaluatePosition(
        toko: toko,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );

      final inside = result.inside;
      if (_wasInside && !inside) {
        await _onExit(
          karyawanId: kid,
          tokoId: tid,
          lat: pos.latitude,
          lng: pos.longitude,
        );
      }
      _wasInside = inside;
    } catch (e) {
      debugPrint('GeofenceExitMonitor tick: $e');
    }
  }

  Future<void> _onExit({
    required String karyawanId,
    required String tokoId,
    required double lat,
    required double lng,
  }) async {
    final now = DateTime.now();
    if (_lastAlertAt != null &&
        now.difference(_lastAlertAt!) < _cooldown) {
      return;
    }
    _lastAlertAt = now;

    await _notifications.show(
      4401,
      'Keluar area toko',
      'Anda keluar dari area geofence toko saat jam kerja (shift masih aktif).',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'geofence_exit',
          'Geofence toko',
          channelDescription: 'Peringatan keluar area absensi',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );

    try {
      await _db.from('geofence_exit_logs').insert({
        'karyawan_id': karyawanId,
        'toko_id': tokoId,
        'latitude': lat,
        'longitude': lng,
      });
    } catch (e) {
      debugPrint('geofence_exit_logs insert: $e');
    }
  }
}
