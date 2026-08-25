import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_admin_scope.dart';

/// Realtime refresh sinyal untuk inbox antrian toko.
class TokoAntrianRealtime {
  TokoAntrianRealtime._();

  /// Dengarkan perubahan sumber antrian di [tokoId].
  /// Panggil [TokoAntrianRealtimeSubscription.dispose] saat halaman ditutup.
  static TokoAntrianRealtimeSubscription subscribeToko({
    required String tokoId,
    required VoidCallback onChanged,
    Duration debounce = const Duration(milliseconds: 450),
  }) {
    final toko = tokoId.trim().toUpperCase();
    final aliases = AttendanceAdminScope.storeIdAliases(toko)
        .map((e) => e.trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (aliases.isEmpty && toko.isNotEmpty) aliases.add(toko);

    final client = Supabase.instance.client;
    final topic =
        'obr-antrian-${toko.isEmpty ? 'x' : toko}-${DateTime.now().microsecondsSinceEpoch}';
    final channel = client.channel(topic);

    Timer? debounceTimer;
    void poke() {
      debounceTimer?.cancel();
      debounceTimer = Timer(debounce, onChanged);
    }

    bool tokoMatch(Map<String, dynamic> row) {
      if (aliases.isEmpty) return true;
      final rowToko = (row['toko_id'] ?? '').toString().trim().toUpperCase();
      if (rowToko.isEmpty) return true;
      return aliases.contains(rowToko);
    }

    void onRow(PostgresChangePayload payload) {
      try {
        final row = payload.newRecord.isNotEmpty
            ? payload.newRecord
            : payload.oldRecord;
        if (row.isEmpty) {
          poke();
          return;
        }
        if (tokoMatch(Map<String, dynamic>.from(row))) poke();
      } catch (e) {
        debugPrint('TokoAntrianRealtime parse: $e');
        poke();
      }
    }

    for (final table in const [
      'sales',
      'online_orders',
      'member_bookings',
      'garansi_klaim_request',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: onRow,
      );
    }

    channel.subscribe();
    return TokoAntrianRealtimeSubscription._(channel, () {
      debounceTimer?.cancel();
    });
  }
}

class TokoAntrianRealtimeSubscription {
  TokoAntrianRealtimeSubscription._(this._channel, this._onDispose);

  final RealtimeChannel _channel;
  final void Function() _onDispose;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
    try {
      await Supabase.instance.client.removeChannel(_channel);
    } catch (e) {
      debugPrint('TokoAntrianRealtime dispose: $e');
    }
  }
}
