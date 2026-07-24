import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Login Admin via kode TOTP unik per karyawan (Edge Function).
abstract final class AdminCodeLoginService {
  static const edgeFunctionName = 'admin-login-with-code';
  static const prefsActorJson = 'admin_login_code_actor_v1';

  /// Hasil login: sesi terpasang + identitas karyawan pemberi kode.
  static Future<AdminCodeLoginActor> signInWithCode({
    required String email,
    required String code,
  }) async {
    final client = Supabase.instance.client;
    try {
      final res = await client.functions.invoke(
        edgeFunctionName,
        body: {
          'email': email.trim().toLowerCase(),
          'code': code.replaceAll(RegExp(r'\D'), ''),
        },
      );

      final map = _asMap(res.data);
      if (map == null) {
        throw 'Respons login kode tidak valid.';
      }
      if (map['error'] != null) {
        throw map['error'].toString();
      }

      final refresh = (map['refresh_token'] ?? '').toString();
      if (refresh.isEmpty) {
        throw 'Sesi tidak lengkap dari server.';
      }

      await client.auth.setSession(refresh);
      if (client.auth.currentSession == null) {
        throw 'Gagal memasang sesi login.';
      }

      final actorMap = _asMap(map['actor']);
      final actor = AdminCodeLoginActor.fromJson(actorMap ?? const {});
      await saveActor(actor);
      return actor;
    } on FunctionException catch (e) {
      throw _errorFromFunctionException(e);
    }
  }

  static Future<void> saveActor(AdminCodeLoginActor actor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsActorJson, jsonEncode(actor.toJson()));
  }

  static Future<AdminCodeLoginActor?> loadActor() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsActorJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        return AdminCodeLoginActor.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearActor() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsActorJson);
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String _errorFromFunctionException(FunctionException e) {
    final details = e.details;
    final map = _asMap(details);
    if (map != null && map['error'] != null) {
      return map['error'].toString();
    }
    if (details is String && details.trim().isNotEmpty) {
      return details;
    }
    return e.reasonPhrase?.isNotEmpty == true
        ? e.reasonPhrase!
        : 'Login kode gagal (${e.status}).';
  }
}

class AdminCodeLoginActor {
  const AdminCodeLoginActor({
    this.karyawanId,
    this.nama,
    this.tokoId,
    this.jabatan,
    this.auditId,
  });

  final String? karyawanId;
  final String? nama;
  final String? tokoId;
  final String? jabatan;
  final String? auditId;

  bool get isPresent =>
      (karyawanId != null && karyawanId!.isNotEmpty) ||
      (nama != null && nama!.isNotEmpty);

  String get label {
    final n = (nama ?? '').trim();
    final t = (tokoId ?? '').trim();
    final j = (jabatan ?? '').trim();
    if (n.isEmpty) return 'Karyawan';
    final parts = <String>[n];
    if (j.isNotEmpty) parts.add(j);
    if (t.isNotEmpty) parts.add(t);
    return parts.join(' • ');
  }

  Map<String, dynamic> toJson() => {
        'karyawan_id': karyawanId,
        'nama': nama,
        'toko_id': tokoId,
        'jabatan': jabatan,
        'audit_id': auditId,
      };

  factory AdminCodeLoginActor.fromJson(Map<String, dynamic> json) {
    return AdminCodeLoginActor(
      karyawanId: (json['karyawan_id'] ?? '').toString().nullIfEmpty,
      nama: (json['nama'] ?? '').toString().nullIfEmpty,
      tokoId: (json['toko_id'] ?? '').toString().nullIfEmpty,
      jabatan: (json['jabatan'] ?? '').toString().nullIfEmpty,
      auditId: (json['audit_id'] ?? '').toString().nullIfEmpty,
    );
  }
}

extension on String {
  String? get nullIfEmpty => trim().isEmpty ? null : this;
}
