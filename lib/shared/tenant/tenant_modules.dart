import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modul langganan tenant. Gagal load = buka semua (migrasi belum di-apply).
class TenantModules extends ChangeNotifier {
  TenantModules._();
  static final TenantModules instance = TenantModules._();

  final Set<String> _enabled = {};
  bool loaded = false;

  bool allows(String moduleKey) {
    if (!loaded) return true;
    return _enabled.contains(moduleKey);
  }

  Future<void> load({SupabaseClient? client}) async {
    try {
      final raw = await (client ?? Supabase.instance.client)
          .rpc('list_my_tenant_modules');
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
      loaded = true;
    } catch (e) {
      debugPrint('tenant_modules: $e');
      loaded = false;
      _enabled.clear();
    }
    notifyListeners();
  }
}
