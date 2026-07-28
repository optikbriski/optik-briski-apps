import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../invoice/invoice_hub_service.dart';
import 'member_repository.dart';
import 'member_session.dart';

/// Poll status pesanan Member → notifikasi lokal tiap perubahan.
class MemberStatusWatch {
  MemberStatusWatch._();
  static final MemberStatusWatch instance = MemberStatusWatch._();

  static const _prefsKey = 'member_status_snapshot_v1';
  static const _notifId = 7101;

  final _repo = MemberRepository();
  final _plugin = FlutterLocalNotificationsPlugin();
  Timer? _timer;
  bool _ready = false;

  Future<void> start() async {
    await _ensureNotif();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => tick());
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ensureNotif() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _ready = true;
  }

  Future<void> tick() async {
    final session = MemberSession.instance;
    if (!session.isLoggedIn) return;
    final phone = session.phoneForQuery;
    if (phone.isEmpty) return;

    final sales = await _repo.listSales(phone);
    final prefs = await SharedPreferences.getInstance();
    final prevRaw = prefs.getString(_prefsKey);
    final prev = <String, String>{};
    if (prevRaw != null) {
      try {
        final m = jsonDecode(prevRaw) as Map<String, dynamic>;
        m.forEach((k, v) => prev[k] = v.toString());
      } catch (_) {}
    }

    final next = <String, String>{};
    for (final s in sales) {
      final inv = (s['no_invoice'] ?? '').toString();
      if (inv.isEmpty) continue;
      final hubLike = {
        'tracking_status': s['tracking_status'],
        'diambil_at': s['diambil_at'],
        'status_pembayaran': s['status_pembayaran'],
      };
      final label = InvoiceHubService.statusLabel(hubLike);
      final key = '$inv|${s['status_pembayaran']}|$label';
      next[inv] = key;
      final old = prev[inv];
      if (old != null && old != key) {
        await _plugin.show(
          _notifId + inv.hashCode.abs() % 1000,
          'Update pesanan $inv',
          label,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'member_order_status',
              'Status pesanan Member',
              channelDescription: 'Perubahan status kacamata / pesanan',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(next));
  }
}
