import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/bootstrap.dart';
import '../../shared/tenant/industry_catalog.dart';
import '../../shared/tenant/module_catalog.dart';
import '../../shared/tenant/tenant_modules.dart';

enum StoreAccountKind { none, platform, owner, staff }

class StoreAuth {
  StoreAuth._();

  static bool isPlatform(Map<String, dynamic>? p) {
    if (p == null) return false;
    final v = p['is_platform'];
    final role = (p['role'] ?? '').toString().toLowerCase();
    return v == true || v == 'true' || role == 'platform';
  }

  static StoreAccountKind kind(Map<String, dynamic>? p) {
    if (p == null) return StoreAccountKind.none;
    if (isPlatform(p)) return StoreAccountKind.platform;
    final role = (p['role'] ?? '').toString().toLowerCase();
    if (const {'karyawan', 'kasir', 'member', 'front', 'back'}.contains(role)) {
      return StoreAccountKind.staff;
    }
    final tid = (p['tenant_id'] ?? '').toString().trim();
    if (tid.isEmpty) return StoreAccountKind.none;
    return StoreAccountKind.owner;
  }

  static String staffMessage =
      'Kasir dan staf masuk di APK Admin/Karyawan yang dibeli — bukan portal ini.';

  static String unboundMessage =
      'Akun belum diikat ke usaha. Setelah beli, Rekasa kirim akses owner.';
}

class StoreAccountSnapshot {
  const StoreAccountSnapshot({
    required this.ok,
    this.platform = false,
    this.reason,
    this.error,
    this.tenantId,
    this.displayName,
    this.slug,
    this.status,
    this.planKey,
    this.industryKey,
    this.whiteLabel = false,
    this.shell = 'rekasa_shared',
    this.modules = const [],
    this.invoices = const [],
    this.contracts = const [],
    this.unsignedContractToken,
  });

  final bool ok;
  final bool platform;
  final String? reason;
  final String? error;
  final String? tenantId;
  final String? displayName;
  final String? slug;
  final String? status;
  final String? planKey;
  final String? industryKey;
  final bool whiteLabel;
  final String shell;
  final List<Map<String, dynamic>> modules;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> contracts;
  final String? unsignedContractToken;

  String get brandLabel {
    final n = (displayName ?? '').trim();
    if (n.isNotEmpty) return n;
    final s = (slug ?? '').trim();
    return s.isEmpty ? 'Usaha Anda' : s;
  }

  String get planLabel => TenantModules.labelForPlan(planKey);

  String get industryLabel =>
      industryByKey(industryKey)?.label ?? (industryKey ?? 'Usaha');

  String get statusLabel {
    switch ((status ?? '').toLowerCase()) {
      case 'aktif':
        return 'Aktif';
      case 'suspend':
        return 'Ditangguhkan';
      case 'trial':
        return 'Uji coba';
      default:
        return (status ?? '').trim().isEmpty ? '—' : status!;
    }
  }

  List<String> get enabledModuleLabels {
    final byKey = {for (final m in moduleCatalog) m.key: m.label};
    final keys = <String>[];
    for (final e in modules) {
      if (e['enabled'] != true) continue;
      final k = (e['module_key'] ?? '').toString().trim();
      if (k.isNotEmpty) keys.add(byKey[k] ?? k);
    }
    keys.sort();
    return keys;
  }

  factory StoreAccountSnapshot.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const StoreAccountSnapshot(ok: false, reason: 'unknown');
    }
    final map = Map<String, dynamic>.from(raw);
    return StoreAccountSnapshot(
      ok: map['ok'] == true,
      platform: map['platform'] == true,
      reason: map['reason']?.toString(),
      error: map['error']?.toString(),
      tenantId: map['tenant_id']?.toString(),
      displayName: map['display_name']?.toString(),
      slug: map['slug']?.toString(),
      status: map['status']?.toString(),
      planKey: map['plan_key']?.toString(),
      industryKey: map['industry_key']?.toString(),
      whiteLabel: map['white_label'] == true,
      shell: (map['shell'] ?? 'rekasa_shared').toString(),
      modules: _maps(map['modules']),
      invoices: _maps(map['invoices']),
      contracts: _maps(map['contracts']),
      unsignedContractToken: map['unsigned_contract_token']?.toString(),
    );
  }

  static List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
}

class StoreAccount {
  StoreAccount._();

  static Future<StoreAccountSnapshot> load({SupabaseClient? client}) async {
    try {
      final raw = await (client ?? supabase).rpc('my_tenant_account');
      return StoreAccountSnapshot.fromRpc(raw);
    } catch (e) {
      debugPrint('my_tenant_account: $e');
      return StoreAccountSnapshot(
        ok: false,
        reason: 'rpc_missing',
        error:
            'SQL 000012 belum di-apply. Portal akun owner perlu my_tenant_account().',
      );
    }
  }
}
