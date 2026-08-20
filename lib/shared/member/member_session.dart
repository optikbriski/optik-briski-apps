import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../whatsapp_launcher.dart';
import '../tenant/tenant_service.dart';
import 'member_shop_address.dart';

/// Sesi Member lokal (HP terverifikasi OTP).
class MemberSession extends ChangeNotifier {
  MemberSession._();
  static final MemberSession instance = MemberSession._();

  static const _prefsKey = 'member_session_v1';

  String? phoneE164;
  String? phoneRaw;
  String? memberId;
  String? tenantId;
  String? nama;
  String? email;
  String? alamat;
  DateTime? tanggalLahir;
  /// Cabang pilihan Member (Beranda / booking).
  String? preferredTokoId;
  double fontScale = 1.0;
  String locale = 'id';
  bool loaded = false;

  bool get isLoggedIn =>
      (phoneE164 != null && phoneE164!.isNotEmpty) ||
      (phoneRaw != null && phoneRaw!.trim().isNotEmpty);

  String get phoneForQuery =>
      phoneE164 ?? normalizeWaNumber(phoneRaw ?? '');

  /// Kunci bucket alamat Belanja Online (anti-bocor antar akun).
  String get shopAddressOwnerKey {
    final id = (memberId ?? '').trim();
    if (id.isNotEmpty) return 'm_$id';
    final e164 = (phoneE164 ?? '').trim();
    if (e164.isNotEmpty) return 'p_$e164';
    final raw = (phoneRaw ?? '').trim();
    if (raw.isNotEmpty) return 'r_$raw';
    return 'guest';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        phoneE164 = m['phone_e164']?.toString();
        phoneRaw = m['phone_raw']?.toString();
        memberId = m['id']?.toString();
        tenantId = m['tenant_id']?.toString();
        nama = m['nama']?.toString();
        email = m['email']?.toString();
        alamat = m['alamat']?.toString();
        tanggalLahir = _parseDate(m['tanggal_lahir']);
        preferredTokoId = m['preferred_toko_id']?.toString();
        fontScale = double.tryParse('${m['font_scale'] ?? 1}') ?? 1.0;
        locale = m['locale']?.toString() ?? 'id';
      } catch (_) {}
    }
    loaded = true;
    if (!TenantService.instance.memberMatchesApk(tenantId)) {
      await logout();
      return;
    }
    // Alamat dulu, baru notify — UI jangan sempat baca bucket akun lama.
    await MemberShopAddress.instance.syncOwner(shopAddressOwnerKey);
    if ((tenantId ?? '').trim().isNotEmpty) {
      await TenantService.instance.bindFromMember({'tenant_id': tenantId});
    }
    notifyListeners();
  }

  Future<void> applyMember(Map<String, dynamic> member) async {
    if (!TenantService.instance.memberMatchesApk(member['tenant_id']?.toString())) {
      throw StateError(
        'Akun ini bukan member ${TenantService.instance.displayName ?? TenantService.instance.slug}.',
      );
    }
    phoneE164 = member['phone_e164']?.toString();
    phoneRaw = member['phone_raw']?.toString() ?? phoneRaw;
    memberId = member['id']?.toString();
    tenantId = member['tenant_id']?.toString() ?? tenantId;
    nama = member['nama']?.toString();
    email = member['email']?.toString();
    alamat = member['alamat']?.toString();
    final dob = _parseDate(member['tanggal_lahir']);
    if (dob != null) tanggalLahir = dob;
    fontScale = double.tryParse('${member['font_scale'] ?? fontScale}') ?? 1.0;
    locale = member['locale']?.toString() ?? locale;
    await _persist();
    await MemberShopAddress.instance.syncOwner(shopAddressOwnerKey);
    if ((tenantId ?? '').trim().isNotEmpty) {
      await TenantService.instance.bindFromMember({'tenant_id': tenantId});
    }
    notifyListeners();
  }

  Future<void> updateLocal({
    String? nama,
    String? email,
    String? alamat,
    String? phoneRaw,
    DateTime? tanggalLahir,
    String? preferredTokoId,
    double? fontScale,
    String? locale,
  }) async {
    if (nama != null) this.nama = nama;
    if (email != null) this.email = email;
    if (alamat != null) this.alamat = alamat;
    if (phoneRaw != null) this.phoneRaw = phoneRaw;
    if (tanggalLahir != null) this.tanggalLahir = tanggalLahir;
    if (preferredTokoId != null) this.preferredTokoId = preferredTokoId;
    if (fontScale != null) this.fontScale = fontScale;
    if (locale != null) this.locale = locale;
    await _persist();
    notifyListeners();
  }

  Future<void> setPreferredToko(String? tokoId) async {
    preferredTokoId = (tokoId == null || tokoId.trim().isEmpty)
        ? null
        : tokoId.trim().toUpperCase();
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    phoneE164 = null;
    phoneRaw = null;
    memberId = null;
    tenantId = null;
    nama = null;
    email = null;
    alamat = null;
    tanggalLahir = null;
    preferredTokoId = null;
    fontScale = 1.0;
    locale = 'id';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await MemberShopAddress.instance.syncOwner(shopAddressOwnerKey);
    notifyListeners();
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'id': memberId,
        'tenant_id': tenantId,
        'phone_e164': phoneE164,
        'phone_raw': phoneRaw,
        'nama': nama,
        'email': email,
        'alamat': alamat,
        'tanggal_lahir': tanggalLahir?.toIso8601String().substring(0, 10),
        'preferred_toko_id': preferredTokoId,
        'font_scale': fontScale,
        'locale': locale,
      }),
    );
  }
}
