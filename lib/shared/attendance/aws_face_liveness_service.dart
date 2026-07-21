import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'attendance_config.dart';

class AwsLivenessCredentials {
  const AwsLivenessCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    this.expiration,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final String? expiration;

  Map<String, dynamic> toJson() => {
        'accessKeyId': accessKeyId,
        'secretAccessKey': secretAccessKey,
        'sessionToken': sessionToken,
        if (expiration != null) 'expiration': expiration,
      };

  factory AwsLivenessCredentials.fromJson(Map<String, dynamic> json) {
    return AwsLivenessCredentials(
      accessKeyId: (json['accessKeyId'] ?? '').toString(),
      secretAccessKey: (json['secretAccessKey'] ?? '').toString(),
      sessionToken: (json['sessionToken'] ?? '').toString(),
      expiration: json['expiration']?.toString(),
    );
  }
}

class AwsLivenessSession {
  const AwsLivenessSession({
    required this.sessionId,
    required this.region,
    required this.credentials,
    required this.minConfidence,
    this.uiPath = 'aws-face-liveness/ui',
  });

  final String sessionId;
  final String region;
  final AwsLivenessCredentials credentials;
  final double minConfidence;
  final String uiPath;
}

class AwsLivenessResults {
  const AwsLivenessResults({
    required this.passed,
    required this.sessionId,
    required this.confidence,
    required this.status,
    required this.minConfidence,
    this.referenceImageBytes,
    this.error,
  });

  final bool passed;
  final String sessionId;
  final double confidence;
  final String status;
  final double minConfidence;
  final Uint8List? referenceImageBytes;
  final String? error;
}

/// Client ke Edge Function [AttendanceConfig.edgeFunctionName].
class AwsFaceLivenessService {
  AwsFaceLivenessService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get uiUrl {
    final base = supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/functions/v1/${AttendanceConfig.edgeFunctionName}/ui';
  }

  Future<AwsLivenessSession> createSession() async {
    final data = await _invoke({'action': 'create_session'});
    final credsRaw = data['credentials'];
    if (credsRaw is! Map) {
      throw 'Respons create_session tanpa credentials.';
    }
    final sessionId = (data['session_id'] ?? '').toString();
    final region = (data['region'] ?? 'ap-southeast-1').toString();
    if (sessionId.isEmpty) {
      throw 'SessionId kosong dari AWS.';
    }
    return AwsLivenessSession(
      sessionId: sessionId,
      region: region,
      credentials: AwsLivenessCredentials.fromJson(
        Map<String, dynamic>.from(credsRaw),
      ),
      minConfidence: (data['min_confidence'] as num?)?.toDouble() ??
          AttendanceConfig.minLivenessConfidence,
      uiPath: (data['ui_path'] ?? 'aws-face-liveness/ui').toString(),
    );
  }

  Future<AwsLivenessResults> getResults(String sessionId) async {
    try {
      final data = await _invoke({
        'action': 'get_results',
        'session_id': sessionId,
      });
      return _parseResults(data);
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map) {
        return _parseResults(Map<String, dynamic>.from(details));
      }
      rethrow;
    }
  }

  AwsLivenessResults _parseResults(Map<String, dynamic> data) {
    final refB64 = data['reference_image_base64']?.toString();
    Uint8List? bytes;
    if (refB64 != null && refB64.isNotEmpty) {
      try {
        bytes = base64Decode(refB64);
      } catch (_) {
        bytes = null;
      }
    }
    return AwsLivenessResults(
      passed: data['passed'] == true || data['ok'] == true,
      sessionId: (data['session_id'] ?? '').toString(),
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      status: (data['status'] ?? '').toString(),
      minConfidence: (data['min_confidence'] as num?)?.toDouble() ??
          AttendanceConfig.minLivenessConfidence,
      referenceImageBytes: bytes,
      error: data['error']?.toString(),
    );
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(
        AttendanceConfig.edgeFunctionName,
        body: body,
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
      throw 'Respons Edge Function tidak valid.';
    } on FunctionException catch (e) {
      final msg = _extractError(e);
      throw _friendlyAwsError(msg);
    } catch (e) {
      throw _friendlyAwsError(e.toString());
    }
  }

  String _friendlyAwsError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('aws secrets') ||
        s.contains('kredensial') ||
        s.contains('aws_liveness') ||
        s.contains('not configured') ||
        s.contains('secret') ||
        s.contains('credential') ||
        s.contains('accessdenied') ||
        s.contains('unauthorized') ||
        s.contains('404') ||
        s.contains('failed to fetch') ||
        s.contains('clientexception')) {
      return 'AWS Face Liveness belum siap. '
          'Akun AWS / secrets Supabase belum dikonfigurasi. '
          'Sementara absensi memakai liveness lokal '
          '(set AttendanceConfig.useAwsFaceLiveness = false).';
    }
    return raw;
  }

  String _extractError(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    if (details is String && details.isNotEmpty) return details;
    return e.reasonPhrase?.isNotEmpty == true
        ? e.reasonPhrase!
        : 'Gagal memanggil AWS Face Liveness (${e.status}).';
  }
}
