import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../whatsapp_launcher.dart';

/// Channel Realtime Broadcast per nomor WA Member (tanpa bergantung RLS tabel).
class MemberRealtime {
  MemberRealtime._();

  static const eventOrderUpdate = 'order_update';

  /// Normalisasi ke 62… agar admin & Member selalu sekanal.
  static String topicForPhone(String phone) {
    var d = normalizeWaNumber(phone);
    if (d.startsWith('0') && d.length >= 9) {
      d = '62${d.substring(1)}';
    }
    return 'obr-member-$d';
  }

  /// Kirim sinyal instan ke APK Member yang subscribe topic ini.
  static Future<void> broadcastOrderUpdate({
    required String phone,
    required String invoice,
    String? title,
    String? body,
    String? kind,
    String? onlineOrderId,
  }) async {
    final topic = topicForPhone(phone);
    if (!topic.startsWith('obr-member-') || topic.length < 16) return;

    final client = Supabase.instance.client;
    final channel = client.channel(topic);
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
      final oid = (onlineOrderId ?? '').trim();
      await channel.sendBroadcastMessage(
        event: eventOrderUpdate,
        payload: {
          'no_invoice': invoice,
          if (title != null) 'title': title,
          if (body != null) 'body': body,
          if (kind != null) 'kind': kind,
          if (oid.isNotEmpty) 'online_order_id': oid,
          'ts': DateTime.now().toUtc().toIso8601String(),
        },
      );
      // Biarkan frame sempat terkirim sebelum channel ditutup.
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (_) {
      // Poll / inbox tetap jadi fallback.
    } finally {
      try {
        await client.removeChannel(channel);
      } catch (_) {}
    }
  }
}
