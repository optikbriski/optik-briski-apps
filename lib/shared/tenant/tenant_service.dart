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

  /// Tenant #1 (kulit Optik). Bukan default platform.
  static const optikSlug = 'optik-briski';
  static const optikId = '00000000-0000-0000-0000-000000000001';
  /// Kulit Rekasa sampai kode usaha diisi.
  static const defaultSlug = '';
  static const _prefsKey = 'tenant_scope_v1';

  String? id;
  String slug = defaultSlug;
  String? displayName;
  String? shortName;
  String? assistantName;
  String? pusatTokoId;
  bool isPlatform = false;

  /// Alasan resolve terakhir (`suspend`, `trial`, `not_found`, …).
  String? lastResolveReason;
  String? lastResolveError;

  bool get isBound => id != null && id!.isNotEmpty;

  static const suspendedMessage =
      'Langganan ditangguhkan. Tagihan belum dibayar pada hari H — '
      'sistem dimatikan sampai lunas. Data toko tidak dihapus. Hubungi Rekasa.';

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
    if (isRekasaStorefront) {
      slug = '';
      id = null;
      displayName = null;
      shortName = null;
      assistantName = null;
      return;
    }
    if (isBrandedStoreApk) {
      slug = brandedStoreSlug;
      return;
    }
    slug = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_prefsKey) ?? '').trim();
      if (saved.isNotEmpty) slug = saved;
    } catch (_) {}
  }

  /// Member / Karyawan APK = satu merek. Isi dalam app tetap sama.
  Future<void> bindBrandedStoreApk({SupabaseClient? client}) async {
    await persistSlug(brandedStoreSlug);
    await resolveSlug(brandedStoreSlug, client: client);
  }

  /// Tolak sesi/akun yang bukan merek APK ini.
  bool storeMatchesApk(String? tenantId, {bool platform = false}) {
    if (platform || isPlatform) return true;
    if (!isBrandedStoreApk || !isBound) return true;
    final t = (tenantId ?? '').trim();
    if (t.isEmpty) return true;
    return t == id;
  }

  bool memberMatchesApk(String? memberTenantId) =>
      storeMatchesApk(memberTenantId);

  Future<void> persistSlug(String next) async {
    final t = next.trim().toLowerCase();
    if (t.isEmpty) {
      slug = isBrandedStoreApk ? brandedStoreSlug : '';
    } else {
      slug = t;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (slug.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, slug);
      }
    } catch (_) {}
  }

  /// Resolusi kode usaha (anon-safe). Gagal = false, [id] tidak diubah ke Optik.
  Future<bool> resolveSlug(String raw, {SupabaseClient? client}) async {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) {
      if (!isBrandedStoreApk) return false;
      s = brandedStoreSlug.trim().toLowerCase();
    }
    if (s.isEmpty) return false;
    lastResolveReason = null;
    lastResolveError = null;
    try {
      final db = client ?? Supabase.instance.client;
      final res = await db.rpc('resolve_tenant', params: {'p_slug': s});
      if (res is! Map) return false;
      if (res['ok'] != true) {
        lastResolveReason = res['reason']?.toString() ?? res['status']?.toString();
        lastResolveError = res['error']?.toString();
        return false;
      }
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
      lastResolveError = '$e';
      return false;
    }
  }

  /// Wajib berhasil. Jangan lanjut login/RPC jika kode usaha salah.
  Future<void> requireResolved({
    String? slug,
    SupabaseClient? client,
  }) async {
    final raw = (slug ?? this.slug).trim();
    if (raw.isEmpty && !isBrandedStoreApk) {
      throw StateError(
        'Isi kode usaha dulu. Tanpa itu data merek lain tidak boleh dibuka.',
      );
    }
    final ok = await resolveSlug(
      raw.isEmpty ? brandedStoreSlug : raw,
      client: client,
    );
    if (!ok || !isBound) {
      final reason = lastResolveReason;
      final err = (lastResolveError ?? '').trim();
      if (reason == 'suspend' || reason == 'trial') {
        throw StateError(err.isNotEmpty ? err : suspendedMessage);
      }
      throw StateError(
        err.isNotEmpty
            ? err
            : 'Kode usaha tidak valid atau tidak aktif. Cek ejaan, jangan pakai kode usaha lain.',
      );
    }
  }

  Future<void> bindFromProfile(
    Map<String, dynamic>? profile, {
    SupabaseClient? client,
  }) async {
    if (profile == null) return;
    final tid = (profile['tenant_id'] ?? '').toString().trim();
    if (tid.isNotEmpty && storeMatchesApk(tid)) id = tid;
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
    if (isRekasaStorefront) return;
    if (isBound) return;
    if (!isBrandedStoreApk && slug.trim().isEmpty) return;
    await resolveSlug(
      isBrandedStoreApk ? brandedStoreSlug : slug,
      client: client,
    );
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
    lastResolveReason = null;
    lastResolveError = null;
  }

  @visibleForTesting
  void debugBind(String tenantId, {String slug = optikSlug}) {
    id = tenantId;
    this.slug = slug;
  }
}

/// Inject `p_tenant_id` ke RPC. Gagal jika tenant belum terverifikasi.
Map<String, dynamic> withTenant(Map<String, dynamic> params) {
  params['p_tenant_id'] = TenantService.instance.boundId;
  return params;
}
