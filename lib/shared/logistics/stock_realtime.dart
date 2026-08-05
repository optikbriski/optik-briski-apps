import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Payload perubahan stok (broadcast DB / postgres_changes).
class StockRealtimeEvent {
  const StockRealtimeEvent({
    required this.tokoId,
    required this.sku,
    this.stock,
    this.reservedQty,
    this.availableQty,
  });

  final String tokoId;
  final String sku;
  final int? stock;
  final int? reservedQty;
  final int? availableQty;

  factory StockRealtimeEvent.fromMap(Map<String, dynamic> raw) {
    final m = Map<String, dynamic>.from(raw);
    // Broadcast kadang wrap di 'payload'.
    final inner = m['payload'];
    if (inner is Map) {
      m.addAll(Map<String, dynamic>.from(inner));
    }
    return StockRealtimeEvent(
      tokoId: (m['toko_id'] ?? '').toString().trim().toUpperCase(),
      sku: (m['sku'] ?? '').toString().trim().toUpperCase(),
      stock: int.tryParse('${m['stock'] ?? ''}'),
      reservedQty: int.tryParse('${m['reserved_qty'] ?? ''}'),
      availableQty: int.tryParse('${m['available_qty'] ?? ''}'),
    );
  }
}

typedef StockRealtimeHandler = void Function(StockRealtimeEvent event);

/// Subscribe stok realtime per toko (broadcast + postgres_changes).
class StockRealtime {
  StockRealtime._();

  static String topicForToko(String tokoId) =>
      'obr-stock-${tokoId.trim().toUpperCase()}';

  /// Dengarkan perubahan stok di [tokoId].
  /// Panggil [dispose] pada subscription saat halaman ditutup.
  static StockRealtimeSubscription subscribeToko({
    required String tokoId,
    required StockRealtimeHandler onEvent,
    bool includePostgresChanges = true,
  }) {
    final toko = tokoId.trim().toUpperCase();
    final client = Supabase.instance.client;
    final topic = topicForToko(toko);
    final channel = client.channel(topic);

    channel.onBroadcast(
      event: 'stock_changed',
      callback: (payload) {
        try {
          final ev = StockRealtimeEvent.fromMap(
            Map<String, dynamic>.from(payload),
          );
          if (ev.tokoId.isEmpty) {
            onEvent(StockRealtimeEvent(
              tokoId: toko,
              sku: ev.sku,
              stock: ev.stock,
              reservedQty: ev.reservedQty,
              availableQty: ev.availableQty,
            ));
          } else {
            onEvent(ev);
          }
        } catch (e) {
          debugPrint('StockRealtime broadcast parse: $e');
        }
      },
    );

    if (includePostgresChanges) {
      // Filter di client (toko_id di DB bisa beda casing).
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'products',
        callback: (payload) {
          try {
            final row = payload.newRecord;
            if (row.isEmpty) return;
            final rowToko =
                (row['toko_id'] ?? '').toString().trim().toUpperCase();
            if (rowToko != toko) return;
            onEvent(StockRealtimeEvent.fromMap(
              Map<String, dynamic>.from(row),
            ));
          } catch (e) {
            debugPrint('StockRealtime pg parse: $e');
          }
        },
      );
    }

    channel.subscribe();
    return StockRealtimeSubscription._(client, channel);
  }

  /// Owner/Pusat: semua toko via postgres_changes (tanpa filter).
  static StockRealtimeSubscription subscribeAllProducts({
    required StockRealtimeHandler onEvent,
  }) {
    final client = Supabase.instance.client;
    final channel = client.channel('obr-stock-all-products');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'products',
      callback: (payload) {
        try {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final m = Map<String, dynamic>.from(row);
          // Hanya peduli kolom stok.
          if (!m.containsKey('stock') && !m.containsKey('reserved_qty')) {
            return;
          }
          onEvent(StockRealtimeEvent.fromMap(m));
        } catch (e) {
          debugPrint('StockRealtime all parse: $e');
        }
      },
    );
    channel.subscribe();
    return StockRealtimeSubscription._(client, channel);
  }

  /// Cadangan client-side bila trigger DB belum deploy.
  static Future<void> broadcastToko({
    required String tokoId,
    String? sku,
    int? stock,
    int? reservedQty,
    int? availableQty,
  }) async {
    final toko = tokoId.trim().toUpperCase();
    if (toko.isEmpty) return;
    final client = Supabase.instance.client;
    final channel = client.channel(topicForToko(toko));
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
      await ready.future.timeout(const Duration(seconds: 6));
      await channel.sendBroadcastMessage(
        event: 'stock_changed',
        payload: {
          'toko_id': toko,
          if (sku != null) 'sku': sku.trim().toUpperCase(),
          if (stock != null) 'stock': stock,
          if (reservedQty != null) 'reserved_qty': reservedQty,
          if (availableQty != null) 'available_qty': availableQty,
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    } catch (_) {
      // Trigger DB / postgres_changes tetap jadi jalur utama.
    } finally {
      try {
        await client.removeChannel(channel);
      } catch (_) {}
    }
  }
}

class StockRealtimeSubscription {
  StockRealtimeSubscription._(this._client, this._channel);

  final SupabaseClient _client;
  final RealtimeChannel _channel;
  bool _closed = false;

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _client.removeChannel(_channel);
    } catch (_) {}
  }
}
