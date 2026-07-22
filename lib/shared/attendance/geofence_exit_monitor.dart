import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geofence_service.dart';

/// Pantau lokasi karyawan saat shift OPEN; notifikasi lokal jika keluar area.
///
/// Android: position stream + foreground notification agar proses lebih tahan
/// saat app di background. Bukan 100% unkillable (force-stop / battery saver
/// agresif tetap bisa menghentikan).
///
/// iOS: best-effort dengan background location indicator jika izin Always.
class GeofenceExitMonitor {
  GeofenceExitMonitor._();
  static final instance = GeofenceExitMonitor._();

  final _db = Supabase.instance.client;
  final _geofence = GeofenceService();
  final _notifications = FlutterLocalNotificationsPlugin();

  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  String? _karyawanId;
  String? _tokoId;
  Map<String, dynamic>? _tokoCache;
  bool _wasInside = true;
  DateTime? _lastAlertAt;
  DateTime? _lastTickAt;
  bool _tickInFlight = false;
  bool _notifReady = false;
  bool _starting = false;

  static const _cooldown = Duration(minutes: 10);
  static const _pollEvery = Duration(seconds: 75);
  static const _minTickGap = Duration(seconds: 45);

  bool get isRunning =>
      _karyawanId != null && (_timer != null || _positionSub != null);

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

  /// Minta izin lokasi (when-in-use → always) + notifikasi.
  /// [context] dipakai untuk dialog penjelasan bahasa Indonesia sebelum Always.
  Future<void> ensureTrackingPermissions({BuildContext? context}) async {
    if (kIsWeb) return;
    await ensureNotificationsReady();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GeofenceExitMonitor: GPS mati');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('GeofenceExitMonitor: izin lokasi ditolak ($permission)');
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      var proceed = true;
      if (context != null && context.mounted) {
        proceed = await _explainAlwaysPermission(context);
      }
      if (proceed) {
        permission = await Geolocator.requestPermission();
      }
    }

    debugPrint('GeofenceExitMonitor: permission=$permission');
  }

  Future<bool> _explainAlwaysPermission(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Izinkan lokasi selama shift',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        content: const Text(
          'Agar pantauan area toko tetap jalan saat aplikasi di belakang '
          '(misalnya HP terkunci atau Anda membuka app lain), pilih '
          '“Izinkan sepanjang waktu” / “Allow all the time” pada langkah berikutnya.\n\n'
          'Lokasi hanya dipantau saat shift absensi masih aktif, lalu berhenti '
          'otomatis setelah absen pulang.\n\n'
          'Catatan: jika aplikasi di-force stop atau izin lokasi dicabut, '
          'pantauan bisa berhenti.',
          style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Lanjut izinkan'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Mulai monitor setelah absen masuk.
  Future<void> start({
    required String karyawanId,
    required String tokoId,
    BuildContext? permissionContext,
  }) async {
    if (kIsWeb) return;
    if (_starting) return;
    _starting = true;
    try {
      await ensureTrackingPermissions(context: permissionContext);
      _karyawanId = karyawanId;
      _tokoId = tokoId;
      _tokoCache = await _geofence.loadToko(tokoId);
      _wasInside = true;
      await _startForegroundStream();
      _timer?.cancel();
      _timer = Timer.periodic(_pollEvery, (_) => _tick());
      unawaited(_tick());
    } finally {
      _starting = false;
    }
  }

  Future<void> _startForegroundStream() async {
    await _positionSub?.cancel();
    _positionSub = null;

    try {
      final settings = _locationSettingsForPlatform();
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
        (pos) => unawaited(_tick(position: pos)),
        onError: (Object e) {
          debugPrint('GeofenceExitMonitor position stream: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GeofenceExitMonitor start stream: $e');
    }
  }

  LocationSettings _locationSettingsForPlatform() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30,
        intervalDuration: _pollEvery,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Absensi aktif',
          notificationText: 'Lokasi dipantau selama shift',
          notificationChannelName: 'Absensi lokasi',
          setOngoing: true,
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        activityType: ActivityType.other,
        distanceFilter: 30,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 30,
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final sub = _positionSub;
    _positionSub = null;
    if (sub != null) unawaited(sub.cancel());
    _karyawanId = null;
    _tokoId = null;
    _tokoCache = null;
    _tickInFlight = false;
  }

  /// Panggil saat app resume / buka absensi — restart jika masih ada shift OPEN.
  Future<void> syncFromOpenShift({
    required String karyawanId,
    required String tokoId,
    required bool hasOpenShift,
    BuildContext? permissionContext,
  }) async {
    if (!hasOpenShift) {
      stop();
      return;
    }
    if (isRunning &&
        _karyawanId == karyawanId &&
        _tokoId == tokoId) {
      return;
    }
    await start(
      karyawanId: karyawanId,
      tokoId: tokoId,
      permissionContext: permissionContext,
    );
  }

  Future<void> _tick({Position? position}) async {
    final kid = _karyawanId;
    final tid = _tokoId;
    if (kid == null || tid == null) return;
    if (_tickInFlight) return;

    final now = DateTime.now();
    if (position != null &&
        _lastTickAt != null &&
        now.difference(_lastTickAt!) < _minTickGap) {
      return;
    }

    _tickInFlight = true;
    _lastTickAt = now;
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

      final pos = position ??
          await Geolocator.getCurrentPosition(
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
    } finally {
      _tickInFlight = false;
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
