import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';
import '../config.dart';
import '../logistics/stock_realtime.dart';
import '../tenant/tenant_modules.dart';
import '../tenant/tenant_service.dart';

/// Paksa soft-sync data **cabang** ke semua client usaha (Admin / Karyawan / Member / Store).
///
/// Dipakai bila sync otomatis (mis. stok setelah POS) diduga gagal — memaksa
/// semua APK/web menarik ulang data cabang yang sama.
///
/// **Bukan** jalur kebocoran stok — tidak menulis ledger / qty rak.
class ClientForceSync {
  ClientForceSync._();

  static const eventForceSync = 'force_sync';

  /// Unik per proses app — broadcast sendiri diabaikan (hindari loop reload).
  /// Catatan web: `1 << 32` jadi 0 di JS → nextInt(0) melempar RangeError.
  static final String originId =
      '${currentFlavor.name}-${DateTime.now().microsecondsSinceEpoch}-'
      '${Random().nextInt(0x7fffffff)}';

  /// Event terakhir (setelah filter toko) — halaman POS/stok bisa listen & refetch.
  static final ValueNotifier<ClientForceSyncEvent?> lastAppliedEvent =
      ValueNotifier<ClientForceSyncEvent?>(null);

  static RealtimeChannel? _channel;
  static String? _boundTenantId;
  static String? _localTokoId;
  static void Function(ClientForceSyncEvent event)? _onRemote;
  static bool _softRefreshing = false;

  static String topicForTenant(String tenantId) {
    final t = tenantId.trim().toLowerCase();
    return 'obr-force-sync-$t';
  }

  static ClientForceSyncEvent? parsePayload(Map<dynamic, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    final inner = m['payload'];
    if (inner is Map) {
      m.addAll(Map<String, dynamic>.from(inner));
    }
    final tenantId = (m['tenant_id'] ?? '').toString().trim();
    final origin = (m['origin_id'] ?? '').toString().trim();
    if (tenantId.isEmpty || origin.isEmpty) return null;
    final toko = (m['toko_id'] ?? '').toString().trim().toUpperCase();
    return ClientForceSyncEvent(
      tenantId: tenantId,
      originId: origin,
      source: (m['source'] ?? '').toString(),
      ts: (m['ts'] ?? '').toString(),
      tokoId: toko.isEmpty ? null : toko,
    );
  }

  /// True bila event cabang relevan untuk toko lokal perangkat ini.
  /// `*`, `ALL`, atau kosong = semua cabang (force sync dari Pusat).
  static bool appliesToLocalToko(
    ClientForceSyncEvent ev, {
    String? localTokoId,
  }) {
    final target = (ev.tokoId ?? '').trim().toUpperCase();
    if (target.isEmpty || target == '*' || target == 'ALL') return true;
    final local = (localTokoId ?? _localTokoId ?? '').trim();
    if (local.isEmpty) return true;
    final aliases = AttendanceAdminScope.storeIdAliases(local)
        .map((e) => e.toUpperCase())
        .toSet();
    if (aliases.isEmpty) {
      return target == local.toUpperCase();
    }
    return aliases.contains(target);
  }

  static bool isAllBranchesToko(String? tokoId) {
    final t = (tokoId ?? '').trim().toUpperCase();
    return t.isEmpty || t == '*' || t == 'ALL';
  }

  /// Soft-refresh lokal: modul tenant. Tidak hard-reload, tidak ubah stok.
  ///
  /// Sengaja **tanpa** `refreshSession`: gagal refresh bisa sign-out dan
  /// melempar user ke layar login (terlihat sebagai “sync merusak sesi”).
  static Future<void> softRefreshLocal() async {
    if (_softRefreshing) return;
    _softRefreshing = true;
    try {
      if (!isRekasaStorefront) {
        try {
          await TenantModules.instance.load();
        } catch (e) {
          debugPrint('ClientForceSync TenantModules: $e');
        }
      }
    } finally {
      _softRefreshing = false;
    }
  }

  /// Bangunkan listener stok cabang (POS / master / member catalog).
  static Future<void> pingStockChannel(String tokoId) async {
    if (isAllBranchesToko(tokoId)) return;
    final aliases = AttendanceAdminScope.storeIdAliases(tokoId);
    final targets = aliases.isEmpty
        ? [tokoId.trim().toUpperCase()]
        : aliases.map((e) => e.toUpperCase()).toList();
    for (final t in targets) {
      if (t.isEmpty) continue;
      try {
        await StockRealtime.broadcastToko(
          tokoId: t,
          sku: '*FORCE_SYNC*',
        );
      } catch (e) {
        debugPrint('ClientForceSync stock ping $t: $e');
      }
    }
  }

  /// Ping stok semua toko di daftar (Pusat → semua cabang).
  ///
  /// Parallel + batas waktu: serial per toko (subscribe realtime ~detik)
  /// membuat tombol sync Pusat terasa “hang” tanpa snackbar sukses.
  static Future<void> pingStockChannels(
    Iterable<String> tokoIds, {
    int concurrency = 6,
    Duration timeBudget = const Duration(seconds: 12),
  }) async {
    final seen = <String>{};
    final targets = <String>[];
    for (final raw in tokoIds) {
      final t = raw.trim().toUpperCase();
      if (t.isEmpty || isAllBranchesToko(t)) continue;
      if (!seen.add(t)) continue;
      targets.add(t);
    }
    if (targets.isEmpty) return;

    final limit = concurrency < 1 ? 1 : concurrency;
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= targets.length) return;
        await pingStockChannel(targets[i]);
      }
    }

    try {
      await Future.wait(
        List.generate(limit.clamp(1, targets.length), (_) => worker()),
      ).timeout(timeBudget);
    } on TimeoutException {
      debugPrint(
        'ClientForceSync pingStockChannels: time budget ${timeBudget.inSeconds}s '
        '(${targets.length} toko) — broadcast force_sync sudah terkirim',
      );
    } catch (e) {
      debugPrint('ClientForceSync pingStockChannels: $e');
    }
  }

  /// Kirim sinyal cabang ke semua client tenant yang subscribe.
  static Future<void> publish({
    required String tenantId,
    required String tokoId,
    String source = 'admin',
  }) async {
    final tid = tenantId.trim();
    final toko = tokoId.trim().toUpperCase();
    if (tid.isEmpty || toko.isEmpty) return;
    final client = Supabase.instance.client;
    final channel = client.channel(topicForTenant(tid));
    try {
      final ready = Completer<void>();
      channel.subscribe((status, err) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (!ready.isCompleted) ready.complete();
        } else if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!ready.isCompleted) {
            ready.completeError(err ?? status);
          }
        }
      });
      await ready.future.timeout(const Duration(seconds: 8));
      await channel.sendBroadcastMessage(
        event: eventForceSync,
        payload: {
          'tenant_id': tid,
          'toko_id': toko,
          'origin_id': originId,
          'source': source,
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (e) {
      debugPrint('ClientForceSync publish: $e');
    } finally {
      // Jangan biarkan removeChannel menggantung tombol sync Pusat.
      try {
        await client
            .removeChannel(channel)
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        try {
          unawaited(client.removeChannel(channel));
        } catch (_) {}
      }
    }
  }

  /// Dengarkan broadcast tenant. [localTokoId] memfilter event cabang lain.
  static Future<void> bind({
    required String tenantId,
    String? localTokoId,
    void Function(ClientForceSyncEvent event)? onRemote,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      await unbind();
      return;
    }
    final local = (localTokoId ?? '').trim().toUpperCase();
    if (_boundTenantId == tid &&
        _channel != null &&
        (_localTokoId ?? '') == local) {
      _onRemote = onRemote;
      return;
    }
    await unbind();
    _boundTenantId = tid;
    _localTokoId = local.isEmpty ? null : local;
    _onRemote = onRemote;
    final client = Supabase.instance.client;
    final channel = client.channel(topicForTenant(tid));
    _channel = channel;
    channel.onBroadcast(
      event: eventForceSync,
      callback: (payload) {
        final ev = parsePayload(payload);
        if (ev == null) return;
        if (ev.originId == originId) return;
        if (ev.tenantId.trim().toLowerCase() != tid.toLowerCase()) return;
        if (!appliesToLocalToko(ev, localTokoId: _localTokoId)) return;
        unawaited(_handleRemote(ev));
      },
    );
    channel.subscribe();
  }

  static Future<void> bindFromTenantService({
    String? localTokoId,
    void Function(ClientForceSyncEvent event)? onRemote,
  }) async {
    final tid = (TenantService.instance.id ?? '').trim();
    if (tid.isEmpty) {
      await unbind();
      return;
    }
    await bind(
      tenantId: tid,
      localTokoId: localTokoId,
      onRemote: onRemote,
    );
  }

  static Future<void> unbind() async {
    final ch = _channel;
    _channel = null;
    _boundTenantId = null;
    _localTokoId = null;
    _onRemote = null;
    if (ch == null) return;
    try {
      await Supabase.instance.client.removeChannel(ch);
    } catch (_) {}
  }

  static Future<void> _handleRemote(ClientForceSyncEvent event) async {
    await softRefreshLocal();
    final toko = (event.tokoId ?? '').trim();
    try {
      if (isAllBranchesToko(toko)) {
        // Pusat → semua cabang: bangunkan channel stok toko lokal perangkat ini.
        final local = (_localTokoId ?? '').trim();
        if (local.isNotEmpty) await pingStockChannel(local);
      } else if (toko.isNotEmpty) {
        await pingStockChannel(toko);
      }
    } catch (_) {}
    lastAppliedEvent.value = event;
    try {
      _onRemote?.call(event);
    } catch (e) {
      debugPrint('ClientForceSync onRemote: $e');
    }
  }
}

class ClientForceSyncEvent {
  const ClientForceSyncEvent({
    required this.tenantId,
    required this.originId,
    required this.source,
    required this.ts,
    this.tokoId,
  });

  final String tenantId;
  final String originId;
  final String source;
  final String ts;
  /// Cabang yang dipaksa sinkron (POS/stok/nota toko ini).
  final String? tokoId;
}
