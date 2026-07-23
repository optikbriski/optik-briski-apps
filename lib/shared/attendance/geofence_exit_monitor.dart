import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'android_battery_optimization.dart';
import 'geofence_service.dart';

/// Pantau lokasi karyawan saat shift OPEN; notifikasi lokal jika keluar area
/// atau GPS/izin lokasi dimatikan.
///
/// Android: [Geolocator] position stream + foreground service (notifikasi
/// ongoing) agar pantauan lebih tahan saat app di background / layar mati.
/// Bukan 100% unkillable — force-stop, cabut izin, atau battery saver agresif
/// tetap bisa menghentikan.
///
/// iOS: best-effort dengan background location indicator jika izin Always.
///
/// Pengecualian: ijin/cuti APPROVED di [jadwal_pengajuan] untuk hari ini
/// → tidak kirim peringatan keluar area / GPS mati.
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
  DateTime? _lastGpsAlertAt;
  DateTime? _lastTickAt;
  DateTime? _lastIjinCheckAt;
  bool? _cachedHasApprovedLeave;
  bool _tickInFlight = false;
  bool _notifReady = false;
  bool _starting = false;
  bool _gpsIssueActive = false;

  static const _cooldown = Duration(minutes: 10);
  static const _pollEvery = Duration(seconds: 75);
  static const _minTickGap = Duration(seconds: 45);
  static const _ijinCacheFor = Duration(minutes: 3);
  static final _dateKey = DateFormat('yyyy-MM-dd');
  static const _prefsBatteryDismissed = 'geofence_battery_opt_dismissed';

  static const _exitNotifId = 4401;
  static const _gpsNotifId = 4402;

  static const _fgTitleOk = 'Absensi aktif · lokasi dipantau';
  static const _fgTextOk =
      'Shift masih OPEN. Jangan force-stop app selama shift.';
  static const _fgTitleGps = 'GPS dimatikan · absensi terancam';
  static const _fgTextGps = 'Nyalakan lokasi selama shift aktif';

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
          '(HP terkunci / app lain), pilih “Izinkan sepanjang waktu” / '
          '“Allow all the time” pada langkah berikutnya.\n\n'
          'Pastikan juga notifikasi diizinkan — notifikasi “Absensi aktif · '
          'lokasi dipantau” menandakan pantauan masih jalan.\n\n'
          'Lokasi hanya dipantau saat shift masih OPEN, lalu berhenti otomatis '
          'setelah absen pulang.\n\n'
          'Batasan: force-stop app, cabut izin lokasi, atau optimasi baterai '
          'agresif tetap bisa menghentikan pantauan.',
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
      _gpsIssueActive = false;
      await _startForegroundStream();
      _timer?.cancel();
      _timer = Timer.periodic(_pollEvery, (_) => _tick());
      unawaited(_tick());
      if (permissionContext != null && permissionContext.mounted) {
        unawaited(_maybePromptBatteryOptimization(permissionContext));
      }
    } finally {
      _starting = false;
    }
  }

  /// Android: minta pengecualian optimasi baterai (sekali, bisa ditolak).
  Future<void> _maybePromptBatteryOptimization(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await AndroidBatteryOptimization.isIgnoring()) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsBatteryDismissed) == true) return;
      if (!context.mounted) return;

      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Optimasi baterai',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          content: const Text(
            'Agar pantauan lokasi tetap jalan saat layar mati, nonaktifkan '
            'optimasi baterai untuk Optik B. Riski (pilih “Tidak dioptimalkan” '
            '/ “Tidak ada batasan”).\n\n'
            'Ini tidak membuat app kebal force-stop — hanya mengurangi '
            'pematian otomatis oleh sistem.',
            style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'dismiss'),
              child: const Text('Jangan tanya lagi'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'later'),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'allow'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('Buka pengaturan'),
            ),
          ],
        ),
      );

      if (choice == 'dismiss') {
        await prefs.setBool(_prefsBatteryDismissed, true);
      } else if (choice == 'allow') {
        final ok = await AndroidBatteryOptimization.requestIgnore();
        if (!ok) await AndroidBatteryOptimization.openSettings();
      }
    } catch (e) {
      debugPrint('GeofenceExitMonitor battery prompt: $e');
    }
  }

  Future<void> _startForegroundStream({bool gpsIssue = false}) async {
    await _positionSub?.cancel();
    _positionSub = null;

    try {
      final settings = _locationSettingsForPlatform(gpsIssue: gpsIssue);
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
        (pos) => unawaited(_tick(position: pos)),
        onError: (Object e) {
          debugPrint('GeofenceExitMonitor position stream: $e');
          unawaited(_handleLocationUnavailableFromError(e));
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('GeofenceExitMonitor start stream: $e');
      unawaited(_handleLocationUnavailableFromError(e));
    }
  }

  LocationSettings _locationSettingsForPlatform({bool gpsIssue = false}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30,
        intervalDuration: _pollEvery,
        // Foreground service: tetap hidup saat app di background / layar mati
        // (selama sistem tidak force-stop / cabut izin).
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: gpsIssue ? _fgTitleGps : _fgTitleOk,
          notificationText: gpsIssue ? _fgTextGps : _fgTextOk,
          notificationChannelName: 'Absensi lokasi',
          setOngoing: true,
          enableWakeLock: true,
          enableWifiLock: true,
          notificationIcon: const AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        activityType: ActivityType.otherNavigation,
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
    _lastIjinCheckAt = null;
    _cachedHasApprovedLeave = null;
    _lastGpsAlertAt = null;
    _gpsIssueActive = false;
  }

  /// null = OK; 'gps_off' | 'permission_denied' jika tidak bisa pantau lokasi.
  Future<String?> _locationIssueReason() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return 'gps_off';

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'permission_denied';
    }
    return null;
  }

  Future<void> _handleLocationUnavailableFromError(Object e) async {
    final kid = _karyawanId;
    if (kid == null) return;

    String? reason = await _locationIssueReason();
    reason ??= _reasonFromLocationError(e);
    if (reason == null) return;

    await _onGpsOrPermissionIssue(karyawanId: kid, reason: reason);
  }

  String? _reasonFromLocationError(Object e) {
    final text = e.toString().toLowerCase();
    if (e is LocationServiceDisabledException ||
        text.contains('location service') ||
        text.contains('disabled')) {
      return 'gps_off';
    }
    if (e is PermissionDeniedException ||
        text.contains('permission') ||
        text.contains('denied')) {
      return 'permission_denied';
    }
    return null;
  }

  Future<void> _syncForegroundForGpsIssue(bool gpsIssue) async {
    if (_gpsIssueActive == gpsIssue) return;
    _gpsIssueActive = gpsIssue;
    // Restart stream agar teks foreground notification Android ikut berubah.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _startForegroundStream(gpsIssue: gpsIssue);
    }
  }

  /// Ijin/cuti APPROVED yang mencakup hari ini (tanggal lokal perangkat).
  @visibleForTesting
  Future<bool> hasApprovedLeaveCoveringNow(String karyawanId) async {
    if (karyawanId.isEmpty) return false;
    final today = _dateKey.format(DateTime.now());
    try {
      final row = await _db
          .from('jadwal_pengajuan')
          .select('id')
          .eq('karyawan_id', karyawanId)
          .eq('status', 'APPROVED')
          .inFilter('tipe', const ['IJIN', 'CUTI'])
          .eq('tanggal', today)
          .limit(1)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('GeofenceExitMonitor ijin check: $e');
      return false;
    }
  }

  Future<bool> _hasApprovedLeaveCached(String karyawanId) async {
    final now = DateTime.now();
    if (_cachedHasApprovedLeave != null &&
        _lastIjinCheckAt != null &&
        now.difference(_lastIjinCheckAt!) < _ijinCacheFor) {
      return _cachedHasApprovedLeave!;
    }
    final ok = await hasApprovedLeaveCoveringNow(karyawanId);
    _cachedHasApprovedLeave = ok;
    _lastIjinCheckAt = now;
    return ok;
  }

  /// Panggil saat app resume / cold start / buka absensi — restart jika
  /// masih ada shift OPEN. Jika sudah jalan, pastikan stream hidup + cek tick.
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
      if (_positionSub == null) {
        await _startForegroundStream(gpsIssue: _gpsIssueActive);
      }
      _timer ??= Timer.periodic(_pollEvery, (_) => _tick());
      unawaited(_tick());
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

      final locationIssue = await _locationIssueReason();
      if (locationIssue != null) {
        await _onGpsOrPermissionIssue(
          karyawanId: kid,
          reason: locationIssue,
        );
        return;
      }
      await _syncForegroundForGpsIssue(false);

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
        // Ijin/cuti disetujui hari ini → jangan peringatkan keluar area.
        final onLeave = await _hasApprovedLeaveCached(kid);
        if (!onLeave) {
          await _onExit(
            karyawanId: kid,
            tokoId: tid,
            lat: pos.latitude,
            lng: pos.longitude,
          );
        } else {
          debugPrint(
            'GeofenceExitMonitor: keluar area diabaikan (ijin/cuti APPROVED)',
          );
        }
      }
      _wasInside = inside;
    } catch (e) {
      debugPrint('GeofenceExitMonitor tick: $e');
      final reason = await _locationIssueReason() ??
          _reasonFromLocationError(e);
      if (reason != null) {
        await _onGpsOrPermissionIssue(karyawanId: kid, reason: reason);
      }
    } finally {
      _tickInFlight = false;
    }
  }

  Future<void> _onGpsOrPermissionIssue({
    required String karyawanId,
    required String reason,
  }) async {
    await _syncForegroundForGpsIssue(true);

    final onLeave = await _hasApprovedLeaveCached(karyawanId);
    if (onLeave) {
      debugPrint(
        'GeofenceExitMonitor: $reason diabaikan (ijin/cuti APPROVED)',
      );
      return;
    }

    final now = DateTime.now();
    if (_lastGpsAlertAt != null &&
        now.difference(_lastGpsAlertAt!) < _cooldown) {
      return;
    }
    _lastGpsAlertAt = now;

    final isGpsOff = reason == 'gps_off';
    await ensureNotificationsReady();
    await _notifications.show(
      _gpsNotifId,
      isGpsOff ? 'GPS dimatikan' : 'Izin lokasi dicabut',
      isGpsOff
          ? 'Nyalakan lokasi selama shift aktif. Absensi sedang dipantau.'
          : 'Izinkan lokasi selama shift aktif. Absensi sedang dipantau.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'geofence_gps',
          'GPS absensi',
          channelDescription: 'Peringatan GPS/izin lokasi saat shift',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    debugPrint('GeofenceExitMonitor: peringatan $reason dikirim');
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
      _exitNotifId,
      'Keluar area toko',
      'Anda keluar dari area toko saat shift masih aktif, tanpa ijin/cuti '
          'yang disetujui untuk hari ini. Segera kembali ke area toko.',
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
