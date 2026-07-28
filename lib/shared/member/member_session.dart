import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../whatsapp_launcher.dart';

/// Sesi Member lokal (HP terverifikasi OTP).
class MemberSession extends ChangeNotifier {
  MemberSession._();
  static final MemberSession instance = MemberSession._();

  static const _prefsKey = 'member_session_v1';

  String? phoneE164;
  String? phoneRaw;
  String? memberId;
  String? nama;
  String? email;
  String? alamat;
  double fontScale = 1.0;
  String locale = 'id';
  bool loaded = false;

  bool get isLoggedIn =>
      (phoneE164 != null && phoneE164!.isNotEmpty) ||
      (phoneRaw != null && phoneRaw!.trim().isNotEmpty);

  String get phoneForQuery =>
      phoneE164 ?? normalizeWaNumber(phoneRaw ?? '');

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        phoneE164 = m['phone_e164']?.toString();
        phoneRaw = m['phone_raw']?.toString();
        memberId = m['id']?.toString();
        nama = m['nama']?.toString();
        email = m['email']?.toString();
        alamat = m['alamat']?.toString();
        fontScale = double.tryParse('${m['font_scale'] ?? 1}') ?? 1.0;
        locale = m['locale']?.toString() ?? 'id';
      } catch (_) {}
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> applyMember(Map<String, dynamic> member) async {
    phoneE164 = member['phone_e164']?.toString();
    phoneRaw = member['phone_raw']?.toString() ?? phoneRaw;
    memberId = member['id']?.toString();
    nama = member['nama']?.toString();
    email = member['email']?.toString();
    alamat = member['alamat']?.toString();
    fontScale = double.tryParse('${member['font_scale'] ?? fontScale}') ?? 1.0;
    locale = member['locale']?.toString() ?? locale;
    await _persist();
    notifyListeners();
  }

  Future<void> updateLocal({
    String? nama,
    String? email,
    String? alamat,
    double? fontScale,
    String? locale,
  }) async {
    if (nama != null) this.nama = nama;
    if (email != null) this.email = email;
    if (alamat != null) this.alamat = alamat;
    if (fontScale != null) this.fontScale = fontScale;
    if (locale != null) this.locale = locale;
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    phoneE164 = null;
    phoneRaw = null;
    memberId = null;
    nama = null;
    email = null;
    alamat = null;
    fontScale = 1.0;
    locale = 'id';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'id': memberId,
        'phone_e164': phoneE164,
        'phone_raw': phoneRaw,
        'nama': nama,
        'email': email,
        'alamat': alamat,
        'font_scale': fontScale,
        'locale': locale,
      }),
    );
  }
}
