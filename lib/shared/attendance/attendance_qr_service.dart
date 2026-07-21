import 'package:supabase_flutter/supabase_flutter.dart';

import 'attendance_config.dart';

class AttendanceQrIssue {
  const AttendanceQrIssue({
    required this.id,
    required this.tokoId,
    required this.token,
    required this.payload,
    required this.expiresAt,
    required this.ttlSeconds,
  });

  final String id;
  final String tokoId;
  final String token;
  final String payload;
  final DateTime expiresAt;
  final int ttlSeconds;

  factory AttendanceQrIssue.fromJson(Map<String, dynamic> json) {
    return AttendanceQrIssue(
      id: (json['id'] ?? '').toString(),
      tokoId: (json['toko_id'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      payload: (json['payload'] ?? '').toString(),
      expiresAt: DateTime.parse(json['expires_at'].toString()).toLocal(),
      ttlSeconds: (json['ttl_seconds'] as num?)?.toInt() ??
          AttendanceConfig.qrTtlSeconds,
    );
  }
}

class AttendanceQrValidation {
  const AttendanceQrValidation({
    required this.tokenId,
    required this.tokoId,
    required this.expiresAt,
  });

  final String tokenId;
  final String tokoId;
  final DateTime expiresAt;

  factory AttendanceQrValidation.fromJson(Map<String, dynamic> json) {
    return AttendanceQrValidation(
      tokenId: (json['token_id'] ?? '').toString(),
      tokoId: (json['toko_id'] ?? '').toString(),
      expiresAt: DateTime.parse(json['expires_at'].toString()).toLocal(),
    );
  }
}

/// Issue / validate token QR absensi (RPC Supabase).
class AttendanceQrService {
  AttendanceQrService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AttendanceQrIssue> issueToken({
    required String tokoId,
    int? ttlSeconds,
  }) async {
    try {
      final res = await _client.rpc(
        'issue_attendance_qr_token',
        params: {
          'p_toko_id': tokoId,
          'p_ttl_seconds': ttlSeconds ?? AttendanceConfig.qrTtlSeconds,
        },
      );
      final map = _asMap(res);
      if (map == null || (map['payload'] ?? '').toString().isEmpty) {
        throw 'Gagal membuat QR absensi.';
      }
      return AttendanceQrIssue.fromJson(map);
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  Future<AttendanceQrValidation> validatePayload(String raw) async {
    try {
      final res = await _client.rpc(
        'validate_attendance_qr_token',
        params: {'p_payload': raw.trim()},
      );
      final map = _asMap(res);
      if (map == null || map['ok'] != true) {
        throw 'QR absensi tidak valid.';
      }
      return AttendanceQrValidation.fromJson(map);
    } on PostgrestException catch (e) {
      throw _rpcMessage(e);
    }
  }

  Map<String, dynamic>? _asMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  String _rpcMessage(PostgrestException e) {
    final m = e.message.trim();
    if (m.isNotEmpty) return m;
    return e.details?.toString() ?? 'Gagal memproses QR absensi.';
  }
}
