import '../attendance/attendance_admin_scope.dart';
import '../brand/brand_service.dart';
import '../brand/brand_slug_rules.dart';
import '../logistics/product_identity.dart';
import '../tenant/tenant_service.dart';

/// Aturan laporan PDF: satu tenant, nama file dari slug, uang JSON.
abstract final class ExportReportRules {
  /// Tabel dump tanpa kolom `tenant_id` — jangan `.eq('tenant_id')`.
  static const tablesWithoutTenantId = {
    'sales_items',
    'versi_app',
  };

  static int moneyOf(Object? raw) => ProductIdentity.moneyOf(raw);

  static int countOf(Object? raw) => ProductIdentity.countOf(raw);

  static bool sameStore(String? a, String? b) =>
      AttendanceAdminScope.sameTokoId(a, b);

  static bool isPusatToko(String? tokoId) =>
      AttendanceAdminScope.isPusatTokoId(tokoId);

  /// Pusat / owner / admin_pusat / super_admin. Cabang biasa tidak.
  static bool canExportPusat({
    String? tokoId,
    String? role,
    Map<String, dynamic>? profile,
  }) {
    final p = profile ??
        {
          'toko_id': tokoId,
          'role': role,
        };
    if (AttendanceAdminScope.isPusatOperator(p)) return true;
    return isPusatToko(AttendanceAdminScope.tokoOf(p));
  }

  /// `optik-briski` → `OptikBriski`. Bukan hardcode OptikBRiski.
  static String fileBrandPrefix({String? slug, String? displayName}) {
    final s = BrandSlugRules.normalize(slug);
    if (s.isNotEmpty) {
      final parts = s
          .split(RegExp(r'[^a-z0-9]+'))
          .where((p) => p.isNotEmpty)
          .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
          .join();
      if (parts.isNotEmpty) return parts;
    }
    final name = (displayName ?? '').trim();
    if (name.isEmpty) return 'Laporan';
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return cleaned.isEmpty ? 'Laporan' : cleaned;
  }

  static String fileBrandPrefixFromSession() {
    final slug = TenantService.instance.slug;
    if (slug.trim().isNotEmpty) {
      return fileBrandPrefix(slug: slug, displayName: BrandService.name);
    }
    return fileBrandPrefix(displayName: BrandService.name);
  }

  static String shareFallbackName() =>
      '${fileBrandPrefixFromSession()}_laporan.pdf';

  /// Snapshot `versi_app` per saluran slug. Optik: slug resmi atau warisan null.
  static bool versiAppBelongsToSlug(String? rowSlug, String tenantSlug) {
    final row = BrandSlugRules.normalize(rowSlug);
    final slug = BrandSlugRules.normalize(tenantSlug);
    if (slug.isEmpty) return false;
    if (BrandSlugRules.isOptikSlug(slug)) {
      return row.isEmpty || BrandSlugRules.isOptikSlug(row);
    }
    return row == slug;
  }

  static bool tableUsesTenantId(String table) =>
      !tablesWithoutTenantId.contains(table);
}
