import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'karyawan_deep_link.dart';

/// Background isolate — wajib top-level untuk FCM kill-state.
@pragma('vm:entry-point')
Future<void> karyawanFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  try {
    final title = message.notification?.title ??
        message.data['judul']?.toString() ??
        'Pengingat';
    final body =
        message.notification?.body ?? message.data['isi']?.toString() ?? '';
    final payload = _payloadFromRemoteMessage(message);
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    const details = AndroidNotificationDetails(
      KaryawanPushService.channelId,
      'Push Karyawan',
      channelDescription: 'FCM antrian / jadwal / pengaduan',
      importance: Importance.high,
      priority: Priority.high,
    );
    await plugin.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: details,
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  } catch (e) {
    debugPrint('karyawan FCM bg show: $e');
  }
}

String _payloadFromRemoteMessage(RemoteMessage message) {
  final data = message.data;
  final existing = (data['payload'] ?? '').toString().trim();
  if (existing.isNotEmpty) return existing;
  return KaryawanDeepLink.encodeFromNotif(
    tipe: data['tipe']?.toString(),
    judul: data['judul']?.toString() ?? message.notification?.title,
    isi: data['isi']?.toString() ?? message.notification?.body,
  );
}

/// Push Karyawan: FCM bila Firebase terkonfigurasi, else token `local:`.
///
/// Aktifkan kill-state:
/// 1. Taruh `android/app/google-services.json` (isi dari Firebase Console;
///    lihat `google-services.json.example`).
/// 2. iOS: `ios/Runner/GoogleService-Info.plist` + APNs key di Firebase.
/// 3. Edge secret `FCM_SERVER_KEY` atau `FCM_SERVICE_ACCOUNT_JSON` untuk
///    function `karyawan-push-dispatch`.
class KaryawanPushService {
  KaryawanPushService._();
  static final instance = KaryawanPushService._();

  static const _deviceKey = 'karyawan_push_device_id_v1';
  static const channelId = 'karyawan_fcm';
  static bool _firebaseReady = false;
  static bool _handlersBound = false;
  static bool _openHandlersBound = false;
  bool _registered = false;

  final _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  /// Init Firebase + permission. Aman dipanggil tanpa google-services.
  static Future<bool> ensureFirebase() async {
    if (kIsWeb) return false;
    if (_firebaseReady) return true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(
        karyawanFirebaseMessagingBackgroundHandler,
      );
      _firebaseReady = true;
      return true;
    } catch (e) {
      debugPrint('KaryawanPushService.Firebase: $e');
      return false;
    }
  }

  Future<void> _ensureLocalNotif() async {
    if (_localReady || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    try {
      await _local.initialize(
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
      debugPrint('KaryawanPushService.localNotif: $e');
    }
    _localReady = true;
  }

  Future<void> _bindOpenAppHandlers() async {
    if (_openHandlersBound || !_firebaseReady) return;
    _openHandlersBound = true;

    void route(RemoteMessage msg) {
      KaryawanDeepLink.emitFromPayload(_payloadFromRemoteMessage(msg));
    }

    FirebaseMessaging.onMessageOpenedApp.listen(route);
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) route(initial);
    } catch (e) {
      debugPrint('KaryawanPushService.getInitialMessage: $e');
    }
  }

  Future<void> _bindForegroundHandlers() async {
    if (_handlersBound || !_firebaseReady) return;
    _handlersBound = true;
    await _ensureLocalNotif();
    await _bindOpenAppHandlers();
    FirebaseMessaging.onMessage.listen((msg) async {
      final title = msg.notification?.title ??
          msg.data['judul']?.toString() ??
          'Pengingat';
      final body =
          msg.notification?.body ?? msg.data['isi']?.toString() ?? '';
      final payload = _payloadFromRemoteMessage(msg);
      if (kIsWeb) return;
      const android = AndroidNotificationDetails(
        channelId,
        'Push Karyawan',
        channelDescription: 'FCM antrian / jadwal / pengaduan',
        importance: Importance.high,
        priority: Priority.high,
      );
      await _local.show(
        msg.hashCode,
        title,
        body,
        const NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    });
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id =
          '${DateTime.now().millisecondsSinceEpoch}-${List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join()}';
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  String get _platform {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
    } catch (_) {}
    return defaultTargetPlatform.name;
  }

  Future<String> _resolveToken() async {
    final ready = await ensureFirebase();
    if (ready) {
      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        await _bindForegroundHandlers();
        final fcm = await messaging.getToken();
        if (fcm != null && fcm.trim().isNotEmpty) {
          messaging.onTokenRefresh.listen((t) {
            if (t.trim().isEmpty) return;
            unawaited(_upsert(t.trim(), platform: _platform));
          });
          return fcm.trim();
        }
      } catch (e) {
        debugPrint('KaryawanPushService.FCM token: $e');
      }
    }
    final device = await _deviceId();
    return 'local:$device';
  }

  Future<bool> _upsert(String token, {required String platform}) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return false;
    final res = await client.rpc(
      'upsert_karyawan_push_token',
      params: {
        'p_token': token,
        'p_platform': platform,
      },
    );
    return res is Map && res['ok'] == true;
  }

  /// Daftarkan token FCM (atau `local:`) ke Supabase.
  Future<bool> registerIfPossible() async {
    if (_registered) return true;
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return false;
    try {
      final token = await _resolveToken();
      final ok = await _upsert(token, platform: _platform);
      if (ok) _registered = true;
      // Pastikan open-app handlers terpasang meski FCM token gagal.
      if (_firebaseReady) unawaited(_bindOpenAppHandlers());
      return ok;
    } catch (e) {
      debugPrint('KaryawanPushService.register: $e');
      return false;
    }
  }

  /// Broadcast in-app ke staf cabang + best-effort FCM via Edge Function.
  Future<int> notifyToko({
    required String tokoId,
    required String judul,
    required String isi,
    String tipe = 'INFO',
  }) async {
    final t = tokoId.trim();
    if (t.isEmpty) return 0;
    var n = 0;
    final payload = KaryawanDeepLink.encodeFromNotif(
      tipe: tipe,
      judul: judul,
      isi: isi,
    );
    try {
      final res = await Supabase.instance.client.rpc(
        'notify_toko_karyawan',
        params: {
          'p_toko': t,
          'p_judul': judul,
          'p_isi': isi,
          'p_tipe': tipe,
        },
      );
      if (res is int) {
        n = res;
      } else if (res is num) {
        n = res.toInt();
      } else {
        n = int.tryParse('$res') ?? 0;
      }
    } catch (e) {
      debugPrint('KaryawanPushService.notifyToko: $e');
    }
    try {
      await Supabase.instance.client.functions.invoke(
        'karyawan-push-dispatch',
        body: {
          'toko_id': t,
          'judul': judul,
          'isi': isi,
          'tipe': tipe,
          'payload': payload,
        },
      );
    } catch (e) {
      debugPrint('KaryawanPushService.dispatch: $e');
    }
    return n;
  }
}
