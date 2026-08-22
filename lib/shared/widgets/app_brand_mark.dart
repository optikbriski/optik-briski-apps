import 'package:flutter/material.dart';

import '../brand/brand_service.dart';
import '../config.dart';
import '../tenant/tenant_service.dart';
import 'optik_brand_logo.dart';
import 'rekasa_mark.dart';

/// Logo chrome: Rekasa di kulit bersama, Optik hanya jika mereknya Optik.
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({
    super.key,
    this.height = 28,
    this.onDark = false,
  });

  final double height;
  final bool onDark;

  static bool get showOptikLogo {
    if (isBrandedStoreApk && brandedStoreSlug == TenantService.optikSlug) {
      return true;
    }
    return AppBrand.looksLikeOptikName(BrandService.name);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BrandService.revision,
      builder: (_, __, ___) {
        if (showOptikLogo) {
          return onDark
              ? OptikBrandLogo.white(height: height)
              : OptikBrandLogo.color(height: height);
        }
        if (!isBrandedStoreApk ||
            LoginBrandLooks.rekasa(BrandService.name)) {
          return RekasaMark(
            height: height,
            wordmarkColor: onDark ? Colors.white : null,
          );
        }
        return Text(
          BrandService.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: onDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
            fontSize: height * 0.42,
            letterSpacing: -0.3,
            height: 1.1,
          ),
        );
      },
    );
  }
}

class LoginBrandLooks {
  static bool rekasa(String name) {
    final n = name.trim().toUpperCase();
    return n.isEmpty || n == 'REKASA' || n.contains('REKASA KARYA');
  }
}
