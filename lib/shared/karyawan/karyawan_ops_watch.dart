import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'lab_job_service.dart';
import 'toko_antrian_realtime.dart';
import 'toko_antrian_service.dart';

/// Pantau antrian toko + lab → notifikasi lokal saat ada pekerjaan baru.
///
/// Bukan FCM cloud (belum ada Firebase Messaging di proyek). Bekerja saat app
/// foreground/background (best-effort), mirip geofence / Member status watch.
class KaryawanOpsWatch with WidgetsBindingObserver {
  KaryawanOpsWatch._();
  static final instance = KaryawanOpsWatch._();

  static const _prefsSnap = 'karyawan_ops_watch_snap_v1';
  static const _notifAntrian = 8201;
  static const _notifLab = 8202;

  final _antrian = TokoAntrianService();
  final _lab = LabJobService();
  final _plugin = FlutterLocalNotificationsPlugin();

  TokoAntrianRealtimeSubscription? _rt;
  Timer? _poll;
  String? _tokoId;
  String? _karyawanId;
  bool _ready = false;
  bool _running = false;
  bool _ticking = false;
  int? _lastAntrian;
  int? _lastLab;

  Future<void> start({
    required String tokoId,
    required String karyawanId,
  }) async {
    final t = tokoId.trim();
    final k = karyawanId.trim();
    if (t.isEmpty || k.isEmpty) return;
    _tokoId = t;
    _karyawanId = k;
    await _ensureNotif();
    WidgetsBinding.instance.addObserver(this);
    _running = true;
    await _rt?.dispose();
    _rt = TokoAntrianRealtime.subscribeToko(
      tokoId: t,
      onChanged: () {
        if (_running) unawaited(tick());
      },
    );
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_running) unawaited(tick());
    });
    unawaited(tick(seedOnly: true));
  }

  Future<void> stop() async {
    _running = false;
    _poll?.cancel();
    _poll = null;
    await _rt?.dispose();
    _rt = null;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running) {
      unawaited(tick());
    }
  }

  Future<void> tick({bool seedOnly = false}) async {
    if (_ticking || !_running) return;
    final toko = _tokoId;
    final kid = _karyawanId;
    if (toko == null || kid == null) return;
    _ticking = true;
    try {
      final antrian = await _antrian.loadDetailed(tokoId: toko);
      final antrianN = antrian.items.length;
      var labN = 0;
      try {
        final labs = await _lab.listOpenForToko(toko);
        labN = labs.length;
      } catch (_) {}

      if (seedOnly || _lastAntrian == null || _lastLab == null) {
        _lastAntrian = antrianN;
        _lastLab = labN;
        await _persist();
        return;
      }

      if (antrianN > _lastAntrian!) {
        final delta = antrianN - _lastAntrian!;
        await _show(
          id: _notifAntrian,
          title: 'Antrian toko',
          body: delta == 1
              ? 'Ada 1 pekerjaan baru di antrian lantai toko.'
              : 'Ada $delta pekerjaan baru di antrian lantai toko.',
        );
      }
      if (labN > _lastLab!) {
        final delta = labN - _lastLab!;
        await _show(
          id: _notifLab,
          title: 'Antrian lab',
          body: delta == 1
              ? 'Ada 1 job lab baru siap diklaim.'
              : 'Ada $delta job lab baru siap diklaim.',
        );
      }
      _lastAntrian = antrianN;
      _lastLab = labN;
      await _persist();
    } catch (e) {
      debugPrint('KaryawanOpsWatch: $e');
    } finally {
      _ticking = false;
    }
  }

  Future<void> _ensureNotif() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsSnap);
    if (raw != null && raw.contains('|')) {
      final parts = raw.split('|');
      _lastAntrian = int.tryParse(parts[0]);
      _lastLab = int.tryParse(parts[1]);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsSnap,
      '${_lastAntrian ?? 0}|${_lastLab ?? 0}',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    const android = AndroidNotificationDetails(
      'karyawan_ops',
      'Antrian toko',
      channelDescription: 'Pickup, booking, online, lab',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }
}
