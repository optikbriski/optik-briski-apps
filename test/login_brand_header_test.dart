import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/brand/brand_service.dart';
import 'package:optik_b_riski/shared/config.dart';
import 'package:optik_b_riski/shared/widgets/app_brand_mark.dart';
import 'package:optik_b_riski/shared/widgets/login_brand_header.dart';

void main() {
  tearDown(() {
    BrandService.bind(AppBrand.shellFallback);
  });

  test('unpinned Rekasa shell does not use Optik logo on login', () {
    expect(isBrandedStoreApk, isFalse);
    expect(LoginBrandHeader.showOptikLogo, isFalse);
    expect(LoginBrandHeader.tenantHeadline, isNull);
    expect(AppBrandMark.showOptikLogo, isFalse);
  });

  test('Rekasa fallback name is never used as a tenant headline', () {
    BrandService.bind(AppBrand.rekasaShell);
    expect(BrandService.name.toUpperCase(), contains('REKASA'));
    expect(LoginBrandHeader.nameLooksLikeRekasa, isTrue);
    expect(LoginBrandHeader.tenantHeadline, isNull);
    expect(AppBrandMark.showOptikLogo, isFalse);
  });

  test('in-app chrome shows Optik only after that brand is bound', () {
    BrandService.bind(AppBrand.rekasaShell);
    expect(AppBrandMark.showOptikLogo, isFalse);
    BrandService.bind(AppBrand.fallback);
    expect(AppBrandMark.showOptikLogo, isTrue);
  });
}
