import 'package:supabase_flutter/supabase_flutter.dart';

class TokoChatService {
  TokoChatService({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  Future<List<Map<String, dynamic>>> listRecent(String tokoId, {int limit = 80}) async {
    final rows = await _db
        .from('toko_chat_messages')
        .select()
        .eq('toko_id', tokoId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List).reversed.toList();
  }

  Future<void> send({
    required String tokoId,
    required String nama,
    required String isi,
    String? karyawanId,
  }) async {
    final body = isi.trim();
    if (body.isEmpty) throw 'Pesan kosong.';
    if (body.length > 1000) throw 'Pesan terlalu panjang.';
    await _db.from('toko_chat_messages').insert({
      'toko_id': tokoId,
      'sender_karyawan_id': karyawanId,
      'sender_nama': nama.trim().isEmpty ? 'Admin' : nama.trim(),
      'isi': body,
    });
  }

  RealtimeChannel subscribe(
    String tokoId,
    void Function(Map<String, dynamic> row) onInsert,
  ) {
    return _db
        .channel('toko-chat-$tokoId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'toko_chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'toko_id',
            value: tokoId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            onInsert(Map<String, dynamic>.from(row));
          },
        )
        .subscribe();
  }
}
