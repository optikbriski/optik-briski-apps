import 'package:flutter_test/flutter_test.dart';

import 'package:optik_b_riski/shared/brand/brand_service.dart';

void main() {
  tearDown(() {
    BrandService.bind(AppBrand.shellFallback);
  });

  test('bind locks storefront to Rekasa; Optik fallback is skin-only', () {
    BrandService.bind(AppBrand.fallback);
    expect(BrandService.name, 'Optik B. Riski');

    BrandService.bind(AppBrand.rekasaShell);
    expect(BrandService.name, 'Rekasa');
    expect(BrandService.shortName, 'RKS');
    expect(BrandService.assistantName, 'Asisten');
  });
}
