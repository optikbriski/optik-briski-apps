import 'package:flutter/material.dart';

import '../brand/brand_service.dart';
import '../config.dart';
import '../tenant/tenant_service.dart';
import 'optik_brand_logo.dart';
import 'rekasa_mark.dart';

/// Header login: merek toko yang tampil, bukan Rekasa menindih kulit lain.
///
/// - Kulit Rekasa / konsol tanpa pin: lockup Rekasa saja.
/// - Paket A Optik: logo + nama Optik. Tanpa judul Rekasa.
/// - Paket A merek lain: nama merek saja. Tanpa logo Optik, tanpa Rekasa besar.
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

  static bool get showOptikLogo {
    if (!isBrandedStoreApk) return false;
    if (brandedStoreSlug == TenantService.optikSlug) return true;
    return BrandService.name.toUpperCase().contains('OPTIK B');
  }

  @override
  Widget build(BuildContext context) {
    if (!isBrandedStoreApk) {
      return RekasaMark(height: logoHeight);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showOptikLogo) ...[
          OptikBrandLogo.color(height: logoHeight),
          SizedBox(height: logoHeight >= 50 ? 10 : 8),
        ],
        ValueListenableBuilder<int>(
          valueListenable: BrandService.revision,
          builder: (_, __, ___) => Text(
            BrandService.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: nameColor,
              fontWeight: FontWeight.w800,
              fontSize: nameSize,
              letterSpacing: -0.3,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}
