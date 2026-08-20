import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'toko_ids.dart';

/// Sekat UMKM. Satu login = satu tenant. Bukan cabang Optik.
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

  String get boundId => id ?? optikId;

  Future<void> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_prefsKey) ?? '').trim();
      if (saved.isNotEmpty) slug = saved;
    } catch (_) {}
    if (slug.isEmpty) slug = defaultSlug;
  }

  Future<void> persistSlug(String next) async {
    slug = next.trim().isEmpty ? defaultSlug : next.trim().toLowerCase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, slug);
    } catch (_) {}
  }

  /// Resolusi kode usaha (anon-safe).
  Future<bool> resolveSlug(String raw, {SupabaseClient? client}) async {
    final s = raw.trim().isEmpty ? defaultSlug : raw.trim().toLowerCase();
    try {
      final db = client ?? Supabase.instance.client;
      final res = await db.rpc('resolve_tenant', params: {'p_slug': s});
      if (res is! Map) return false;
      if (res['ok'] != true) return false;
      id = res['id']?.toString();
      slug = (res['slug'] ?? s).toString();
      displayName = res['display_name']?.toString();
      shortName = res['short_name']?.toString();
      assistantName = res['assistant_name']?.toString();
      pusatTokoId = res['pusat_toko_id']?.toString();
      await persistSlug(slug);
      return id != null && id!.isNotEmpty;
    } catch (e) {
      debugPrint('resolve_tenant: $e');
      return false;
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
    if (tid.isNotEmpty) id = tid;
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

  Future<void> ensureResolved({SupabaseClient? client}) async {
    if (isBound) return;
    final ok = await resolveSlug(slug, client: client);
    if (!ok) {
      id = optikId;
      slug = defaultSlug;
      pusatTokoId ??= TokoIds.optikPusat;
    }
  }

  void clearSessionTenant() {
    isPlatform = false;
  }
}

/// Inject `p_tenant_id` ke RPC member / directory.
Map<String, dynamic> withTenant(Map<String, dynamic> params) {
  params['p_tenant_id'] = TenantService.instance.boundId;
  return params;
}
