import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'module_catalog.dart';
import 'tenant_service.dart';

/// Hak modul tenant. Etalase menulis `tenant_modules`; APK toko membaca ini.
///
/// Fail-open hanya jika RPC belum ada (migrasi lama) **dan** bukan APK Store,
/// atau sesi belum terikat tenant. Setelah load sukses: hanya modul `enabled`.
class TenantModules extends ChangeNotifier {
  TenantModules._();
  static final TenantModules instance = TenantModules._();

  final Set<String> _enabled = {};
  bool loaded = false;
  bool storefront = false;
  String? planKey;
  String? industryKey;
  String? slug;
  String? displayName;
  bool whiteLabel = false;
  String shell = 'rekasa_shared';

  bool allows(String moduleKey) {
    if (storefront || isRekasaStorefront) return false;
    if (!loaded) return true;
    return _enabled.contains(moduleKey);
  }

  Set<String> get enabledKeys => Set.unmodifiable(_enabled);

  List<String> get enabledLabels {
    final byKey = {for (final m in moduleCatalog) m.key: m.label};
    final keys = _enabled.toList()..sort();
    return [for (final k in keys) byKey[k] ?? k];
  }

  static String labelForPlan(String? key) {
    switch ((key ?? '').toLowerCase()) {
      case 'paket_a':
        return 'Paket A — Pro';
      case 'paket_b':
        return 'Paket B — Bisnis';
      case 'paket_c':
        return 'Paket C — Starter';
      default:
        return (key ?? '').trim().isEmpty ? 'Paket' : key!;
    }
  }

  String get planLabel => labelForPlan(planKey);

  String get shellHint {
    final s = (slug ?? '').trim();
    if (storefront || shell == 'rekasa_store') {
      return 'Ini APK etalase Rekasa. Kasir klien = APK Admin/Karyawan yang dibeli.';
    }
    if (whiteLabel || shell == 'white_label') {
      return 'Paket merek sendiri. Menu = fitur yang dinyalakan di etalase'
          '${s.isEmpty ? '' : ' untuk kode $s'}.';
    }
    return 'Pakai APK Rekasa Admin/Karyawan, login isi kode usaha'
        '${s.isEmpty ? '' : ' $s'}. Menu = fitur yang dibeli/dinyalakan.';
  }

  /// Teks struk: APK mana yang di-install setelah beli.
  static String installHint({
    required bool whiteLabel,
    required String slug,
  }) {
    final s = slug.trim();
    if (whiteLabel) {
      return 'Setelah lunas Rekasa kirim APK/web merek sendiri '
          '(bukan APK etalase ini). Menu di APK itu = fitur yang baru dinyalakan'
          '${s.isEmpty ? '.' : '. Kode usaha: $s.'}';
    }
    return 'Install APK Rekasa Admin/Karyawan — bukan APK etalase ini. '
        'Login isi kode usaha${s.isEmpty ? '' : ' $s'}. '
        'Menu yang muncul = fitur yang dibeli/dinyalakan. '
        'Upgrade nanti cukup login ulang, bukan ganti APK.';
  }

  /// APK etalase: jangan buka menu kasir.
  void sealStorefront() {
    storefront = true;
    loaded = true;
    _enabled.clear();
    planKey = null;
    industryKey = null;
    slug = null;
    displayName = null;
    whiteLabel = false;
    shell = 'rekasa_store';
    notifyListeners();
  }

  Future<void> load({SupabaseClient? client}) async {
    if (isRekasaStorefront) {
      sealStorefront();
      return;
    }
    storefront = false;
    try {
      final db = client ?? Supabase.instance.client;
      try {
        final raw = await db.rpc('my_tenant_entitlements');
        if (raw is Map && raw['ok'] == true) {
          _applyEntitlements(Map<String, dynamic>.from(raw));
          loaded = true;
          notifyListeners();
          return;
        }
        // anon / no_tenant: tetap fail-open sampai login bind.
        if (raw is Map && raw['ok'] == false) {
          loaded = false;
          _enabled.clear();
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('my_tenant_entitlements: $e');
      }

      final raw = await db.rpc('list_my_tenant_modules');
      _enabled.clear();
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          if (e['enabled'] == true) {
            final k = (e['module_key'] ?? '').toString().trim();
            if (k.isNotEmpty) _enabled.add(k);
          }
        }
      }
      if (_enabled.isEmpty && !TenantService.instance.isBound) {
        loaded = false;
      } else {
        loaded = true;
      }
    } catch (e) {
      debugPrint('tenant_modules: $e');
      loaded = false;
      _enabled.clear();
    }
    notifyListeners();
  }

  void _applyEntitlements(Map<String, dynamic> raw) {
    if (raw['platform'] == true) {
      storefront = true;
      _enabled.clear();
      shell = 'rekasa_store';
      planKey = null;
      industryKey = null;
      slug = null;
      displayName = null;
      whiteLabel = false;
      return;
    }
    planKey = raw['plan_key']?.toString();
    industryKey = raw['industry_key']?.toString();
    slug = raw['slug']?.toString();
    displayName = raw['display_name']?.toString();
    whiteLabel = raw['white_label'] == true;
    shell = (raw['shell'] ?? 'rekasa_shared').toString();
    _enabled.clear();
    final mods = raw['modules'];
    if (mods is List) {
      for (final e in mods) {
        if (e is! Map) continue;
        if (e['enabled'] == true) {
          final k = (e['module_key'] ?? '').toString().trim();
          if (k.isNotEmpty) _enabled.add(k);
        }
      }
    }
  }

  @visibleForTesting
  void debugReset() {
    loaded = false;
    storefront = false;
    _enabled.clear();
    planKey = null;
    industryKey = null;
    slug = null;
    displayName = null;
    whiteLabel = false;
    shell = 'rekasa_shared';
  }

  @visibleForTesting
  void debugApplyEnabled(Set<String> keys) {
    loaded = true;
    storefront = false;
    _enabled
      ..clear()
      ..addAll(keys);
  }

  @visibleForTesting
  void debugApplyEntitlements(Map<String, dynamic> raw) {
    loaded = true;
    storefront = false;
    _applyEntitlements(raw);
  }
}
