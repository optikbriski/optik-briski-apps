import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tenant/tenant_service.dart';
import '../tenant/toko_ids.dart';

/// Merek tenant (bukan nama cabang). Nama toko = `invoice_settings.shop_name`.
class AppBrand {
  const AppBrand({
    required this.displayName,
    required this.shortName,
    required this.assistantName,
  });

  final String displayName;
  final String shortName;
  final String assistantName;

  /// Hanya fallback offline / sebelum row `app_brand` ada.
  static const fallback = AppBrand(
    displayName: 'Optik B. Riski',
    shortName: 'OBR',
    assistantName: 'OBRA',
  );
}

class BrandService {
  BrandService._();

  static AppBrand _current = AppBrand.fallback;

  static AppBrand get current => _current;
  static String get name => _current.displayName;
  static String get shortName => _current.shortName;
  static String get assistantName => _current.assistantName;

  /// Naik setiap [load] selesai supaya judul jendela/tab rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> load({SupabaseClient? client}) async {
    try {
      final db = client ?? Supabase.instance.client;
      await TenantService.instance.ensureResolved(client: db);
      final t = TenantService.instance;
      if (!t.isBound) {
        // Jangan tampilkan merek Optik untuk slug usaha lain yang gagal resolve.
        if (t.slug != TenantService.defaultSlug) {
          final label = t.slug.trim().isEmpty ? 'POS' : t.slug;
          _current = AppBrand(
            displayName: label,
            shortName: label,
            assistantName: 'Asisten',
          );
        }
        return;
      }
      final fromRpc = (t.displayName ?? '').trim();
      if (fromRpc.isNotEmpty) {
        _current = AppBrand(
          displayName: fromRpc,
          shortName: (t.shortName ?? '').trim().isEmpty
              ? AppBrand.fallback.shortName
              : t.shortName!.trim(),
          assistantName: (t.assistantName ?? '').trim().isEmpty
              ? AppBrand.fallback.assistantName
              : t.assistantName!.trim(),
        );
      }
      final row = await db
          .from('app_brand')
          .select('display_name, short_name, assistant_name')
          .eq('tenant_id', t.boundId)
          .maybeSingle();
      final data = row;
      if (data == null) return;
      final name = (data['display_name'] ?? '').toString().trim();
      if (name.isEmpty) return;
      final short = (data['short_name'] ?? '').toString().trim();
      final assistant = (data['assistant_name'] ?? '').toString().trim();
      _current = AppBrand(
        displayName: name,
        shortName: short.isEmpty ? AppBrand.fallback.shortName : short,
        assistantName:
            assistant.isEmpty ? AppBrand.fallback.assistantName : assistant,
      );
    } catch (_) {
      // Tetap fallback — app boleh jalan offline / sebelum migrasi.
    } finally {
      revision.value++;
    }
  }

  /// Label struk jika `shop_name` cabang belum diisi di Supabase.
  static String defaultShopName(String? tokoId) {
    final id = _normalizeTokoId(tokoId);
    final brand = name.trim().toUpperCase();
    if (TokoIds.isPusat(id, tenantPusatTokoId: TenantService.instance.pusatTokoId)) {
      return '$brand PUSAT';
    }
    var label = id;
    if (label.startsWith('CABANG-')) {
      label = label.substring('CABANG-'.length);
    } else if (label.startsWith('CABANG_')) {
      label = label.substring('CABANG_'.length);
    } else if (label.startsWith('CABANG ')) {
      label = label.substring('CABANG '.length);
    }
    label = label.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    while (label.contains('  ')) {
      label = label.replaceAll('  ', ' ');
    }
    if (label.isEmpty) label = id;
    return '$brand $label';
  }

  static bool looksGenericShopName(String shopName, String tokoId) {
    final id = _normalizeTokoId(tokoId);
    final brand = name.trim().toUpperCase();
    final current = shopName.trim().toUpperCase();
    return current.isEmpty ||
        current == brand ||
        current == '$brand PUSAT' ||
        current == 'OPTIK B. RISKI' ||
        current == 'OPTIK B. RISKI PUSAT' ||
        (id != 'PUSAT' && current.contains('PUSAT'));
  }

  static String _normalizeTokoId(String? raw) {
    final t = (raw ?? '').trim().toUpperCase();
    return t.isEmpty ? 'PUSAT' : t;
  }
}

extension BrandTranslation on String {
  String brandTr({Map<String, String>? namedArgs}) => tr(
        this,
        namedArgs: {
          'brand': BrandService.name,
          'assistant': BrandService.assistantName,
          ...?namedArgs,
        },
      );
}
