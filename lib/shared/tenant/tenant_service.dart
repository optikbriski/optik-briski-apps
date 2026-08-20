import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'toko_ids.dart';

/// Sekat UMKM. Satu login = satu tenant. Bukan cabang Optik.
///
/// Fail-closed: jangan pernah diam-diam memakai tenant Optik jika kode
/// usaha gagal di-resolve. Kebocoran katalog/member/uang antar UMKM fatal.
class TenantService {
  TenantService._();
  static final TenantService instance = TenantService._();

  static const optikId = '00000000-0000-0000-0000-000000000001';
  static const defaultSlug = 'optik-briski';
  static const _prefsKey = 'tenant_scope_v1';

  String? id;
  String slug = defaultSlug;
  String? displayName;
  String? shortName;
  String? assistantName;
  String? pusatTokoId;
  bool isPlatform = false;

  bool get isBound => id != null && id!.isNotEmpty;

  /// UUID tenant yang sudah di-resolve. Lempar jika belum — jangan fallback.
  String get boundId {
    final v = id;
    if (v == null || v.isEmpty) {
      throw StateError(unboundMessage);
    }
    return v;
  }

  static const unboundMessage =
      'Kode usaha belum terverifikasi. Tidak boleh memakai data usaha lain.';

  Future<void> loadLocal() async {
    if (isBrandedMemberApk) {
      slug = memberTenantSlug;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_prefsKey) ?? '').trim();
      if (saved.isNotEmpty) slug = saved;
    } catch (_) {}
    if (slug.isEmpty) slug = defaultSlug;
  }

  /// APK Member = satu merek. Pelanggan tidak pilih kode usaha.
  Future<void> bindBrandedMemberApk({SupabaseClient? client}) async {
    await persistSlug(memberTenantSlug);
    await resolveSlug(memberTenantSlug, client: client);
  }

  /// Tolak sesi/akun yang bukan merek APK ini.
  bool memberMatchesApk(String? memberTenantId) {
    if (!isBrandedMemberApk || !isBound) return true;
    final t = (memberTenantId ?? '').trim();
    if (t.isEmpty) return true;
    return t == id;
  }

  Future<void> persistSlug(String next) async {
    slug = next.trim().isEmpty ? defaultSlug : next.trim().toLowerCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, slug);
    } catch (_) {}
  }

  /// Resolusi kode usaha (anon-safe). Gagal = false, [id] tidak diubah ke Optik.
  Future<bool> resolveSlug(String raw, {SupabaseClient? client}) async {
    final s = raw.trim().isEmpty ? defaultSlug : raw.trim().toLowerCase();
    try {
      final db = client ?? Supabase.instance.client;
      final res = await db.rpc('resolve_tenant', params: {'p_slug': s});
      if (res is! Map) return false;
      if (res['ok'] != true) return false;
      final nextId = res['id']?.toString();
      if (nextId == null || nextId.isEmpty) return false;
      id = nextId;
      slug = (res['slug'] ?? s).toString();
      displayName = res['display_name']?.toString();
      shortName = res['short_name']?.toString();
      assistantName = res['assistant_name']?.toString();
      pusatTokoId = res['pusat_toko_id']?.toString();
      await persistSlug(slug);
      return true;
    } catch (e) {
      debugPrint('resolve_tenant: $e');
      return false;
    }
  }

  /// Wajib berhasil. Jangan lanjut login/RPC jika kode usaha salah.
  Future<void> requireResolved({
    String? slug,
    SupabaseClient? client,
  }) async {
    final raw = (slug ?? this.slug).trim();
    final ok = await resolveSlug(raw.isEmpty ? defaultSlug : raw, client: client);
    if (!ok || !isBound) {
      throw StateError(
        'Kode usaha tidak valid atau tidak aktif. Cek ejaan, jangan pakai kode usaha lain.',
      );
    }
  }

  Future<void> bindFromProfile(
    Map<String, dynamic>? profile, {
    SupabaseClient? client,
  }) async {
    if (profile == null) return;
    final tid = (profile['tenant_id'] ?? '').toString().trim();
    if (tid.isNotEmpty) id = tid;
    final plat = profile['is_platform'];
    isPlatform = plat == true ||
        plat == 'true' ||
        (profile['role'] ?? '').toString().toLowerCase() == 'platform';
    final toko = (profile['toko_id'] ?? '').toString().trim();
    if (TokoIds.isPusat(toko)) {
      pusatTokoId = toko.toUpperCase();
    }
    if (id != null && id!.isNotEmpty) {
      await _hydrateFromTable(client);
    }
  }

  Future<void> bindFromMember(Map<String, dynamic>? member) async {
    if (member == null) return;
    final tid = (member['tenant_id'] ?? '').toString().trim();
    if (tid.isEmpty) return;
    if (!memberMatchesApk(tid)) return;
    id = tid;
  }

  Future<void> _hydrateFromTable(SupabaseClient? client) async {
    final tid = id;
    if (tid == null || tid.isEmpty) return;
    try {
      final db = client ?? Supabase.instance.client;
      final row = await db
          .from('tenants')
          .select('id, slug, legal_name, pusat_toko_id')
          .eq('id', tid)
          .maybeSingle();
      if (row == null) return;
      slug = (row['slug'] ?? slug).toString();
      displayName ??= row['legal_name']?.toString();
      final pusat = (row['pusat_toko_id'] ?? '').toString().trim();
      if (pusat.isNotEmpty) pusatTokoId = pusat;
      await persistSlug(slug);
    } catch (e) {
      debugPrint('tenant hydrate: $e');
    }
  }

  /// Coba resolve slug tersimpan. Gagal = tetap unbound (bukan Optik).
  Future<void> ensureResolved({SupabaseClient? client}) async {
    if (isBound) return;
    await resolveSlug(slug, client: client);
  }

  void clearSessionTenant() {
    isPlatform = false;
  }

  /// Tes: lepas binding tanpa mengutak-atik prefs.
  @visibleForTesting
  void debugUnbind() {
    id = null;
    displayName = null;
    shortName = null;
    assistantName = null;
    pusatTokoId = null;
    isPlatform = false;
  }

  @visibleForTesting
  void debugBind(String tenantId, {String slug = defaultSlug}) {
    id = tenantId;
    this.slug = slug;
  }
}

/// Inject `p_tenant_id` ke RPC. Gagal jika tenant belum terverifikasi.
Map<String, dynamic> withTenant(Map<String, dynamic> params) {
  params['p_tenant_id'] = TenantService.instance.boundId;
  return params;
}
