import '../config.dart';
import '../tenant/tenant_service.dart';

/// Slug merek: data toko vs saluran APK. Jangan campur.
abstract final class BrandSlugRules {
  static const rekasaChannel = 'rekasa';

  static String normalize(String? raw) => (raw ?? '').trim().toLowerCase();

  /// Kulit Optik hanya slug/pin resmi — bukan nama yang kebetulan "Optik B…".
  static bool isOptikSlug(String? slug) =>
      normalize(slug) == TenantService.optikSlug;

  static bool isOptikDisplayName(String? name) {
    final n = (name ?? '').trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    return n == 'OPTIK B. RISKI' || n == 'OPTIK B RISKI';
  }

  /// Saluran update APK = binary yang terpasang, bukan kode usaha login.
  /// APK bersama → `rekasa`. APK merek sendiri → slug pin.
  static String releaseChannel({
    bool? branded,
    String? brandedSlug,
  }) {
    final pin = branded ?? isBrandedStoreApk;
    if (!pin) return rekasaChannel;
    final s = normalize(brandedSlug ?? brandedStoreSlug);
    return s.isEmpty ? rekasaChannel : s;
  }

  /// `optik-karyawan-1.3.1.apk` → slug optik-briski (warisan).
  /// `rekasa-admin-1.0.0.apk` / `warung-sari-member-1.0.0.apk` → slug file.
  static ({String slug, String flavor, String versi})? parseReleaseFilename(
    String objectName,
  ) {
    final base = objectName.split('/').last.trim().toLowerCase();
    final m = RegExp(
      r'^([a-z0-9]+(?:-[a-z0-9]+)*)-(karyawan|admin|member)-'
      r'([0-9]+\.[0-9]+\.[0-9]+)\.apk$',
    ).firstMatch(base);
    if (m == null) return null;
    var slug = m.group(1)!;
    if (slug == 'optik') slug = TenantService.optikSlug;
    return (slug: slug, flavor: m.group(2)!, versi: m.group(3)!);
  }
}
