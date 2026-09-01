import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../apps/karyawan/pengingat_page.dart';
import 'karyawan_deep_link.dart';
import 'karyawan_notif_prefs.dart';
import 'karyawan_push_service.dart';
import 'lab_job_service.dart';
import 'toko_antrian_realtime.dart';
import 'toko_antrian_service.dart';

/// Pantau antrian toko + lab + notifikasi in-app → notifikasi lokal.
///
/// Fondasi push (#1): tanpa Firebase Messaging, jalur lokal + Realtime
/// menutup foreground/background. Kill-state penuh menyusul FCM.
class KaryawanOpsWatch with WidgetsBindingObserver {
  KaryawanOpsWatch._();
  static final instance = KaryawanOpsWatch._();

  static const _prefsSnap = 'karyawan_ops_watch_snap_v1';
  static const _notifAntrian = 8201;
  static const _notifLab = 8202;
  static const _notifInbox = 8203;

  final _antrian = TokoAntrianService();
  final _lab = LabJobService();
  final _plugin = FlutterLocalNotificationsPlugin();

  TokoAntrianRealtimeSubscription? _rt;
  RealtimeChannel? _notifCh;
  Timer? _poll;
  String? _tokoId;
  String? _karyawanId;
  bool _ready = false;
  bool _running = false;
  bool _ticking = false;
  int? _lastAntrian;
  int? _lastLab;
  DateTime? _notifSince;
  DateTime? _lastPushTokoAt;

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
    await _bindNotifikasiRealtime(k);
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
    final ch = _notifCh;
    _notifCh = null;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
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

  Future<void> _bindNotifikasiRealtime(String karyawanId) async {
    final ch = _notifCh;
    _notifCh = null;
    if (ch != null) {
      try {
        await Supabase.instance.client.removeChannel(ch);
      } catch (_) {}
    }
    _notifSince = DateTime.now().toUtc();
    final channel = Supabase.instance.client
        .channel('karyawan-notif-$karyawanId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifikasi',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: karyawanId,
          ),
          callback: (payload) {
            if (!_running) return;
            unawaited(_onNotifInsert(payload.newRecord));
          },
        );
    _notifCh = channel;
    channel.subscribe();
  }

  Future<void> _onNotifInsert(Map<String, dynamic> row) async {
    final judul = (row['judul'] ?? 'Pengingat').toString().trim();
    final isi = (row['isi'] ?? '').toString().trim();
    final tipe = (row['tipe'] ?? 'INFO').toString().trim().toUpperCase();
    final kid = _karyawanId;
    if (kid == null || kid.isEmpty) return;

    final onDuty = await KaryawanNotifPrefs.isOnDuty(kid);
    if (tipe == 'SOP' && !await KaryawanNotifPrefs.wantSop(onDuty: onDuty)) {
      return;
    }
    if ((tipe == 'SHIFT' || judul.toLowerCase().contains('jadwal')) &&
        !await KaryawanNotifPrefs.wantShift(onDuty: onDuty)) {
      return;
    }

    final created = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (created != null &&
        _notifSince != null &&
        created.toUtc().isBefore(_notifSince!)) {
      return;
    }

    final payload = KaryawanDeepLink.encodeFromNotif(
      tipe: tipe,
      judul: judul,
      isi: isi,
    );
    await _show(
      id: _notifInbox + (judul.hashCode.abs() % 90),
      title: judul.isEmpty ? 'Pengingat' : judul,
      body: isi.isEmpty ? 'Ada update baru di Pengingat.' : isi,
      payload: payload,
    );
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
        final payload = KaryawanDeepLink.encode(
          dest: PengingatDest.antrian,
        );
        await _show(
          id: _notifAntrian,
          title: 'Antrian toko',
          body: delta == 1
              ? 'Ada 1 pekerjaan baru di antrian lantai toko.'
              : 'Ada $delta pekerjaan baru di antrian lantai toko.',
          payload: payload,
        );
        _maybeNotifyToko(
          tokoId: toko,
          judul: 'Antrian toko',
          isi: delta == 1
              ? 'Ada 1 pekerjaan baru di antrian lantai toko.'
              : 'Ada $delta pekerjaan baru di antrian lantai toko.',
          tipe: 'ANTRIAN',
        );
      }
      if (labN > _lastLab!) {
        final delta = labN - _lastLab!;
        final payload = KaryawanDeepLink.encode(dest: PengingatDest.lab);
        await _show(
          id: _notifLab,
          title: 'Antrian lab',
          body: delta == 1
              ? 'Ada 1 job lab baru siap diklaim.'
              : 'Ada $delta job lab baru siap diklaim.',
          payload: payload,
        );
        _maybeNotifyToko(
          tokoId: toko,
          judul: 'Antrian lab',
          isi: delta == 1
              ? 'Ada 1 job lab baru siap diklaim.'
              : 'Ada $delta job lab baru siap diklaim.',
          tipe: 'LAB',
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

  void _maybeNotifyToko({
    required String tokoId,
    required String judul,
    required String isi,
    required String tipe,
  }) {
    final now = DateTime.now();
    final last = _lastPushTokoAt;
    if (last != null && now.difference(last) < const Duration(seconds: 25)) {
      return;
    }
    _lastPushTokoAt = now;
    unawaited(
      KaryawanPushService.instance.notifyToko(
        tokoId: tokoId,
        judul: judul,
        isi: isi,
        tipe: tipe,
      ),
    );
  }

  Future<void> _ensureNotif() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (response) {
          KaryawanDeepLink.emitFromPayload(response.payload);
        },
      );
    } catch (e) {
      debugPrint('KaryawanOpsWatch.notif: $e');
    }
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
    String? payload,
  }) async {
    if (kIsWeb) return;
    const android = AndroidNotificationDetails(
      'karyawan_ops',
      'Antrian toko',
      channelDescription: 'Pickup, booking, online, lab, pengingat',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
      payload: payload,
    );
  }
}
