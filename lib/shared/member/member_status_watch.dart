import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../invoice/invoice_hub_service.dart';
import '../whatsapp_launcher.dart';
import 'member_inbox_unread.dart';
import 'member_realtime.dart';
import 'member_repository.dart';
import 'member_session.dart';

/// Pantau status pesanan Member → notifikasi lokal + refresh UI.
///
/// **Realtime dulu** (Broadcast channel per WA), poll jarang sebagai cadangan
/// karena Member login lokal — postgres_changes di `sales` sering diblok RLS.
class MemberStatusWatch with WidgetsBindingObserver {
  MemberStatusWatch._();
  static final MemberStatusWatch instance = MemberStatusWatch._();

  static const _prefsKey = 'member_status_snapshot_v2';
  static const _seenAlertsKey = 'member_alert_seen_ids_v1';
  static const _notifId = 7101;

  final _repo = MemberRepository();
  final _plugin = FlutterLocalNotificationsPlugin();
  final _refreshController = StreamController<void>.broadcast();

  Timer? _timer;
  RealtimeChannel? _broadcastChannel;
  bool _ready = false;
  bool _ticking = false;
  bool _lifecycleAttached = false;
  bool _broadcastLive = false;

  /// UI (nota / daftar pesanan) bisa listen untuk reload.
  Stream<void> get onRefresh => _refreshController.stream;

  Future<void> start() async {
    await _ensureNotif();
    _attachLifecycle();
    await _bindBroadcast();
    _restartPollTimer();
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_teardownBroadcast());
  }

  void _restartPollTimer() {
    _timer?.cancel();
    // Broadcast hidup → poll jarang (cadangan). Belum → lebih sering.
    final every = _broadcastLive
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _timer = Timer.periodic(every, (_) => tick());
  }

  void _attachLifecycle() {
    if (_lifecycleAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _lifecycleAttached = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_bindBroadcast());
      unawaited(tick());
    }
  }

  Future<void> _ensureNotif() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
    } catch (_) {}
    _ready = true;
  }

  Future<void> _teardownBroadcast() async {
    final ch = _broadcastChannel;
    _broadcastChannel = null;
    _broadcastLive = false;
    if (ch == null) return;
    try {
      await Supabase.instance.client.removeChannel(ch);
    } catch (_) {
      try {
        await ch.unsubscribe();
      } catch (_) {}
    }
  }

  Future<void> _bindBroadcast() async {
    final session = MemberSession.instance;
    if (!session.isLoggedIn) return;
    final phone = session.phoneForQuery;
    final digits = normalizeWaNumber(phone);
    if (digits.length < 8) return;

    final topic = MemberRealtime.topicForPhone(phone);
    // Sudah subscribe topic yang sama.
    if (_broadcastChannel != null && _broadcastLive) return;

    await _teardownBroadcast();

    try {
      final channel = Supabase.instance.client.channel(topic);
      channel.onBroadcast(
        event: MemberRealtime.eventOrderUpdate,
        callback: (payload) {
          unawaited(_onBroadcast(payload));
        },
      );
      final ready = Completer<void>();
      channel.subscribe((status, err) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _broadcastLive = true;
          if (!ready.isCompleted) ready.complete();
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _broadcastLive = false;
          if (!ready.isCompleted) ready.complete();
        }
      });
      await ready.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
      _broadcastChannel = channel;
      _restartPollTimer();
    } catch (_) {
      _broadcastLive = false;
      _restartPollTimer();
    }
  }

  Future<void> _onBroadcast(Map<String, dynamic> payload) async {
    // Beberapa frame membungkus data di key `payload`.
    final data = payload['payload'] is Map
        ? Map<String, dynamic>.from(payload['payload'] as Map)
        : payload;
    final title = (data['title'] ?? 'Update pesanan').toString();
    final body = (data['body'] ?? data['no_invoice'] ?? '').toString();
    final inv = (data['no_invoice'] ?? '').toString();
    await _showLocal(
      id: _notifId + (inv.isEmpty ? title : inv).hashCode.abs() % 2000,
      title: title,
      body: body.length > 180 ? '${body.substring(0, 180)}…' : body,
    );
    _refreshController.add(null);
    // Sinkron snapshot / inbox agar tidak dobel notif dari poll.
    unawaited(tick());
  }

  Future<void> tick() async {
    if (_ticking) return;
    final session = MemberSession.instance;
    if (!session.isLoggedIn) return;
    final phone = session.phoneForQuery;
    if (phone.isEmpty) return;

    _ticking = true;
    try {
      await _tickSalesStatus(phone);
      await _tickInboxAlerts(phone);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickSalesStatus(String phone) async {
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
    var changed = false;
    for (final s in sales) {
      final inv = (s['no_invoice'] ?? '').toString();
      if (inv.isEmpty) continue;
      final hubLike = {
        'tracking_status': s['tracking_status'],
        'diambil_at': s['diambil_at'],
        'status_pembayaran': s['status_pembayaran'],
      };
      final label = InvoiceHubService.statusLabel(hubLike);
      final dpTok = (s['has_qr_dp'] == true ||
              (s['qr_dp_token'] ?? '').toString().length >= 8)
          ? '1'
          : '0';
      final lnTok = (s['has_qr_lunas'] == true ||
              (s['qr_lunas_token'] ?? '').toString().length >= 8)
          ? '1'
          : '0';
      final key =
          '$inv|${s['status_pembayaran']}|${s['tracking_status']}|$label|$dpTok|$lnTok';
      next[inv] = key;
      final old = prev[inv];
      if (old != null && old != key) {
        changed = true;
        // Kalau broadcast sudah hidup, skip notif status (hindari dobel);
        // tetap refresh UI.
        if (!_broadcastLive) {
          await _showLocal(
            id: _notifId + inv.hashCode.abs() % 1000,
            title: 'Update pesanan $inv',
            body: label,
          );
        }
      } else if (old == null && prev.isNotEmpty) {
        changed = true;
      }
    }

    await prefs.setString(_prefsKey, jsonEncode(next));
    if (changed) _refreshController.add(null);
  }

  Future<void> _tickInboxAlerts(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final seenRaw = prefs.getStringList(_seenAlertsKey) ?? <String>[];
    final seen = seenRaw.toSet();

    List<Map<String, dynamic>> alerts;
    try {
      final res = await Supabase.instance.client.rpc(
        'list_member_order_alerts',
        params: {'p_phone': phone},
      );
      alerts = _asMapList(res);
    } catch (_) {
      return;
    }

    var anyNew = false;
    for (final a in alerts) {
      final id = (a['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      anyNew = true;
      // Broadcast biasanya sudah menampilkan notif yang sama.
      if (!_broadcastLive) {
        final title = (a['title'] ?? 'Update pesanan').toString();
        final body = (a['body'] ?? '').toString();
        await _showLocal(
          id: _notifId + id.hashCode.abs() % 2000,
          title: title,
          body: body.length > 180 ? '${body.substring(0, 180)}…' : body,
        );
      }
    }

    if (anyNew) {
      final trimmed =
          seen.toList().reversed.take(200).toList().reversed.toList();
      await prefs.setStringList(_seenAlertsKey, trimmed);
      _refreshController.add(null);
    }
    // Selalu sync badge Inbox (read state terpisah dari dedupe push).
    try {
      await MemberInboxUnread.instance.refresh();
    } catch (_) {}
  }

  List<Map<String, dynamic>> _asMapList(dynamic res) {
    if (res is List) {
      return res
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (res is String && res.isNotEmpty) {
      try {
        final decoded = jsonDecode(res);
        return _asMapList(decoded);
      } catch (_) {}
    }
    return const [];
  }

  Future<void> _showLocal({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _plugin.show(
        id,
        title,
        body,
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
    } catch (_) {}
  }
}
