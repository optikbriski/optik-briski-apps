import 'package:flutter/material.dart';

import '../brand/brand_service.dart';
import '../config.dart';
import '../tenant/tenant_service.dart';
import 'optik_brand_logo.dart';
import 'rekasa_mark.dart';

/// Header login: merek yang tampil, tanpa Rekasa menindih kulit lain.
///
/// - Kulit Rekasa / konsol tanpa pin: lockup Rekasa saja.
/// - Paket A Optik: logo Optik saja. Tanpa judul Rekasa.
/// - Paket A merek lain: nama merek saja. Tanpa logo Optik, tanpa Rekasa.
class LoginBrandHeader extends StatelessWidget {
  const LoginBrandHeader({
    super.key,
    this.logoHeight = 56,
    this.nameColor,
    this.nameSize = 22,
  });

  final double logoHeight;
  final Color? nameColor;
  final double nameSize;

  static bool get nameLooksLikeRekasa {
    final n = BrandService.name.trim().toUpperCase();
    return n.isEmpty || n == 'REKASA' || n.contains('REKASA KARYA');
  }

  static bool get showOptikLogo {
    if (!isBrandedStoreApk) return false;
    if (brandedStoreSlug == TenantService.optikSlug) return true;
    return BrandService.name.toUpperCase().contains('OPTIK B');
  }

  /// Nama kulit toko. Null = jangan tulis judul (logo sudah cukup / Rekasa).
  static String? get tenantHeadline {
    if (!isBrandedStoreApk) return null;
    if (showOptikLogo) return null;
    if (nameLooksLikeRekasa) {
      final slug = brandedStoreSlug.trim();
      if (slug.isEmpty) return null;
      return slug;
    }
    return BrandService.name;
  }

  @override
  Widget build(BuildContext context) {
    if (!isBrandedStoreApk) {
      return RekasaMark(height: logoHeight);
    }
    if (showOptikLogo) {
      return OptikBrandLogo.color(height: logoHeight);
    }
    final headline = tenantHeadline;
    if (headline == null) {
      return SizedBox(height: logoHeight * 0.2);
    }
    return ValueListenableBuilder<int>(
      valueListenable: BrandService.revision,
      builder: (_, __, ___) => Text(
        tenantHeadline ?? headline,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: nameColor,
          fontWeight: FontWeight.w800,
          fontSize: nameSize,
          letterSpacing: -0.3,
          height: 1.15,
        ),
      ),
    );
  }
}
